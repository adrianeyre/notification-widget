import AppKit
import NotificationWidgetCore
import SwiftUI

/// The fill behind a row: an accent-soft surface while the Item is highlighted after an
/// Alert (ITM-5), a quiet one on hover. Inset and rounded inside the column.
private struct RowBackground: View {
    let isHighlighted: Bool
    let isHovering: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: PanelMetrics.rowRadius, style: .continuous)
            .fill(isHighlighted ? Color.accentColor.opacity(0.14) : Color.primary.opacity(isHovering ? 0.06 : 0))
    }
}

/// A DM, Mention or Email: avatar, sender and context with the time on line one, then
/// the excerpt or subject. Clicking opens it (INT-1, INT-2); hovering swaps the time for
/// Dismiss (INT-3).
struct PersonRow: View {
    let item: Item
    let model: AppModel
    @State private var isHovering = false

    private var isHighlighted: Bool { model.alerts.isHighlighted(item.id) }

    var body: some View {
        let (sender, context) = SenderLine.parse(item)

        HStack(alignment: .top, spacing: 10) {
            Button { model.open(item) } label: {
                HStack(alignment: .top, spacing: 10) {
                    PersonAvatar(name: sender, imageURL: item.avatarURL, isMention: item.kind == .mention)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(sender)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                                .layoutPriority(1)
                            if let context {
                                Text("· \(context)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Text(item.title)
                            .font(.system(size: 12, weight: isHighlighted ? .medium : .regular))
                            .foregroundStyle(isHighlighted ? .primary : .secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            TrailingTrack(item: item, model: model, isHovering: isHovering) {
                RelativeTime(date: item.date)
            }
        }
        .padding(PanelMetrics.rowPadding)
        .background(RowBackground(isHighlighted: isHighlighted, isHovering: isHovering))
        .onHover { isHovering = $0 }
        .animation(.snappy(duration: 0.2), value: isHighlighted)
    }
}

/// A later Event: a fixed time column, then the title.
struct EventRow: View {
    let item: Item
    let model: AppModel
    @State private var isHovering = false

    private var isHighlighted: Bool { model.alerts.isHighlighted(item.id) }

    var body: some View {
        HStack(spacing: 8) {
            Button { model.open(item) } label: {
                HStack(spacing: 8) {
                    if let start = item.event?.start {
                        Text(start, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .fixedSize()
                            .frame(width: 42, alignment: .leading)
                    }
                    Text(item.title)
                        .font(.system(size: 13, weight: isHighlighted ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if item.event?.joinURL != nil {
                JoinButton(item: item, model: model, prominent: false)
            }
            TrailingTrack(item: item, model: model, isHovering: isHovering) { EmptyView() }
        }
        .padding(PanelMetrics.rowPadding)
        .background(RowBackground(isHighlighted: isHighlighted, isHovering: isHovering))
        .onHover { isHovering = $0 }
    }
}

/// The next Event, raised: title, its time, a live countdown within 15 minutes (ITM-3),
/// and Join for Meet or Zoom (ITM-4).
struct NextEventCard: View {
    let item: Item
    let model: AppModel
    @State private var isHovering = false

    private var isHighlighted: Bool { model.alerts.isHighlighted(item.id) }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button { model.open(item) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    if let event = item.event {
                        HStack(spacing: 8) {
                            Text(timeRange(event))
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(.secondary)
                            Countdown(start: event.start)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if item.event?.joinURL != nil {
                JoinButton(item: item, model: model, prominent: true)
            }
            if isHovering {
                DismissButton(item: item, model: model)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHighlighted ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06))
        }
        .onHover { isHovering = $0 }
    }

    private func timeRange(_ event: EventDetails) -> String {
        let style = Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        return "\(event.start.formatted(style))–\(event.end.formatted(style))"
    }
}

private struct JoinButton: View {
    let item: Item
    let model: AppModel
    let prominent: Bool

    var body: some View {
        Button("Join") { model.join(item) }
            .buttonStyle(.borderedProminent)
            .controlSize(prominent ? .regular : .small)
            .help("Join the video meeting")
    }
}

/// "in 11:59" in orange when the Event starts within 15 minutes; "Now" once it has started.
private struct Countdown: View {
    let start: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let remaining = EventCountdown.remaining(until: start, now: context.date) {
                Text(EventCountdown.text(remaining: remaining))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.orange)
                    .fixedSize()
            } else if start <= context.date {
                Text("Now")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                    .fixedSize()
            }
        }
    }
}

/// A fixed trailing slot: the time at rest, Dismiss on hover, so nothing shifts.
private struct TrailingTrack<Rest: View>: View {
    let item: Item
    let model: AppModel
    let isHovering: Bool
    @ViewBuilder let rest: () -> Rest

    var body: some View {
        ZStack(alignment: .trailing) {
            rest().opacity(isHovering ? 0 : 1)
            DismissButton(item: item, model: model)
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
        }
        .frame(width: PanelMetrics.trailingWidth, alignment: .trailing)
    }
}

/// "now", "12m", "3h": short enough to sit on line one.
private struct RelativeTime: View {
    let date: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(Self.text(since: date, now: context.date))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.tertiary)
                .fixedSize()
        }
    }

    static func text(since date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86_400: return "\(Int(seconds / 3600))h"
        default: return "\(Int(seconds / 86_400))d"
        }
    }
}

/// The person's photo (their Slack profile picture or Gravatar) in a disc, or their
/// initials in their own muted colour while it loads or when there isn't one. A Mention
/// gets an "@" badge.
private struct PersonAvatar: View {
    let name: String
    let imageURL: URL?
    let isMention: Bool

    private static let palette: [Color] = [
        Color(red: 0.42, green: 0.55, blue: 0.80), Color(red: 0.36, green: 0.62, blue: 0.52),
        Color(red: 0.78, green: 0.52, blue: 0.36), Color(red: 0.62, green: 0.48, blue: 0.72),
        Color(red: 0.75, green: 0.44, blue: 0.50), Color(red: 0.46, green: 0.60, blue: 0.66),
        Color(red: 0.66, green: 0.58, blue: 0.36),
    ]

    private var initials: String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "," }).prefix(2)
        let letters = words.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    private var color: Color {
        // A stable hash, so a person keeps their colour across launches.
        let sum = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Self.palette[sum % Self.palette.count]
    }

    private var photo: NSImage? { imageURL.flatMap { AvatarImages.shared.image(for: $0) } }

    var body: some View {
        Circle()
            .fill(color.gradient)
            .frame(width: PanelMetrics.avatarSize, height: PanelMetrics.avatarSize)
            .overlay {
                if let photo {
                    Image(nsImage: photo)
                        .resizable()
                        .scaledToFill()
                        .clipShape(Circle())
                        .accessibilityLabel(name)
                } else {
                    Text(initials)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(x: isMention ? -1 : 0, y: isMention ? -1 : 0)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isMention {
                    // Hangs off the disc's corner, clear of the initials.
                    Image(systemName: "at.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .background(Circle().fill(.background).padding(-1.5))
                        .offset(x: 5, y: 5)
                }
            }
            .padding(.top, 1)
            .task(id: imageURL) {
                if let imageURL { await AvatarImages.shared.load(imageURL) }
            }
    }
}

/// Downloaded avatar photos, kept for the app's lifetime so rows don't flash back to
/// initials when the Panel redraws. A URL with no photo (Gravatar answers 404) or that
/// failed to load is skipped for a while, then tried again.
@MainActor
@Observable
final class AvatarImages {
    static let shared = AvatarImages()

    /// How long to wait before retrying a URL that had no photo or failed.
    private static let retryAfter: TimeInterval = 60 * 60
    /// Enough for every sender on the Panel many times over.
    private static let capacity = 500

    private var images: [URL: NSImage] = [:]
    @ObservationIgnored private var failedAt: [URL: Date] = [:]
    @ObservationIgnored private var inFlight: Set<URL> = []

    func image(for url: URL) -> NSImage? { images[url] }

    #if DEBUG
    /// Puts a photo in place without downloading it, for the debug screenshots.
    func preload(_ image: NSImage, for url: URL) {
        images[url] = image
    }
    #endif

    func load(_ url: URL) async {
        guard images[url] == nil, !inFlight.contains(url) else { return }
        if let failed = failedAt[url], Date().timeIntervalSince(failed) < Self.retryAfter { return }
        inFlight.insert(url)
        defer { inFlight.remove(url) }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let image = NSImage(data: data) else {
                failedAt[url] = Date()
                return
            }
            if images.count >= Self.capacity { images.removeAll() }
            images[url] = image
            failedAt[url] = nil
        } catch {
            // A cancelled load means the row went away; a later one will load it.
            let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
            if !cancelled { failedAt[url] = Date() }
        }
    }
}

/// Splits an Item's detail line into the sender and where it came from:
/// "Priya Shah · DM" → ("Priya Shah", "DM"); an Email's detail is just the sender.
enum SenderLine {
    static func parse(_ item: Item) -> (sender: String, context: String?) {
        let parts = (item.detail ?? "").components(separatedBy: " · ")
        let sender = parts.first.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown"
        let rest = parts.dropFirst().joined(separator: " · ")
        return (sender, rest.isEmpty ? nil : rest)
    }
}
