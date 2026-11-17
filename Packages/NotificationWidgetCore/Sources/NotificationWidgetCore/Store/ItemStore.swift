import Foundation
import Observation

/// Holds each Source's latest Items, applies Dismissals and expiry, and publishes
/// what the Panel shows.
///
/// Sources hand the store a full snapshot of their current Items every time they
/// refresh. Items are kept in memory only and rebuilt from the Sources (APP-2);
/// only Dismissed IDs are persisted.
@MainActor
@Observable
public final class ItemStore {
    /// The latest snapshot from each Source.
    public private(set) var itemsBySource: [Source: [Item]] = [:]
    /// The IDs of Dismissed Items. Saved on every change.
    public private(set) var dismissedIDs: Set<Item.ID>
    /// The time used to remove expired Items. Advance it with ``tick(now:)``.
    public private(set) var now: Date

    @ObservationIgnored private let persistence: DismissalPersistence
    /// Told about every snapshot, so it can decide when to Alert.
    public let alertEngine: AlertEngine?

    public init(persistence: DismissalPersistence, alertEngine: AlertEngine? = nil, now: Date = Date()) {
        self.persistence = persistence
        self.alertEngine = alertEngine
        self.dismissedIDs = persistence.loadDismissedIDs()
        self.now = now
    }

    /// Replaces everything from `source` with `items`.
    ///
    /// Dismissed IDs for `source` that aren't in the snapshot any more are pruned,
    /// so the saved list doesn't grow forever. Pass `isBackfill: true` when the snapshot
    /// comes from a launch or reconnect Backfill, so its new Items don't Alert (ALR-8).
    public func replaceItems(_ items: [Item], from source: Source, isBackfill: Bool = false) {
        precondition(items.allSatisfy { $0.source == source }, "Every Item must come from \(source)")
        itemsBySource[source] = items

        let current = Set(items.map(\.id))
        let pruned = dismissedIDs.filter { $0.source != source || current.contains($0) }
        if pruned != dismissedIDs {
            dismissedIDs = pruned
            persistence.saveDismissedIDs(pruned)
        }

        alertEngine?.itemsArrived(items.filter { !dismissedIDs.contains($0.id) }, from: source, isBackfill: isBackfill)
    }

    /// Removes everything from `source` without touching its Dismissals, for example
    /// when its Account is disconnected.
    public func clearItems(from source: Source) {
        itemsBySource[source] = nil
    }

    /// Hides an Item from the Panel. Nothing is changed at the Source (INT-3).
    public func dismiss(_ id: Item.ID) {
        alertEngine?.clearHighlight(id)
        guard dismissedIDs.insert(id).inserted else { return }
        persistence.saveDismissedIDs(dismissedIDs)
    }

    /// Advances the store's clock so expired Items (for example ended Events) leave the Panel.
    public func tick(now: Date) {
        self.now = now
    }

    /// Items that aren't Dismissed or expired, from every Source.
    public var visibleItems: [Item] {
        itemsBySource.values.joined().filter { item in
            !dismissedIDs.contains(item.id) && !item.isExpired(at: now)
        }
    }

    /// The visible Items grouped into Panel sections.
    public var sections: PanelSections {
        PanelSections(visibleItems: visibleItems)
    }
}
