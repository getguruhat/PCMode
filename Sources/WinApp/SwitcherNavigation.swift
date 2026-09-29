enum SwitcherNavigation {
    static func index(steps: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((steps % count) + count) % count
    }
}
