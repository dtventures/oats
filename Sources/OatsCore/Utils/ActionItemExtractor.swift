import Foundation

public enum ActionItemExtractor {
    private static var currentUser: Attendee {
        let d     = UserDefaults(suiteName: "oats.prefs")!
        let name  = d.string(forKey: "userName")  ?? ""
        let email = d.string(forKey: "userEmail") ?? ""
        return Attendee(name: name, email: email)
    }

    private static let claude = ClaudeAPI()

    // MARK: - Sync (mock/fallback)

    public static func extract(from note: GranolaNote) -> [TodoItem] {
        guard let markdown = note.summaryMarkdown else { return [] }
        let others = participants(for: note)
        let structured = parseStructured(markdown: markdown, note: note, others: others)
        if !structured.isEmpty { return structured }
        return mockAIExtract(markdown: markdown, note: note, others: others)
    }

    // MARK: - Async (uses ClaudeAPI when key is set, regex fallback otherwise)

    public static func extractAsync(from note: GranolaNote) async -> [TodoItem] {
        guard let markdown = note.summaryMarkdown else { return [] }
        let others = participants(for: note)

        let structured = parseStructured(markdown: markdown, note: note, others: others)
        if !structured.isEmpty { return structured }

        if claude.isAvailable {
            let userName  = currentUser.firstName
            let noteTitle = note.title ?? "Untitled Meeting"
            if let aiItems = try? await claude.extractActionItems(
                from: markdown, noteTitle: noteTitle, userName: userName
            ), !aiItems.isEmpty {
                return aiItems.map { makeItem(text: $0, note: note, others: others, source: .ai) }
            }
        }

        return mockAIExtract(markdown: markdown, note: note, others: others)
    }

    // MARK: - Strategy 1: parse "## Action Items" section

    private static func parseStructured(markdown: String, note: GranolaNote, others: [Attendee]) -> [TodoItem] {
        let firstName = currentUser.firstName
        var inSection = false
        var items: [TodoItem] = []

        for line in markdown.components(separatedBy: "\n") {
            if line.lowercased().contains("action item") && line.hasPrefix("##") {
                inSection = true; continue
            }
            if inSection && line.hasPrefix("##") { inSection = false }
            guard inSection else { continue }

            if let groups = capture(line, pattern: #"^[-*]\s+\*\*([^*]+)\*\*[:\s]+(.+)$"#),
               groups[0].lowercased() == firstName.lowercased() {
                let text = groups[1].trimmingCharacters(in: .whitespaces)
                items.append(makeItem(text: text, note: note, others: others))
            }
        }
        return items
    }

    // MARK: - Strategy 2: regex extraction

    private static func mockAIExtract(markdown: String, note: GranolaNote, others: [Attendee]) -> [TodoItem] {
        let name = currentUser.firstName
        let patterns = [
            "\(name)\\s+(?:will|agreed to|committed to)\\s+([^.!?\\n]+[.!?])",
            "\(name)\\s+(?:is|was)\\s+(?:going to|planning to)\\s+([^.!?\\n]+[.!?])",
            "(?:asked|requested|wants)\\s+\(name)\\s+to\\s+([^.!?\\n]+[.!?])",
        ]

        var seen  = Set<String>()
        var items = [TodoItem]()

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let ns = markdown as NSString
            for match in regex.matches(in: markdown, range: NSRange(location: 0, length: ns.length)) {
                guard match.numberOfRanges > 1 else { continue }
                let r = match.range(at: 1)
                guard r.location != NSNotFound else { continue }
                let raw = ns.substring(with: r)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "[.!?]$", with: "", options: .regularExpression)
                guard raw.count >= 10, raw.count <= 200 else { continue }
                let normalized = raw.prefix(1).uppercased() + raw.dropFirst()
                guard seen.insert(normalized.lowercased()).inserted else { continue }
                items.append(makeItem(text: String(normalized), note: note, others: others, source: .ai))
            }
        }
        return items
    }

    // MARK: - Participant helpers

    public static func participants(for note: GranolaNote) -> [Attendee] {
        let myEmail = currentUser.email.lowercased()
        var seen    = Set<String>()
        var result  = [Attendee]()
        for a in ([note.owner] + note.attendees).map({ $0.toAttendee() }) {
            let key = a.email.lowercased()
            guard key != myEmail, seen.insert(key).inserted else { continue }
            result.append(a)
        }
        return result
    }

    // MARK: - Helpers

    private static func makeItem(
        text: String, note: GranolaNote, others: [Attendee], source: ItemSource = .granola
    ) -> TodoItem {
        let type        = ItemClassifier.classify(text)
        let meetingDate = note.calendarEvent?.scheduledStartTime ?? note.createdAt
        return TodoItem(
            id:             "todo_\(note.id)_\(UUID().uuidString)",
            text:           text,
            noteId:         note.id,
            noteTitle:      note.title ?? "Untitled Meeting",
            noteURL:        note.shareableLink,
            attendees:      others,
            source:         source,
            createdAt:      meetingDate,
            itemType:       type,
            recipientEmail: type == .followup
                ? ItemClassifier.recipientEmail(from: text, attendees: others) : nil
        )
    }

    private static func capture(_ string: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = string as NSString
        guard let match = regex.firstMatch(in: string, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1
        else { return nil }
        return (1..<match.numberOfRanges).compactMap {
            let r = match.range(at: $0)
            guard r.location != NSNotFound else { return nil }
            return ns.substring(with: r)
        }
    }
}
