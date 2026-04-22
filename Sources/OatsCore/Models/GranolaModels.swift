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

public struct TranscriptUtterance: Decodable {
    public let text:      String
    public let speaker:   Speaker
    public let startTime: Date?
    public let endTime:   Date?

    /// true = the device microphone picked this up (the local user)
    public var isUser: Bool { speaker.source == "microphone" }

    public struct Speaker: Decodable {
        public let source: String   // "microphone" | "speaker"
    }

    enum CodingKeys: String, CodingKey {
        case text, speaker
        case startTime = "start_time"
        case endTime   = "end_time"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text      = try c.decode(String.self, forKey: .text)
        speaker   = try c.decode(Speaker.self, forKey: .speaker)
        startTime = try? c.decode(Date.self, forKey: .startTime)
        endTime   = try? c.decode(Date.self, forKey: .endTime)
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
    public let transcript:      [TranscriptUtterance]?

    /// Transcript formatted with speaker labels for Claude extraction.
    /// [You] = microphone (the app user), [Other] = remote speaker.
    public var formattedTranscript: String? {
        guard let t = transcript, !t.isEmpty else { return nil }
        return t.map { u in
            let label = u.isUser ? "[You]" : "[Other]"
            return "\(label): \(u.text)"
        }.joined(separator: "\n")
    }

    enum CodingKeys: String, CodingKey {
        case id, title, owner, attendees, transcript
        case createdAt       = "created_at"
        case updatedAt       = "updated_at"
        case summaryMarkdown = "summary_markdown"
        case calendarEvent   = "calendar_event"
        case shareableLink   = "web_url"   // API returns web_url, not shareable_link
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
        transcript      = try? c.decode([TranscriptUtterance].self, forKey: .transcript)
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
