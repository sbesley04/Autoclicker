# Autoclicker

A native macOS autoclicker with a futuristic neon-HUD interface. Global mouse-button
and keyboard triggers (including **Mouse Button 3 / 4**), five activation modes plus a
dedicated **Humanized Rapid** mode, action sequences, coordinate targeting, profiles
with JSON import/export, a menu bar controller, and a hard emergency stop.

Built with **Swift + SwiftUI**, with **AppKit / CoreGraphics (CGEvent)** for the
low-level input core. No Electron, no web views.

> **Intended use:** accessibility assistance, UI testing, repetitive-task relief and
> definitely not hypixel

---

## Requirements

- macOS 13 (Ventura) or newer
- Xcode 16+ to build the project normally
  (a Command-Line-Tools-only fallback is included, see below)

## Building and running

### With Xcode (normal path)

1. Open `Autoclicker.xcodeproj` in Xcode 16 or newer.
2. Select the **Autoclicker** scheme and press **⌘R**.
3. Run the unit tests with **⌘U** (Swift Testing based).

The app is ad-hoc signed ("Sign to Run Locally") and **not sandboxed** — the App
Sandbox forbids the CGEvent tap and event posting this app fundamentally needs.

`swift build` / `swift test` also work from a full Xcode toolchain thanks to the
included `Package.swift`.

### Without Xcode (Command Line Tools only)

```sh
Scripts/build-app.sh          # → .build-clt/Autoclicker.app
open .build-clt/Autoclicker.app
Scripts/run-tests.sh          # builds and runs the Swift Testing suite
```

`Scripts/swiftflags.sh` (created on this machine) holds workaround compiler flags for
a CLT packaging bug (duplicate `SwiftBridging` modulemap). On a healthy toolchain the
scripts fall back to plain flags automatically.

## macOS permissions

Open the app's **Permissions** section — it deep-links to the right panes, explains
each permission, and re-checks status automatically whenever the app becomes active.

| Permission | Where | Why |
|---|---|---|
| **Accessibility** (required) | System Settings → Privacy & Security → Accessibility | Creates the global event tap that detects triggers, optionally suppresses them, and posts the synthesized clicks. Without it the app cannot click at all. |
| **Input Monitoring** (recommended) | System Settings → Privacy & Security → Input Monitoring | Needed on some systems for global keyboard capture: keyboard triggers, the emergency-stop shortcut while other apps are frontmost, and key names in Input Detection mode. |

Notes:

- If the app doesn't appear in a list, add it manually with the **+** button.
- After toggling a permission, macOS sometimes requires relaunching the app.
- Rebuilding an ad-hoc-signed app produces a new binary identity; you may need to
  remove and re-add it in the permission lists after rebuilds.
- **Fail-safe:** with permissions missing, clicking is disabled outright; if a
  permission is revoked mid-session the session stops and the trigger disarms.

## Mouse Button 3 / 4 detection

macOS reports extra mouse buttons as `otherMouseDown/Up` events carrying a raw
**button number**: `0` left, `1` right, `2` middle, `3`, `4`, … for the rest. Vendor
software often calls button number 3 "Mouse Button 4", so numbering can be confusing —
and drivers (Logi Options+, Razer Synapse, SteerMouse…) may remap side buttons to
keyboard shortcuts or gestures before macOS ever sees a mouse button.

Use **Trigger → Input Detection Mode**: press *Detect*, then press the physical
button. The app shows the exact event type and button number macOS reports, and can
assign it as the trigger in one click. The **Input Diagnostics** panel shows a live
feed of recent events (synthetic ones tagged `SYN`) to troubleshoot mappings.

Original trigger events can **pass through**, be **suppressed**, or act as
**trigger only** — suppression requires an active (Accessibility-backed) event tap
and is reported in the UI when unavailable.

## Feature overview

- **Modes:** Hold, Toggle, Burst (exact click count), One-Shot, Repeat Sequence,
  Humanized Rapid.
- **Click types:** left / right / middle / double / mouse-down only / mouse-up only /
  click-and-hold (configurable duration).
- **Speed:** clicks-per-second (decimals allowed), fixed interval, randomized range,
  humanized; engine floor of 1 ms (1000 cps) with confirmation above 30 cps.
- **Humanized timing:** truncated-normal intervals around a target average with
  drift correction, Subtle/Natural/Burst/Custom profiles, hesitations, rapid bursts,
  cursor jitter, seeded reproducibility, live telemetry graph and a preview simulator
  that never posts real events. All optional, all off by default.
- **Targeting:** current cursor, fixed point, cycle, random; capture tool; multi-
  monitor aware (global top-left coordinate space); return-to-origin.
- **Sequences:** visual editor with reorderable steps, per-step parameters, nested
  repeat groups, validation before running.
- **Profiles:** create/duplicate/rename/delete, JSON import/export (validated and
  sanitized), six default presets, autosave to Application Support.
