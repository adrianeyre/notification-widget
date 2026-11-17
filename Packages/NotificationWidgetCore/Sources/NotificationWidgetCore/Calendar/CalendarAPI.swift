import Foundation

/// The parts of a Google Calendar `events.list` response the app uses.
public struct CalendarEventList: Decodable, Equatable, Sendable {
    public var items: [CalendarEvent]
    public var defaultReminders: [CalendarReminder]?
    public var nextPageToken: String?

    public init(items: [CalendarEvent], defaultReminders: [CalendarReminder]? = nil, nextPageToken: String? = nil) {
        self.items = items
        self.defaultReminders = defaultReminders
        self.nextPageToken = nextPageToken
    }

    enum CodingKeys: CodingKey { case items, defaultReminders, nextPageToken }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([CalendarEvent].self, forKey: .items) ?? []
        defaultReminders = try container.decodeIfPresent([CalendarReminder].self, forKey: .defaultReminders)
        nextPageToken = try container.decodeIfPresent(String.self, forKey: .nextPageToken)
    }
}

/// One Google Calendar event resource (only the fields the app reads).
public struct CalendarEvent: Decodable, Equatable, Sendable {
    public struct Time: Decodable, Equatable, Sendable {
        /// Set for timed events, as RFC 3339.
        public var dateTime: String?
        /// Set for all-day events, as `yyyy-MM-dd`.
        public var date: String?

        public init(dateTime: String? = nil, date: String? = nil) {
            self.dateTime = dateTime
            self.date = date
        }
    }

    public struct Attendee: Decodable, Equatable, Sendable {
        public var isSelf: Bool?
        public var responseStatus: String?

        public init(isSelf: Bool?, responseStatus: String?) {
            self.isSelf = isSelf
            self.responseStatus = responseStatus
        }

        enum CodingKeys: String, CodingKey {
            case isSelf = "self"
            case responseStatus
        }
    }

    public struct Reminders: Decodable, Equatable, Sendable {
        public var useDefault: Bool
        public var overrides: [CalendarReminder]?

        public init(useDefault: Bool, overrides: [CalendarReminder]? = nil) {
            self.useDefault = useDefault
            self.overrides = overrides
        }
    }

    public struct ConferenceData: Decodable, Equatable, Sendable {
        public struct EntryPoint: Decodable, Equatable, Sendable {
            public var entryPointType: String?
            public var uri: String?

            public init(entryPointType: String?, uri: String?) {
                self.entryPointType = entryPointType
                self.uri = uri
            }
        }

        public var entryPoints: [EntryPoint]?

        public init(entryPoints: [EntryPoint]?) {
            self.entryPoints = entryPoints
        }
    }

    public var id: String
    public var status: String?
    public var summary: String?
    public var htmlLink: String?
    public var start: Time
    public var end: Time
    public var attendees: [Attendee]?
    public var reminders: Reminders?
    public var eventType: String?
    public var hangoutLink: String?
    public var conferenceData: ConferenceData?
    public var location: String?
    public var description: String?

    public init(
        id: String,
        status: String? = "confirmed",
        summary: String?,
        htmlLink: String? = nil,
        start: Time,
        end: Time,
        attendees: [Attendee]? = nil,
        reminders: Reminders? = nil,
        eventType: String? = nil,
        hangoutLink: String? = nil,
        conferenceData: ConferenceData? = nil,
        location: String? = nil,
        description: String? = nil
    ) {
        self.id = id
        self.status = status
        self.summary = summary
        self.htmlLink = htmlLink
        self.start = start
        self.end = end
        self.attendees = attendees
        self.reminders = reminders
        self.eventType = eventType
        self.hangoutLink = hangoutLink
        self.conferenceData = conferenceData
        self.location = location
        self.description = description
    }
}

public struct CalendarReminder: Decodable, Equatable, Sendable {
    public var method: String
    public var minutes: Int

    public init(method: String, minutes: Int) {
        self.method = method
        self.minutes = minutes
    }
}

/// Fetches Events from the user's primary calendar.
public protocol CalendarEventsFetching: Sendable {
    /// Returns every Event overlapping `start..<end`, with recurring Events expanded
    /// into single instances. Follows all pages.
    func fetchEvents(from start: Date, to end: Date) async throws -> CalendarEventList
}

/// The live Google Calendar API.
public struct GoogleCalendarAPI: CalendarEventsFetching {
    private let client: GoogleAuthorizedClient
    private let baseURL = URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!

    public init(client: GoogleAuthorizedClient) {
        self.client = client
    }

    public func fetchEvents(from start: Date, to end: Date) async throws -> CalendarEventList {
        var all = CalendarEventList(items: [])
        var pageToken: String?
        repeat {
            let page: CalendarEventList = try await client.get(url(from: start, to: end, pageToken: pageToken))
            all.items += page.items
            all.defaultReminders = all.defaultReminders ?? page.defaultReminders
            pageToken = page.nextPageToken
        } while pageToken != nil
        return all
    }

    func url(from start: Date, to end: Date, pageToken: String?) -> URL {
        let formatter = ISO8601DateFormatter()
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: formatter.string(from: start)),
            URLQueryItem(name: "timeMax", value: formatter.string(from: end)),
            // Expand recurring Events into single instances.
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "250"),
            URLQueryItem(
                name: "fields",
                value: "nextPageToken,defaultReminders,items(id,status,summary,htmlLink,start,end,attendees(self,responseStatus),reminders,eventType,hangoutLink,conferenceData/entryPoints(entryPointType,uri),location,description)"
            ),
        ] + (pageToken.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? [])
        return components.url!
    }
}
