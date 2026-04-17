import Foundation

// MARK: - API Response Types

public struct ListNotesResponse: Decodable {
    public let notes:   [NoteSummary]
    public let hasMore: Bool
    public let cursor:  String?
}

public struct NoteSummary: Decodable {
    public let id:        String
    public let title:     String?
    public let owner:     GranolaUser
    public let createdAt: Date
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, owner
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public struct GranolaNote: Decodable {
    public let id:              String
    public let title:           String?
    public let owner:           GranolaUser
    public let attendees:       [GranolaUser]
    public let createdAt:       Date
    public let updatedAt:       Date
    public let summaryMarkdown: String?
    public let calendarEvent:   CalendarEvent?
    public let shareableLink:   String?

    enum CodingKeys: String, CodingKey {
        case id, title, owner, attendees
        case createdAt       = "created_at"
        case updatedAt       = "updated_at"
        case summaryMarkdown = "summary_markdown"
        case calendarEvent   = "calendar_event"
        case shareableLink   = "shareable_link"
    }

    public init(id: String, title: String?, owner: GranolaUser, attendees: [GranolaUser],
                createdAt: Date, updatedAt: Date, summaryMarkdown: String?,
                calendarEvent: CalendarEvent?, shareableLink: String?) {
        self.id = id; self.title = title; self.owner = owner; self.attendees = attendees
        self.createdAt = createdAt; self.updatedAt = updatedAt
        self.summaryMarkdown = summaryMarkdown; self.calendarEvent = calendarEvent
        self.shareableLink = shareableLink
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(String.self,          forKey: .id)
        title           = try c.decodeIfPresent(String.self, forKey: .title)
        owner           = try c.decode(GranolaUser.self,     forKey: .owner)
        attendees       = (try? c.decode([GranolaUser].self, forKey: .attendees)) ?? []
        createdAt       = try c.decode(Date.self,            forKey: .createdAt)
        updatedAt       = try c.decode(Date.self,            forKey: .updatedAt)
        summaryMarkdown = try c.decodeIfPresent(String.self, forKey: .summaryMarkdown)
        calendarEvent   = try c.decodeIfPresent(CalendarEvent.self, forKey: .calendarEvent)
        shareableLink   = try c.decodeIfPresent(String.self, forKey: .shareableLink)
    }
}

public struct GranolaUser: Decodable {
    public let name:  String
    public let email: String

    public func toAttendee() -> Attendee { Attendee(name: name, email: email) }
}

public struct CalendarEvent: Decodable {
    public let eventTitle:          String?
    public let scheduledStartTime:  Date?
    public let scheduledEndTime:    Date?

    enum CodingKeys: String, CodingKey {
        case eventTitle         = "event_title"
        case scheduledStartTime = "scheduled_start_time"
        case scheduledEndTime   = "scheduled_end_time"
    }
}
