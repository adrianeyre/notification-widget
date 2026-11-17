import Foundation

/// Where Dismissed Item IDs are saved so they survive restarts (INT-3, APP-2).
public protocol DismissalPersistence: Sendable {
    func loadDismissedIDs() -> Set<Item.ID>
    func saveDismissedIDs(_ ids: Set<Item.ID>)
}

/// Saves Dismissed Item IDs in `UserDefaults`.
public struct UserDefaultsDismissalPersistence: DismissalPersistence, @unchecked Sendable {
    // UserDefaults is thread-safe; it just isn't marked Sendable.
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "dismissedItemIDs") {
        self.defaults = defaults
        self.key = key
    }

    public func loadDismissedIDs() -> Set<Item.ID> {
        guard let data = defaults.data(forKey: key),
              let ids = try? JSONDecoder().decode([Item.ID].self, from: data)
        else { return [] }
        return Set(ids)
    }

    public func saveDismissedIDs(_ ids: Set<Item.ID>) {
        let sorted = ids.sorted { $0.description < $1.description }
        guard let data = try? JSONEncoder().encode(sorted) else { return }
        defaults.set(data, forKey: key)
    }
}

/// Keeps Dismissed Item IDs in memory only. Useful for previews and tests.
public final class InMemoryDismissalPersistence: DismissalPersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var ids: Set<Item.ID>

    public init(_ ids: Set<Item.ID> = []) {
        self.ids = ids
    }

    public func loadDismissedIDs() -> Set<Item.ID> {
        lock.withLock { ids }
    }

    public func saveDismissedIDs(_ ids: Set<Item.ID>) {
        lock.withLock { self.ids = ids }
    }
}