- **Menu bar:** start/stop, profile switching, live CPS/click counts, emergency stop,
  open window, quit; app can keep running with the window closed.
- **Safety:** global emergency stop (default **⌘⇧⎋**, recordable), max clicks, max
  runtime, startup countdown, stop-on-app-switch, high-rate confirmation, automatic
  stop on quit/sleep/permission-loss/display changes.

## Architecture

```
Autoclicker/
├── App/
│   ├── AutoclickerApp.swift      @main scene, menu bar extra, app delegate
│   └── AppState.swift            central coordinator (the only glue layer)
├── Core/                          pure logic — no AppKit, fully unit-tested
│   ├── Models/                    Profile, configs, TriggerInput, SequenceAction
│   ├── Timing/                    RandomSource (SplitMix64), interval generators,
│   │                              HumanizedIntervalGenerator, TimingPreview
│   ├── Engine/                    ClickEngine (worker thread), SequenceRunner,
│   │                              TriggerStateMachine, InterruptibleWaiter,
│   │                              TargetResolver, EventPosting protocol + mock
│   └── Persistence/               ProfileStore, SettingsStore (JSON, debounced)
├── System/                        macOS integration
│   ├── PermissionManager.swift    AX + IOHIDCheckAccess, deep links, auto-refresh
│   ├── GlobalInputMonitor.swift   CGEventTap on its own thread, suppression,
│   │                              capture modes, synthetic-event filtering
│   ├── CGEventPoster.swift        tagged CGEvent posting, coordinate conversion
│   ├── SoundManager.swift         optional system-sound effects
│   └── SystemEventObserver.swift  sleep / wake / display / app-switch
└── UI/                            SwiftUI HUD (theme system, components, screens)
```

Key design points:

- **`EventPosting` protocol** decouples engines from CGEvent so the whole engine
  stack runs under tests with a `RecordingEventPoster`.
- **`TriggerStateMachine`** is a pure value type: every activation mode's behavior
  (including emergency-stop priority) is table-tested without threads.
- **`ClickEngine`** runs sessions on a dedicated thread; `InterruptibleWaiter`
  (NSCondition) makes every delay — including multi-second randomized ones —
  cancellable within microseconds. One session at a time, enforced under a lock.
- **Self-trigger prevention:** every synthesized CGEvent carries a magic value in
  `eventSourceUserData`; the event tap drops those before trigger matching.
- **Tap resilience:** the tap re-enables itself on `tapDisabledByTimeout`, runs at
  `userInteractive` QoS on a dedicated run loop, and is torn down (never duplicated)
  on stop/restart.
- **UI flood control:** engine callbacks land in a lock-protected buffer drained by
  a 0.15 s main-thread timer, so 1000 cps clicking cannot saturate the main thread.

## Testing

~50 Swift Testing tests cover: interval math, humanized bounds/average/seeding/
profiles, preview purity, trigger state machine for every mode, emergency-stop
priority and reason precedence, burst count exactness (fixed + humanized), limit
enforcement (clicks/runtime), immediate stop during long randomized delays,
click-and-hold release on stop, sequence ordering/validation/codability, profile
persistence, import validation/sanitization, and corrupt-store recovery.

Run with **⌘U** in Xcode, `swift test`, or `Scripts/run-tests.sh` (CLT-only).

## Known limitations

- **Vendor mouse drivers** may remap side buttons to keyboard macros before macOS
  sees them; the Input Detection panel shows what actually arrives. Buttons remapped
  by such software must be set to a plain button function to be usable as triggers.
- **Suppression** needs an active event tap (Accessibility). Secure input fields
  (password prompts) block keyboard capture system-wide by design.
- **Sandboxed distribution is impossible** — event taps and event posting are
  incompatible with the App Sandbox, so this app can't ship in the Mac App Store.
- Posting clicks into apps running with higher privileges than the poster is
  restricted by macOS.
- Timer granularity: intervals are honored on a high-QoS thread, but macOS is not a
  real-time OS; at extreme rates (>500 cps) actual throughput depends on system load.
- The rebuilt binary identity caveat for ad-hoc signing (see Permissions above).

## Troubleshooting

1. **Nothing clicks** → check the Permissions screen; Accessibility must be granted
   to *this* build of the app. Try removing and re-adding it, then relaunch.
2. **Trigger not detected** → open Trigger → Input Diagnostics and press the button.
   If no event appears, a vendor driver is intercepting it.
3. **Keyboard trigger works only while the app is frontmost** → grant Input
   Monitoring.
4. **Runaway clicking** → press **⌘⇧⎋** (or your custom emergency stop); it
   interrupts any wait instantly and disarms the trigger.
5. **Suppression not working** → the tap fell back to listen-only; re-grant
   Accessibility and relaunch.
6. **Stale permission after rebuild** → System Settings lists the old binary;
   remove the entry, re-add the new app.
