import NotificationWidgetCore
import SwiftUI

/// Shared measurements, so every column, row and inset lines up.
enum PanelMetrics {
    static let columnWidth: CGFloat = 280
    /// The gap between columns, either side of the hairline.
    static let columnGap: CGFloat = 14
    /// The Panel's outer inset: words stay 12pt or more from its edge.
    static let inset: CGFloat = 14
    static let cornerRadius: CGFloat = 22
    /// Inset for row fills (hover, highlight), so they're rounded inside the column.
    static let rowPadding = EdgeInsets(top: 5, leading: 6, bottom: 5, trailing: 6)
    static let rowRadius: CGFloat = 8
    static let avatarSize: CGFloat = 24
    /// The trailing track that holds a time, swapped for Dismiss on hover.
    static let trailingWidth: CGFloat = 30
}

/// The widget-style Panel, laid out horizontally: Events, then DMs and Mentions, then
/// Emails, as side-by-side columns (PNL-5).
struct PanelView: View {
    /// Kept for `PanelController`'s size.
    static let columnWidth = PanelMetrics.columnWidth

    let model: AppModel

    var body: some View {
        let sections = model.store.sections

        VStack(alignment: .leading, spacing: 10) {
            PanelHeader(model: model)
            HStack(alignment: .top, spacing: PanelMetrics.columnGap) {
                EventsColumn(section: sections.events, model: model, emptyText: emptyText(for: .googleCalendar))
                    .frame(width: PanelMetrics.columnWidth, alignment: .topLeading)
                Divider()
                PeopleColumn(title: "DMs and Mentions", symbol: "bubble.left.and.bubble.right.fill", source: .slack,
                             content: sections.messages, model: model, emptyText: emptyText(for: .slack))
                    .frame(width: PanelMetrics.columnWidth, alignment: .topLeading)
                Divider()
                PeopleColumn(title: "Emails", symbol: "envelope.fill", source: .gmail,
                             content: sections.emails, model: model, emptyText: emptyText(for: .gmail))
                    .frame(width: PanelMetrics.columnWidth, alignment: .topLeading)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(PanelMetrics.inset)
        .frame(width: PanelController.size.width, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous))
        .overlay {
            // A hairline keeps the edge crisp on light and dark desktops.
            RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        }
        .onHover { model.panelHoverChanged($0) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func emptyText(for source: Source) -> String {
        if model.usesSampleItems { return "Nothing here" }
        switch source {
        case .slack:
            switch model.slack.state {
            case .disconnected: return "Connect Slack in Settings"
            case .checking: return "Connecting to Slack…"
            case .needsSignIn: return "Slack needs new tokens"
            case .connected: return "No unread DMs or Mentions"
            }
        case .gmail, .googleCalendar:
            switch model.google.state {
            case .notConfigured: return "Set up Google in Settings"
            case .disconnected: return "Connect Google in Settings"
            case .needsSignIn: return "Google needs you to sign in again"
            case .connected: return source == .gmail ? "No unread Emails" : "No more Events today"
            }
        }
    }
}

// MARK: - Header

/// The date, and how many Items are waiting for a look. Dragging it moves the Panel (PNL-4).
private struct PanelHeader: View {
    let model: AppModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(model.store.now, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 8)
            let newCount = model.store.visibleItems.filter { model.alerts.isHighlighted($0.id) }.count
            if newCount > 0 {
                Text("\(newCount) new")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, PanelMetrics.rowPadding.leading)
        .frame(height: 20)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
        .animation(.snappy, value: model.alerts.highlightedIDs)
    }
}

// MARK: - Columns

private struct ColumnHeader: View {
    let title: String
    let symbol: String
    let source: Source
    let count: Int
    let model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if model.health(for: source) == .connected {
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            } else {
                HealthIndicator(source: source, model: model)
            }
        }
        .padding(.horizontal, PanelMetrics.rowPadding.leading)
        .frame(height: 18)
    }
}

