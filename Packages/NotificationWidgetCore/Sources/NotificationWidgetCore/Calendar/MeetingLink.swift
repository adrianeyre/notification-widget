import Foundation

/// Finds the video meeting link for an Event's Join button (ITM-4).
public enum MeetingLink {
    /// A Google Meet link (`hangoutLink` or a video conference entry point), or a Zoom
    /// `zoom.us/j/…` link in the location or description. Meet wins if both exist.
    public static func joinURL(for event: CalendarEvent) -> URL? {
        if let meet = event.hangoutLink.flatMap(URL.init(string:)) {
            return meet
        }
        let videoEntry = event.conferenceData?.entryPoints?
            .first { $0.entryPointType == "video" }
            .flatMap { $0.uri.flatMap(URL.init(string:)) }
        if let videoEntry {
            return videoEntry
        }
        for text in [event.location, event.description].compactMap({ $0 }) {
            if let zoom = zoomURL(in: text) { return zoom }
        }
        return nil
    }

    private static let zoomPattern = try! NSRegularExpression(
        pattern: #"https?://(?:[a-z0-9-]+\.)*zoom\.us/j/\d+(?:\?[^\s"'<>]*)?"#,
        options: [.caseInsensitive]
    )

    /// The first Zoom meeting link in `text` (which may be HTML from the description).
    public static func zoomURL(in text: String) -> URL? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = zoomPattern.firstMatch(in: text, range: range),
              let swiftRange = Range(match.range, in: text)
        else { return nil }
        let link = String(text[swiftRange]).replacingOccurrences(of: "&amp;", with: "&")
        return URL(string: link)
    }

    /// For a Zoom web link, the `zoommtg://` URL that opens the Zoom app directly.
    /// `nil` for anything that isn't a Zoom meeting link.
    public static func zoomAppURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(), host == "zoom.us" || host.hasSuffix(".zoom.us") else { return nil }
        let parts = url.pathComponents
        guard let j = parts.firstIndex(of: "j"), j + 1 < parts.count else { return nil }
        let meetingID = parts[j + 1]
        var components = URLComponents()
        components.scheme = "zoommtg"
        components.host = host
        components.path = "/join"
        var query = [URLQueryItem(name: "action", value: "join"), URLQueryItem(name: "confno", value: meetingID)]
        if let password = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "pwd" })?.value {
            query.append(URLQueryItem(name: "pwd", value: password))
        }
        components.queryItems = query
        return components.url
    }
}
