import Foundation

/// A sleep that can be cancelled instantly from another thread. This is what
/// lets the emergency stop interrupt even long randomized delays immediately
/// instead of waiting for the current interval to elapse.
final class InterruptibleWaiter {
    private let condition = NSCondition()
    private var cancelled = false

    /// Blocks the calling thread for `seconds`, or less if `cancel()` is
    /// called. Returns `false` if the wait was cancelled.
    @discardableResult
    func wait(_ seconds: TimeInterval) -> Bool {
        guard seconds > 0 else {
            condition.lock()
            defer { condition.unlock() }
            return !cancelled
        }
        let deadline = Date().addingTimeInterval(seconds)
        condition.lock()
        defer { condition.unlock() }
        while !cancelled && Date() < deadline {
            condition.wait(until: deadline)
        }
        return !cancelled
    }

    var isCancelled: Bool {
        condition.lock()
        defer { condition.unlock() }
        return cancelled
    }

    /// Wake any in-progress wait immediately and make future waits return
    /// false until `reset()` is called.
    func cancel() {
        condition.lock()
        cancelled = true
        condition.broadcast()
        condition.unlock()
    }

    /// Re-arm the waiter for a new session.
    func reset() {
        condition.lock()
        cancelled = false
        condition.unlock()
    }
}
