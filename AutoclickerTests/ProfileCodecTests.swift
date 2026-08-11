import Foundation
#if canImport(Testing)
import Testing
#endif
#if !TEST_RUNNER
@testable import Autoclicker
#endif

@Suite("Profile encoding and persistence")
struct ProfileCodecTests {
    private func tempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("autoclicker-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("A profile round-trips through JSON exactly")
    func roundTrip() throws {
        var profile = Profile.humanizedPreset
        profile.trigger = .mouseButton(number: 3)
        profile.inputBehavior = .suppress
        profile.sequence = [
            SequenceStep(action: .leftClick),
            SequenceStep(action: .randomDelay(minMS: 10, maxMS: 90)),
            SequenceStep(action: .repeatGroup(count: 2, steps: [
                SequenceStep(action: .moveCursor(x: 10.5, y: 20.25)),
                SequenceStep(action: .mouseDown(button: 4)),
                SequenceStep(action: .mouseUp(button: 4)),
            ])),
            SequenceStep(action: .returnToOrigin),
        ]
        profile.targeting.points = [SavedPoint(name: "A", x: 100, y: 200)]
        profile.safety.maxClicks = 500
        profile.humanizedRapid.seed = 77

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(Profile.self, from: data)
        #expect(decoded == profile)
    }

    @Test("Keyboard triggers round-trip with modifiers")
    func triggerCodable() throws {
        let trigger = TriggerInput.keyboard(keyCode: 97, modifiers: [.command, .shift])
        let data = try JSONEncoder().encode(trigger)
        #expect(try JSONDecoder().decode(TriggerInput.self, from: data) == trigger)
    }

    @Test("Profiles persist across store instances")
    func persistence() {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        var createdID: UUID?
        do {
            let store = ProfileStore(directory: dir)
            let profile = store.createProfile(named: "Persisted")
            createdID = profile.id
            store.saveNow()
        }
        let reloaded = ProfileStore(directory: dir)
        #expect(reloaded.profiles.contains { $0.id == createdID })
        #expect(reloaded.selectedProfileID == createdID)
    }

    @Test("A fresh store contains the six default presets")
    func defaults() {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProfileStore(directory: dir)
        let names = store.profiles.map(\.name)
        for expected in ["Rapid Click", "Precision Click", "Hold to Click",
                         "Controlled Burst", "Humanized", "Coordinate Cycle"] {
            #expect(names.contains(expected))
        }
    }

    @Test("Import rejects invalid JSON and foreign structures")
    func importValidation() {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProfileStore(directory: dir)
        let before = store.profiles.count
        #expect(throws: (any Error).self) {
            try store.importProfile(from: Data("not json at all".utf8))
        }
        #expect(throws: (any Error).self) {
            try store.importProfile(from: Data(#"{"foo": 1}"#.utf8))
        }
        #expect(store.profiles.count == before)
    }

    @Test("Export → import creates an independent copy")
    func exportImport() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProfileStore(directory: dir)
        let original = store.profiles[0]
        let data = try store.exportData(for: original)
        let imported = try store.importProfile(from: data)
        #expect(imported.id != original.id, "imported profiles get a fresh identity")
        #expect(imported.mode == original.mode)
        #expect(imported.name != original.name, "name is de-duplicated")
    }

    @Test("Imported values are sanitized into safe ranges")
    func importSanitization() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProfileStore(directory: dir)
        var hostile = Profile()
        hostile.name = "   "
        hostile.speed.clicksPerSecond = 1_000_000 // absurd rate
        hostile.speed.randomMinMS = -50
        hostile.humanizedRapid.minIntervalMS = 900
        hostile.humanizedRapid.maxIntervalMS = 5 // inverted bounds
        let imported = try store.importProfile(from: JSONEncoder().encode(hostile))
        #expect(!imported.name.trimmingCharacters(in: .whitespaces).isEmpty)
        #expect(imported.speed.clicksPerSecond <= 1000)
        #expect(imported.speed.randomMinMS >= SpeedConfig.absoluteMinimumIntervalMS)
        #expect(imported.humanizedRapid.minIntervalMS <= imported.humanizedRapid.maxIntervalMS)
    }

    @Test("A corrupt store file recovers without crashing")
    func corruptStoreRecovery() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Damaged container with one valid profile inside.
        let valid = try String(data: JSONEncoder().encode(Profile.rapidClick), encoding: .utf8)!
        let damaged = #"{"version": 1, "profiles": [\#(valid), {"broken": true}]}"#
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(damaged.utf8).write(to: dir.appendingPathComponent("profiles.json"))
        let store = ProfileStore(directory: dir)
        #expect(store.profiles.count == 1)
        #expect(store.profiles[0].name == "Rapid Click")
        #expect(store.selectedProfileID == store.profiles[0].id)
    }

    @Test("Garbage store file falls back to defaults")
    func garbageStoreFallback() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data([0xFF, 0x00, 0x12]).write(to: dir.appendingPathComponent("profiles.json"))
        let store = ProfileStore(directory: dir)
        #expect(store.profiles.count == Profile.defaultProfiles().count)
    }

    @Test("Deleting the last profile restores defaults (never an empty store)")
    func deleteAll() {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProfileStore(directory: dir)
        for profile in store.profiles { store.delete(profile.id) }
        #expect(!store.profiles.isEmpty)
        #expect(store.selectedProfileID != nil)
    }

    @Test("Duplicate creates unique ids for profile and sequence steps")
    func duplicateIdentity() {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProfileStore(directory: dir)
        var profile = store.profiles[0]
        profile.sequence = [SequenceStep(action: .leftClick)]
        store.update(profile)
        let copy = store.duplicate(profile)
        #expect(copy.id != profile.id)
        #expect(copy.sequence[0].id != profile.sequence[0].id)
        #expect(copy.sequence[0].action == profile.sequence[0].action)
    }

    @Test("App settings sanitize unknown themes and out-of-range values")
    func settingsSanitize() {
        var settings = AppSettings()
        settings.themeID = "does-not-exist"
        settings.glowIntensity = 42
        settings.interfaceScale = 9
        let clean = settings.sanitized()
        #expect(HUDThemeID(rawValue: clean.themeID) != nil)
        #expect(clean.glowIntensity <= 1)
        #expect(clean.interfaceScale <= 1.4)
    }
}
