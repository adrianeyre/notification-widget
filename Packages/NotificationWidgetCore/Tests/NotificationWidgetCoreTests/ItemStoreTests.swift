import Foundation
import Testing
@testable import NotificationWidgetCore

@MainActor
@Suite("Item store")
struct ItemStoreTests {
    @Test("A snapshot replaces everything from that Source and leaves other Sources alone")
    func snapshotReplace() {
        let store = ItemStore(persistence: InMemoryDismissalPersistence(), now: referenceNow)
        store.replaceItems([email("a"), email("b")], from: .gmail)
        store.replaceItems([dm("x")], from: .slack)

        store.replaceItems([email("c")], from: .gmail)

        #expect(Set(store.visibleItems.map(\.id.value)) == ["c", "x"])
    }

    @Test("Dismiss hides an Item by ID")
    func dismissHides() {
        let store = ItemStore(persistence: InMemoryDismissalPersistence(), now: referenceNow)
        store.replaceItems([email("a"), email("b")], from: .gmail)

        store.dismiss(.init(source: .gmail, value: "a"))

        #expect(store.visibleItems.map(\.id.value) == ["b"])
        #expect(store.sections.emails.items.map(\.id.value) == ["b"])
    }

    @Test("Dismissals persist across store reloads")
    func dismissPersists() {
        let defaults = freshDefaults()
        let first = ItemStore(persistence: UserDefaultsDismissalPersistence(defaults: defaults), now: referenceNow)
        first.replaceItems([email("a"), email("b")], from: .gmail)
        first.dismiss(.init(source: .gmail, value: "a"))

        // A new store, as after a restart, rebuilt from the same Source snapshot.
        let second = ItemStore(persistence: UserDefaultsDismissalPersistence(defaults: defaults), now: referenceNow)
        #expect(second.dismissedIDs == [.init(source: .gmail, value: "a")])
        second.replaceItems([email("a"), email("b")], from: .gmail)

        #expect(second.visibleItems.map(\.id.value) == ["b"])
    }

    @Test("Items themselves are never saved, only Dismissed IDs")
    func itemsNotPersisted() {
        let defaults = freshDefaults()
        let first = ItemStore(persistence: UserDefaultsDismissalPersistence(defaults: defaults), now: referenceNow)
        first.replaceItems([email("a")], from: .gmail)

        let second = ItemStore(persistence: UserDefaultsDismissalPersistence(defaults: defaults), now: referenceNow)
        #expect(second.visibleItems.isEmpty)
    }

    @Test("Dismissed IDs the Source no longer returns are pruned")
    func pruning() {
        let persistence = InMemoryDismissalPersistence()
        let store = ItemStore(persistence: persistence, now: referenceNow)
        store.replaceItems([email("a"), email("b")], from: .gmail)
        store.replaceItems([dm("x")], from: .slack)
        store.dismiss(.init(source: .gmail, value: "a"))
        store.dismiss(.init(source: .gmail, value: "b"))
        store.dismiss(.init(source: .slack, value: "x"))

        store.replaceItems([email("b")], from: .gmail)

        let expected: Set<Item.ID> = [.init(source: .gmail, value: "b"), .init(source: .slack, value: "x")]
        #expect(store.dismissedIDs == expected)
        #expect(persistence.loadDismissedIDs() == expected)
    }

    @Test("Clearing a Source keeps its Dismissals")
    func clearKeepsDismissals() {
        let store = ItemStore(persistence: InMemoryDismissalPersistence(), now: referenceNow)
        store.replaceItems([email("a")], from: .gmail)
        store.dismiss(.init(source: .gmail, value: "a"))

        store.clearItems(from: .gmail)

        #expect(store.visibleItems.isEmpty)
        #expect(store.dismissedIDs == [.init(source: .gmail, value: "a")])
    }

    @Test("Expired Items leave once the clock passes their expiry")
    func expiry() {
        let store = ItemStore(persistence: InMemoryDismissalPersistence(), now: referenceNow)
        let ending = event("ending", start: referenceNow.addingTimeInterval(-1800), end: referenceNow.addingTimeInterval(60))
        store.replaceItems([ending], from: .googleCalendar)
        #expect(store.visibleItems.count == 1)

        store.tick(now: referenceNow.addingTimeInterval(60))

        #expect(store.visibleItems.isEmpty)
    }
}

@Suite("Panel sections")
struct PanelSectionsTests {
    @Test("Each section shows at most 5 Items plus a +N more count")
    func limitAndMore() {
        let items = (0..<7).map { email("e\($0)", at: referenceNow.addingTimeInterval(Double(-$0))) }

        let sections = PanelSections(visibleItems: items)

        #expect(sections.emails.items.map(\.id.value) == ["e0", "e1", "e2", "e3", "e4"])
        #expect(sections.emails.moreCount == 2)
    }

    @Test("Five or fewer Items show no +N more")
    func noMore() {
        let sections = PanelSections(visibleItems: (0..<5).map { email("e\($0)") })
        #expect(sections.emails.moreCount == 0)
    }

    @Test("Events split into an all-day header and timed Events in start order, next one first")
    func eventsSplit() {
        let allDay = event("offsite", start: referenceNow, end: referenceNow.addingTimeInterval(86_400), allDay: true)
        let later = event("later", start: referenceNow.addingTimeInterval(7200), end: referenceNow.addingTimeInterval(9000))
        let sooner = event("sooner", start: referenceNow.addingTimeInterval(600), end: referenceNow.addingTimeInterval(1200))

        let sections = PanelSections(visibleItems: [later, allDay, sooner, dm("x")])

        #expect(sections.events.allDay.map(\.id.value) == ["offsite"])
        #expect(sections.events.timed.items.map(\.id.value) == ["sooner", "later"])
        #expect(sections.events.next?.id.value == "sooner")
        #expect(sections.messages.items.map(\.id.value) == ["x"])
    }

    @Test("Sample Items fill every section and overflow the messages section")
    func sampleItems() {
        let sections = PanelSections(visibleItems: SampleItems.items(now: referenceNow, calendar: utcCalendar))
        #expect(!sections.events.allDay.isEmpty)
        #expect(!sections.events.timed.isEmpty)
        #expect(sections.messages.moreCount > 0)
        #expect(!sections.emails.isEmpty)
    }
}
