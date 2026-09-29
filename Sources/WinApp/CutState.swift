/// Tracks which clipboard revision is eligible for exactly one Move Here.
struct CutState {
    private(set) var generation = 0
    private(set) var pending = false
    private(set) var originalChangeCount = 0
    private var readyChangeCount: Int?

    mutating func cancel() {
        generation += 1
        pending = false
        readyChangeCount = nil
    }
    mutating func begin(changeCount: Int) -> Int {
        cancel()
        originalChangeCount = changeCount
        pending = true
        return generation
    }
    mutating func finish(changeCount: Int, hasFiles: Bool) {
        guard pending else { return }
        pending = false
        readyChangeCount = hasFiles && changeCount != originalChangeCount ? changeCount : nil
    }
    mutating func consume(changeCount: Int) -> Bool {
        let allowed = !pending && readyChangeCount == changeCount
        cancel()
        return allowed
    }
}
