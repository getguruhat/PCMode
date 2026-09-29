import Foundation

/// All paths share one press latch. Releases and a quiet interval re-arm it;
/// repeats never fire, even when a key is held longer than the debounce interval.
struct PressGate {
    private var held = Set<String>()
    private var lastDown = -Double.infinity
    private var lastRelease = -Double.infinity

    mutating func receive(path: String, down: Bool, repeating: Bool, now: Double) -> Bool {
        if !down {
            held.remove(path)
            lastRelease = now
            return false
        }
        let alreadyHeld = held.contains(path)
        let anotherHeld = !held.isEmpty
        held.insert(path)
        guard !repeating, !alreadyHeld, !anotherHeld,
              now - lastDown > 0.35, now - lastRelease > 0.08 else { return false }
        lastDown = now
        return true
    }
}
