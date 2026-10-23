/// Admits one holder at a time and resumes waiters in arrival order. Actors use it to keep a
/// critical section atomic across `await` points.
struct SerialGate {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Resumes `continuation` at once when the gate is free; otherwise queues it.
    mutating func enterOrQueue(_ continuation: CheckedContinuation<Void, Never>) {
        if busy {
            waiters.append(continuation)
        } else {
            busy = true
            continuation.resume()
        }
    }

    mutating func leave() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
