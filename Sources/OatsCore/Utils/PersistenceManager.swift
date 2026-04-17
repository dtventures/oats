import Foundation

public enum PersistenceManager {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    // MARK: - Directory

    public static var dataDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir  = base.appendingPathComponent("Oats", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Generic save / load

    public static func save<T: Encodable>(_ value: T, to filename: String) {
        let url = dataDirectory.appendingPathComponent(filename)
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            print("PersistenceManager save error (\(filename)): \(error)")
        }
    }

    public static func load<T: Decodable>(_ type: T.Type, from filename: String) -> T? {
        let url = dataDirectory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            print("PersistenceManager load error (\(filename)): \(error)")
            return nil
        }
    }

    // MARK: - Named files

    public enum File {
        public static let todos          = "todos.json"
        public static let processedNotes = "processedNotes.json"
    }

    // MARK: - Note markdown files

    public static var notesDirectory: URL {
        let dir = dataDirectory.appendingPathComponent("notes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Returns the URL for a note's markdown file (may or may not exist yet).
    public static func noteURL(noteId: String) -> URL {
        notesDirectory.appendingPathComponent("\(noteId).md")
    }

    public static func saveNote(_ markdown: String, noteId: String) {
        let url = noteURL(noteId: noteId)
        try? markdown.write(to: url, atomically: true, encoding: .utf8)
    }

    public static func loadNote(noteId: String) -> String? {
        let url = noteURL(noteId: noteId)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    public static func noteExists(noteId: String) -> Bool {
        FileManager.default.fileExists(atPath: noteURL(noteId: noteId).path)
    }
}
