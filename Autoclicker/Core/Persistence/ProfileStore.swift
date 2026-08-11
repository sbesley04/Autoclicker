import Foundation
import Combine

/// Owns the profile list: persistence, CRUD, selection, JSON import/export.
/// Files live under Application Support/Autoclicker/. All public API is
/// main-thread; disk writes are debounced onto a background queue.
final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [Profile] = []
    @Published var selectedProfileID: UUID? {
        didSet { scheduleSave() }
    }

    var selectedProfile: Profile? {
        profiles.first { $0.id == selectedProfileID }
    }

    private let directory: URL
    private var fileURL: URL { directory.appendingPathComponent("profiles.json") }
    private let saveQueue = DispatchQueue(label: "com.autoclicker.profile-store", qos: .utility)
    private var saveWorkItem: DispatchWorkItem?

    private struct StoreFile: Codable {
        var version: Int = 1
        var selectedProfileID: UUID?
        var profiles: [Profile]
    }

    init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory()
        load()
    }

    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Autoclicker", isDirectory: true)
    }

    // MARK: - Loading

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            restoreDefaults()
            return
        }
        let decoder = JSONDecoder()
        if let store = try? decoder.decode(StoreFile.self, from: data), !store.profiles.isEmpty {
            profiles = store.profiles.map { $0.sanitized() }
            selectedProfileID = store.selectedProfileID.flatMap { id in
                profiles.contains { $0.id == id } ? id : nil
            } ?? profiles.first?.id
        } else if let recovered = Self.recoverProfiles(from: data), !recovered.isEmpty {
            // Partial recovery: the container was damaged but individual
            // profile objects may still decode.
            profiles = recovered
            selectedProfileID = profiles.first?.id
            scheduleSave()
        } else {
            restoreDefaults()
        }
    }

    /// Tries to salvage individual profiles from a damaged store file.
    private static func recoverProfiles(from data: Data) -> [Profile]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawProfiles = object["profiles"] as? [Any] else { return nil }
        let decoder = JSONDecoder()
        var recovered: [Profile] = []
        for raw in rawProfiles {
            if let itemData = try? JSONSerialization.data(withJSONObject: raw),
               let profile = try? decoder.decode(Profile.self, from: itemData) {
                recovered.append(profile.sanitized())
            }
        }
        return recovered
    }

    // MARK: - CRUD

    @discardableResult
    func createProfile(named name: String = "New Profile") -> Profile {
        var profile = Profile()
        profile.name = uniqueName(from: name)
        profiles.append(profile)
        selectedProfileID = profile.id
        scheduleSave()
        return profile
    }

    @discardableResult
    func duplicate(_ profile: Profile) -> Profile {
        var copy = profile
        copy.id = UUID()
        copy.name = uniqueName(from: "\(profile.name) Copy")
        // Give copied sequence steps fresh identities.
        copy.sequence = Self.reidentify(copy.sequence)
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles.insert(copy, at: index + 1)
        } else {
            profiles.append(copy)
        }
        selectedProfileID = copy.id
        scheduleSave()
        return copy
    }

    func rename(_ profileID: UUID, to newName: String) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        profiles[index].name = trimmed
        scheduleSave()
    }

    func delete(_ profileID: UUID) {
        profiles.removeAll { $0.id == profileID }
        if profiles.isEmpty {
            restoreDefaults()
        } else if selectedProfileID == profileID {
            selectedProfileID = profiles.first?.id
        }
        scheduleSave()
    }

    /// Replace a profile wholesale (the editor screens call this on change).
    func update(_ profile: Profile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
        scheduleSave()
    }

    func restoreDefaults() {
        profiles = Profile.defaultProfiles()
        selectedProfileID = profiles.first?.id
        scheduleSave()
    }

    private func uniqueName(from base: String) -> String {
        var name = base
        var counter = 2
        while profiles.contains(where: { $0.name == name }) {
            name = "\(base) \(counter)"
            counter += 1
        }
        return name
    }

    private static func reidentify(_ steps: [SequenceStep]) -> [SequenceStep] {
        steps.map { step in
            var copy = step
            copy.id = UUID()
            if case .repeatGroup(let count, let inner) = copy.action {
                copy.action = .repeatGroup(count: count, steps: reidentify(inner))
            }
            return copy
        }
    }

    // MARK: - Import / export

    enum ImportError: LocalizedError {
        case unreadable
        case invalidFormat(String)

        var errorDescription: String? {
            switch self {
            case .unreadable: return "The file could not be read."
            case .invalidFormat(let detail): return "Not a valid profile file: \(detail)"
            }
        }
    }

    func exportData(for profile: Profile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(profile)
    }

    @discardableResult
    func importProfile(from data: Data) throws -> Profile {
        let decoder = JSONDecoder()
        var profile: Profile
        do {
            profile = try decoder.decode(Profile.self, from: data)
        } catch let error as DecodingError {
            throw ImportError.invalidFormat(Self.describe(error))
        } catch {
            throw ImportError.unreadable
        }
        profile = profile.sanitized()
        profile.id = UUID() // never collide with an existing profile
        profile.name = uniqueName(from: profile.name)
        profile.sequence = Self.reidentify(profile.sequence)
        profiles.append(profile)
        selectedProfileID = profile.id
        scheduleSave()
        return profile
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _): return "missing field '\(key.stringValue)'"
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return context.debugDescription
        case .dataCorrupted(let context): return context.debugDescription
        @unknown default: return "unrecognized structure"
        }
    }

    // MARK: - Saving

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let snapshot = StoreFile(
            selectedProfileID: selectedProfileID, profiles: profiles)
        let url = fileURL
        let dir = directory
        let item = DispatchWorkItem {
            Self.write(snapshot, to: url, directory: dir)
        }
        saveWorkItem = item
        saveQueue.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    /// Synchronous flush, called when the app terminates.
    func saveNow() {
        saveWorkItem?.cancel()
        let snapshot = StoreFile(selectedProfileID: selectedProfileID, profiles: profiles)
        let url = fileURL
        let dir = directory
        saveQueue.sync {
            Self.write(snapshot, to: url, directory: dir)
        }
    }

    private static func write(_ store: StoreFile, to url: URL, directory: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(store)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Autoclicker: failed to save profiles: \(error)")
        }
    }
}
