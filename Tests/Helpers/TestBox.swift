
actor TestBox<T> {
    private(set) var value: T?

    func set(_ value: T) {
        self.value = value
    }

    func get() -> T? {
        value
    }
}
