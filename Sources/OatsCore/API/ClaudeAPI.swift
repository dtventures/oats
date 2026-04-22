import Foundation

public enum ClaudeAPIError: Error {
    case noAPIKey
    case badResponse(Int)
    case noContent
}

public struct ClaudeAPI {
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let model   = "claude-haiku-4-5-20251001"

    public init() {}

    public var apiKey: String {
        KeychainManager.load(KeychainManager.Key.claudeAPIKey) ?? ""
    }

    public var isAvailable: Bool { !apiKey.isEmpty }

    // MARK: - Extract action items for a specific person

    public func extractActionItems(
        from content: String,
        noteTitle: String,
        userName: String,
        attendees: [String] = [],
        isTranscript: Bool = false
    ) async throws -> [String] {
        guard !apiKey.isEmpty else { throw ClaudeAPIError.noAPIKey }

        let attendeeContext = attendees.isEmpty
            ? ""
            : "Other attendees: \(attendees.joined(separator: ", "))\n"

        let othersClause = attendees.isEmpty
            ? "anyone else"
            : attendees.joined(separator: ", ")

        let contentLabel = isTranscript ? "Meeting transcript" : "Meeting notes"
        let speakerNote = isTranscript ? """

Speaker key: [You] = \(userName), [Other] = the other participant(s).
""" : ""

        let prompt = """
Extract action items that \(userName) personally needs to act on from this meeting.

Meeting: \(noteTitle)
\(attendeeContext)\(speakerNote)
\(contentLabel):
\(content)

Include ONLY items where \(userName) is the one who must act:
1. Things \(userName) said they would do, committed to, or volunteered for ([You] lines in the transcript)
2. Things other participants explicitly asked or requested \(userName) to do ([Other] lines directed at \(userName))
3. Follow-ups \(userName) needs to send (emails, intros, replies, scheduling)

Exclude:
- Tasks for \(othersClause) — even if \(userName) is mentioned in passing
- General discussion points with no clear owner
- Vague items like "look into it" with no concrete action

Use imperative phrasing ("Send the proposal to Alex") not third-person ("\(userName) will send...").
Include deadline if mentioned. Be concise — no filler words.

Return a JSON array of strings. If \(userName) has no action items, return [].
Return only valid JSON, no explanation.
"""

        let requestBody: [String: Any] = [
            "model":      model,
            "max_tokens": 1024,
            "messages":   [["role": "user", "content": prompt]],
        ]

        guard let endpointURL = URL(string: baseURL) else { throw ClaudeAPIError.noContent }
        var request = URLRequest(url: endpointURL, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue(apiKey,             forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01",       forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClaudeAPIError.badResponse(http.statusCode)
        }

        guard let json        = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let firstBlock = (json["content"] as? [[String: Any]])?.first,
              let text       = firstBlock["text"] as? String
        else { throw ClaudeAPIError.noContent }

        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let arrayData = cleaned.data(using: .utf8),
              let items     = try? JSONDecoder().decode([String].self, from: arrayData)
        else {
            if let start = text.firstIndex(of: "["),
               let end   = text.lastIndex(of: "]") {
                let slice = String(text[start...end])
                if let d     = slice.data(using: .utf8),
                   let items = try? JSONDecoder().decode([String].self, from: d) {
                    return items
                }
            }
            return []
        }
        return items
    }
}
