import Foundation

public enum ItemType:   String, Codable, Sendable { case todo, followup }
public enum ItemSource: String, Codable, Sendable { case granola, ai }

public struct Attendee: Identifiable, Equatable, Codable, Sendable {
    public var id: String { email }
    public let name:  String
    public let email: String

    public init(name: String, email: String) {
        self.name = name; self.email = email
    }

    public var firstName: String { name.components(separatedBy: " ").first ?? name }

    public var initials: String {
        let parts = name.components(separatedBy: " ")
        if parts.count == 1 { return String(name.prefix(2)).uppercased() }
        return ((parts.first?.first.map(String.init) ?? "") +
                (parts.last?.first.map(String.init)  ?? "")).uppercased()
    }

    // Palette used by the GUI for avatar colours (SwiftUI extension lives in OatsCore
    // so the hex strings are available to GranolaFloat without duplication).
    public static let avatarPalette: [String] = [
        "#7BA3C4", "#C47B9E", "#7BAF7B", "#C4A87B",
        "#9E7BC4", "#C47B7B", "#7BC4C4", "#A8A87B",
    ]

    public var avatarPaletteIndex: Int {
        abs(name.unicodeScalars.reduce(0) { ($0 << 5) &- $0 &+ Int($1.value) })
            % Attendee.avatarPalette.count
    }
}

public struct TodoItem: Identifiable, Equatable, Codable, Sendable {
    public let id:             String
    public let text:           String
    public let noteId:         String
    public let noteTitle:      String
    public let noteURL:        String?
    public let attendees:      [Attendee]
    public var completed:      Bool      = false
    public var archived:       Bool      = false
    public var completedAt:    Date?
    public let source:         ItemSource
    public let createdAt:      Date
    public let itemType:       ItemType
    public let recipientEmail: String?

    public init(id: String, text: String, noteId: String, noteTitle: String,
                noteURL: String?, attendees: [Attendee], source: ItemSource,
                createdAt: Date, itemType: ItemType, recipientEmail: String?,
                completed: Bool = false, archived: Bool = false, completedAt: Date? = nil) {
        self.id             = id
        self.text           = text
        self.noteId         = noteId
        self.noteTitle      = noteTitle
        self.noteURL        = noteURL
        self.attendees      = attendees
        self.source         = source
        self.createdAt      = createdAt
        self.itemType       = itemType
        self.recipientEmail = recipientEmail
        self.completed      = completed
        self.archived       = archived
        self.completedAt    = completedAt
    }

    public var isActive: Bool { !archived && !completed }

    public var granolaURL: URL? {
        if let link = noteURL,
           let url  = URL(string: link),
           url.scheme == "https" { return url }
        return URL(string: "granola://notes/\(noteId)")
    }
}