/// Shown only when the Source isn't connected, with a one-click fix (PNL-8).
private struct HealthIndicator: View {
    let source: Source
    let model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        switch model.health(for: source) {
        case .connected:
            EmptyView()
        case .outOfDate:
            indicator("Out of date", color: .orange, action: "Reconnect") { model.reconnect(source) }
        case .needsSignIn:
            indicator("Needs sign-in", color: .red, action: "Sign in") {
                if source == .slack {
                    NSApp.activate()
                    openSettings()
                } else {
                    model.reconnect(source)
                }
            }
        case .disconnected:
            indicator("Disconnected", color: .secondary, action: "Connect") {
                NSApp.activate()
                openSettings()
            }
        }
    }

    private func indicator(_ label: String, color: Color, action: String, perform: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(color)
            Text("·").foregroundStyle(.tertiary)
            Button(action, action: perform)
                .buttonStyle(.link)
        }
        .font(.system(size: 11, weight: .medium))
    }
}

/// Events: all-day Events as chips (SRC-6), the next Event as a raised card, then the rest.
private struct EventsColumn: View {
    let section: EventsSection
    let model: AppModel
    let emptyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ColumnHeader(title: "Events", symbol: "calendar", source: .googleCalendar,
                         count: section.allDay.count + section.timed.items.count + section.timed.moreCount, model: model)

            if !section.allDay.isEmpty {
                HStack(spacing: 6) {
                    ForEach(section.allDay) { AllDayChip(item: $0, model: model) }
                }
                .padding(.horizontal, PanelMetrics.rowPadding.leading)
            }

            if section.isEmpty {
                EmptyRow(symbol: "calendar", text: emptyText)
            }

            ForEach(Array(section.timed.items.enumerated()), id: \.element.id) { index, item in
                if index == 0 {
                    NextEventCard(item: item, model: model)
                } else {
                    EventRow(item: item, model: model)
                }
            }
            MoreRow(count: section.timed.moreCount, leading: PanelMetrics.rowPadding.leading + 50)
        }
    }
}

/// DMs and Mentions, or Emails: people first, then what they said.
private struct PeopleColumn: View {
    let title: String
    let symbol: String
    let source: Source
    let content: SectionContent
    let model: AppModel
    let emptyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ColumnHeader(title: title, symbol: symbol, source: source,
                         count: content.items.count + content.moreCount, model: model)
                .padding(.bottom, 4)
            if content.isEmpty {
                EmptyRow(symbol: symbol, text: emptyText)
            }
            ForEach(content.items) { item in
                PersonRow(item: item, model: model)
            }
            MoreRow(count: content.moreCount, leading: PanelMetrics.rowPadding.leading + PanelMetrics.avatarSize + 10)
        }
    }
}

// MARK: - Small parts

private struct AllDayChip: View {
    let item: Item
    let model: AppModel
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Button { model.open(item) } label: {
                Text(item.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            if isHovering {
                DismissButton(item: item, model: model, size: 10)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            model.alerts.isHighlighted(item.id) ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.07),
            in: Capsule()
        )
        .onHover { isHovering = $0 }
        .help("All day")
    }
}

private struct EmptyRow: View {
    let symbol: String
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol)
        }
        .font(.system(size: 12))
        .foregroundStyle(.tertiary)
        .padding(PanelMetrics.rowPadding)
    }
}

private struct MoreRow: View {
    let count: Int
    let leading: CGFloat

    var body: some View {
        if count > 0 {
            Text("+\(count) more")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.leading, leading)
                .padding(.top, 2)
        }
    }
}

struct DismissButton: View {
    let item: Item
    let model: AppModel
    var size: CGFloat = 13

    var body: some View {
        Button {
            model.dismiss(item)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: size))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Dismiss")
        .accessibilityLabel("Dismiss")
    }
}

#Preview {
    PanelView(model: AppModel())
        .frame(width: 960, height: 320)
}
