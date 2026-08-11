import Foundation
#if canImport(Testing)
import Testing
#endif
#if !TEST_RUNNER
@testable import Autoclicker
#endif

// When built by Scripts/run-tests.sh (-D TEST_RUNNER), the app sources and
// the tests are compiled into one module and this file provides the entry
// point. Under Xcode / SwiftPM the test target imports the app module
// normally and the runner below is compiled out.
#if TEST_RUNNER
@main
struct TestRunnerMain {
    static func main() async {
        await __swiftPMEntryPoint() as Never
    }
}
#endif

/// Waits for a ClickEngine session to finish and returns its outcome.
func runEngineSession(
    _ engine: ClickEngine,
    _ session: ClickSession,
    onClick: @escaping (Int, TimeInterval) -> Void = { _, _ in },
    afterStart: @escaping () -> Void = {},
    timeout: TimeInterval = 15
) -> (reason: StopReason, clicks: Int)? {
    let done = DispatchSemaphore(value: 0)
    let resultLock = NSLock()
    var result: (StopReason, Int)?
    let callbacks = ClickEngineCallbacks(
        onStart: afterStart,
        onClick: onClick,
        onStop: { reason, clicks in
            resultLock.lock()
            result = (reason, clicks)
            resultLock.unlock()
            done.signal()
        })
    guard engine.start(session, callbacks: callbacks) else { return nil }
    guard done.wait(timeout: .now() + timeout) == .success else { return nil }
    resultLock.lock()
    defer { resultLock.unlock() }
    return result
}
