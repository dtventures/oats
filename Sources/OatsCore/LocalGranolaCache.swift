import Foundation

/// Reads notes directly from Granola's local cache file.
/// This is faster than the public API — notes appear as soon as Granola
/// generates them locally, with no backend propagation delay.
public enum LocalGranolaCache {

    private static let cacheURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Granola/cache-v6.json")

    // MARK: - Public

    /// Returns all meeting notes from the local cache, newest first.
    /// Notes with neither notes_markdown nor a transcript are excluded.
    public static func readNotes() -> [GranolaNote] {
        guard let data = try? Data(contentsOf: cacheURL),
              let root  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cache = root["cache"]  as? [String: Any],
              let state = cache["state"] as? [String: Any]
        else { return [] }

        let documents  = state["documents"]  as? [String: Any] ?? [:]
        let transcripts = state["transcripts"] as? [String: Any] ?? [:]

        return documents.values.compactMap { raw in
            parseNote(raw, transcripts: transcripts)
        }
    }

    // MARK: - Private

    private static func parseNote(_ raw: Any, transcripts: [String: Any]) -> GranolaNote? {
        guard let doc = raw as? [String: Any],
              let id          = doc["id"]         as? String,
              let createdStr  = doc["created_at"]  as? String,
              let updatedStr  = doc["updated_at"]  as? String,
              (doc["deleted_at"] == nil || doc["deleted_at"] is NSNull),
              (doc["type"] as? String ?? "meeting") == "meeting"
        else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter() // no fractional seconds fallback

        guard let createdAt = iso.date(from: createdStr) ?? isoBasic.date(from: createdStr),
              let updatedAt = iso.date(from: updatedStr) ?? isoBasic.date(from: updatedStr)
        else { return nil }

        // --- Summary content ---
        let notesMarkdown = (doc["notes_markdown"] as? String) ?? ""
        let transcriptText: String = {
            guard let utterances = transcripts[id] as? [[String: Any]] else { return "" }
            return utterances.compactMap { $0["text"] as? String }.joined(separator: " ")
        }()

        let summaryMarkdown: String?
        if !notesMarkdown.isEmpty {
            summaryMarkdown = notesMarkdown
        } else if !transcriptText.isEmpty {
            summaryMarkdown = transcriptText
        } else {
            return nil // nothing to extract from
        }

        // --- Owner ---
        let people  = doc["people"] as? [String: Any]
        let creator = people?["creator"] as? [String: Any]
        let owner   = GranolaUser(
            name:  creator?["name"]  as? String ?? "Unknown",
            email: creator?["email"] as? String ?? ""
        )

        // --- Attendees ---
        let attendeesList = (people?["attendees"] as? [[String: Any]]) ?? []
        let attendees: [GranolaUser] = attendeesList.compactMap { a in
            guard let email = a["email"] as? String else { return nil }
            let details = a["details"] as? [String: Any]
            let person  = details?["person"] as? [String: Any]
            let nameObj = person?["name"] as? [String: Any]
            let name    = nameObj?["fullName"] as? String ?? email
            return GranolaUser(name: name, email: email)
        }

        // --- Calendar event ---
        let calendarEvent: CalendarEvent? = {
            guard let event = doc["google_calendar_event"] as? [String: Any] else { return nil }
            let startDateTime = (event["start"] as? [String: Any])?["dateTime"] as? String
            let endDateTime   = (event["end"]   as? [String: Any])?["dateTime"] as? String
            let start = startDateTime.flatMap { iso.date(from: $0) ?? isoBasic.date(from: $0) }
            let end   = endDateTime.flatMap   { iso.date(from: $0) ?? isoBasic.date(from: $0) }
            return CalendarEvent(
                eventTitle:         event["summary"] as? String,
                scheduledStartTime: start,
                scheduledEndTime:   end
            )
        }()

        return GranolaNote(
            id:              id,
            title:           doc["title"] as? String,
            owner:           owner,
            attendees:       attendees,
            createdAt:       createdAt,
            updatedAt:       updatedAt,
            summaryMarkdown: summaryMarkdown,
            calendarEvent:   calendarEvent,
            shareableLink:   nil
        )
    }
}
