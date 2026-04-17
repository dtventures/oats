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
        from markdown: String,
        noteTitle: String,
        userName: String
    ) async throws -> [String] {
        guard !apiKey.isEmpty else { throw ClaudeAPIError.noAPIKey }

        let prompt = """
You are extracting personal action items from a meeting transcript summary.

Meeting: \(noteTitle)
Person to extract for: \(userName)

Meeting notes:
\(markdown)

Extract ONLY the tasks that "\(userName)" personally needs to act on. Include:
- Direct to-dos (things to build, write, complete, or deliver)
- Follow-ups (emails to send, people to contact, meetings to schedule, replies needed)

Rules:
- Skip tasks assigned to other people
- Be concise — one clear action per item, no filler words
- Use imperative phrasing: "Send proposal to Sarah", not "Alex will send..."
- Include deadlines if mentioned (e.g. "Send report to Jake by Friday")

Return a JSON array of strings. If no items found for \(userName), return [].
Return only valid JSON. No explanation or markdown.

Example: ["Send updated roadmap to Jordan", "Schedule 30-min sync with Mike", "Follow up with Rachel on the contract"]
"""

        let body: [String: Any] = [
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
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClaudeAPIError.badResponse(http.statusCode)
        }

        guard let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = (json["content"] as? [[String: Any]])?.first,
              let text    = content["text"] as? String
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
