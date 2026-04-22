import Foundation

public enum ActionItemExtractor {
    private static var currentUser: Attendee {
        let identity = UserProfileStore.current()
        return Attendee(name: identity.trimmedName, email: identity.normalizedEmail)
    }

    private static let claude = ClaudeAPI()
    public static var isAIAvailable: Bool { claude.isAvailable }

    // MARK: - Sync (mock/fallback)

    public static func extract(from note: GranolaNote) -> [TodoItem] {
        guard let markdown = note.summaryMarkdown else { return [] }
        let others = participants(for: note)
        let structured = parseStructured(markdown: markdown, note: note, others: others)
        if !structured.isEmpty { return structured }
        let genericStructured = parseGenericStructured(markdown: markdown, note: note, others: others)
        if !genericStructured.isEmpty { return genericStructured }
        return mockAIExtract(markdown: markdown, note: note, others: others)
    }

    // MARK: - Async (uses ClaudeAPI when key is set, regex fallback otherwise)

    public static func extractAsync(from note: GranolaNote) async -> [TodoItem] {
        let others = participants(for: note)

        // Prefer the raw speaker-attributed transcript for AI extraction (more accurate attribution)
        // Fall back to summary_markdown for structured regex parsing
        if claude.isAvailable, let transcript = note.formattedTranscript {
            let userName      = currentUser.firstName
            let noteTitle     = note.title ?? "Untitled Meeting"
            let attendeeNames = others.map(\.name).filter { !$0.isEmpty }
            if let aiItems = try? await claude.extractActionItems(
                from: transcript, noteTitle: noteTitle, userName: userName,
                attendees: attendeeNames, isTranscript: true
            ), !aiItems.isEmpty {
                return aiItems.map { makeItem(text: $0, note: note, others: others, source: .ai) }
            }
        }

        // Fallback: structured parsing of summary_markdown
        guard let markdown = note.summaryMarkdown else { return [] }

        let structured = parseStructured(markdown: markdown, note: note, others: others)
        if !structured.isEmpty { return structured }

        let genericStructured = parseGenericStructured(markdown: markdown, note: note, others: others)
        if !genericStructured.isEmpty { return genericStructured }

        if claude.isAvailable {
            let userName      = currentUser.firstName
            let noteTitle     = note.title ?? "Untitled Meeting"
            let attendeeNames = others.map(\.name).filter { !$0.isEmpty }
            if let aiItems = try? await claude.extractActionItems(
                from: markdown, noteTitle: noteTitle, userName: userName, attendees: attendeeNames
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

    private static func parseGenericStructured(markdown: String, note: GranolaNote, others: [Attendee]) -> [TodoItem] {
        let interestingHeaders = ["action item", "action items", "next step", "next steps", "follow-up", "follow-ups", "todo", "to-do"]
        let firstName = currentUser.firstName.lowercased()
        var inSection = false
        var items: [TodoItem] = []
        var seen = Set<String>()

        for rawLine in markdown.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let lower = line.lowercased()

            if line.hasPrefix("##") {
                inSection = interestingHeaders.contains { lower.contains($0) }
                continue
            }
            guard inSection else { continue }

            if let groups = capture(line, pattern: #"^[-*]\s+\*\*([^*]+)\*\*[:\s]+(.+)$"#) {
                // Attributed bullet — only keep if it belongs to the current user
                guard groups[0].trimmingCharacters(in: .whitespaces).lowercased() == firstName else { continue }
                let text = cleanedBulletText(groups[1])
                guard !text.isEmpty, seen.insert(text.lowercased()).inserted else { continue }
                items.append(makeItem(text: text, note: note, others: others))
                continue
            }

            if let groups = capture(line, pattern: #"^[-*]\s+(.+)$"#) {
                // Unattributed bullet — only include if it sounds like a personal action item:
                // starts with an imperative verb OR contains first-person language.
                // This filters out third-party plans like "Planning to expand marketing efforts".
                let text = cleanedBulletText(groups[0])
                guard !text.isEmpty, seen.insert(text.lowercased()).inserted else { continue }
                guard looksLikePersonalTask(text) else { continue }
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

    /// Returns true if an unattributed bullet sounds like a personal action item for the current user.
    /// Rejects third-party plans ("Planning to expand…", "Open to strategic options").
    private static func looksLikePersonalTask(_ text: String) -> Bool {
        let lower = text.lowercased()

        // First-person language → definitely theirs
        let firstPerson = ["i ", "i'll", "i've", "i'm", "i need", "i will", "i should",
                           "my ", "we ", "we'll", "we've", "we're", "our "]
        if firstPerson.contains(where: { lower.hasPrefix($0) || lower.contains(" \($0.trimmingCharacters(in: .whitespaces)) ") }) {
            return true
        }

        // Imperative verbs at the start (the most common action-item format)
        let imperatives = ["send", "schedule", "follow", "reply", "respond", "review",
                           "update", "write", "share", "prepare", "reach out", "contact",
                           "book", "set up", "set ", "create", "draft", "confirm",
                           "check", "look into", "research", "complete", "finish",
                           "submit", "upload", "connect", "introduce", "add ", "fix ",
                           "test", "deploy", "push", "pull", "merge", "close"]
        if imperatives.contains(where: { lower.hasPrefix($0) }) {
            return true
        }

        return false
    }

    private static func cleanedBulletText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[.!?]$"#, with: "", options: .regularExpression)
    }
}
