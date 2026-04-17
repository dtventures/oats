import Foundation

public enum ItemClassifier {
    public static func classify(_ text: String) -> ItemType {
        let todoOverrides: [String] = ["schedule", "review", "prepare", "build", "set up",
                                       "research", "publish.*wiki", "book.*room", "book.*meeting"]
        for pattern in todoOverrides {
            if matches(text, pattern: pattern) {
                if !matches(text, pattern: "\\b(send|email|forward|share)\\b.{1,40}\\b(to|with)\\b") {
                    return .todo
                }
            }
        }

        let followupPatterns: [String] = [
            "\\bfollow[\\s-]?up\\b", "\\breach out\\b", "\\breply\\b", "\\brespond\\b",
            "\\bloop in\\b", "\\bintro(duce)?\\b.*\\bto\\b", "\\bforward\\b",
            "\\bshoot over\\b", "\\bemail\\b", "\\bsend\\b.{1,40}\\bto\\b",
            "\\bshare\\b.{1,40}\\bwith\\b",
        ]
        for pattern in followupPatterns {
            if matches(text, pattern: pattern) { return .followup }
        }
        return .todo
    }

    public static func recipientEmail(from text: String, attendees: [Attendee]) -> String? {
        for attendee in attendees {
            let firstName = attendee.firstName
            if matches(text, pattern: "\\b\(NSRegularExpression.escapedPattern(for: firstName))\\b") {
                return attendee.email
            }
        }
        return attendees.first?.email
    }

    public static func suggestedSubject(_ text: String) -> String {
        var s = text
        let prefixes = ["^send\\s+", "^email\\s+",
                        "^follow[\\s-]?up with \\w+\\s*[–—-]?\\s*", "^share\\s+"]
        for p in prefixes {
            s = s.replacingOccurrences(of: p, with: "", options: [.regularExpression, .caseInsensitive])
        }
        s = s.prefix(1).uppercased() + s.dropFirst()
        return s.count > 80 ? String(s.prefix(77)) + "…" : s
    }

    private static func matches(_ text: String, pattern: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]))
            .map { $0.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil } ?? false
    }
}
