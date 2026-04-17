import Foundation

public enum GranolaAPIError: Error {
    case noAPIKey
    case badResponse(Int)
    case decodingFailed(Error)
}

public struct GranolaAPI {
    private let baseURL = "https://public-api.granola.ai"

    public init() {}

    public var apiKey: String {
        KeychainManager.load(KeychainManager.Key.granolaAPIKey) ?? ""
    }

    // MARK: - Fetch notes

    public func fetchRecentNotes(daysBack: Int = 14) async throws -> [GranolaNote] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date())!
        let summaries = try await listNotes(createdAfter: cutoff)

        return try await withThrowingTaskGroup(of: GranolaNote?.self) { group in
            for summary in summaries {
                group.addTask { try await self.fetchNote(id: summary.id) }
            }
            var notes: [GranolaNote] = []
            for try await note in group {
                if let note { notes.append(note) }
            }
            return notes
        }
    }

    // MARK: - Private

    private func listNotes(createdAfter: Date) async throws -> [NoteSummary] {
        guard !apiKey.isEmpty else { throw GranolaAPIError.noAPIKey }

        var allSummaries: [NoteSummary] = []
        var cursor: String? = nil

        repeat {
            var items: [URLQueryItem] = [
                URLQueryItem(name: "created_after", value: ISO8601DateFormatter().string(from: createdAfter)),
                URLQueryItem(name: "page_size",     value: "30"),
            ]
            if let c = cursor { items.append(URLQueryItem(name: "cursor", value: c)) }

            var components = URLComponents(string: "\(baseURL)/v1/notes")!
            components.queryItems = items

            guard let pageURL = components.url else { throw GranolaAPIError.badResponse(0) }
            let response: ListNotesResponse = try await get(url: pageURL)
            allSummaries.append(contentsOf: response.notes)
            cursor = response.hasMore ? response.cursor : nil
        } while cursor != nil

        return allSummaries
    }

    private func fetchNote(id: String) async throws -> GranolaNote {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        guard let url = URL(string: "\(baseURL)/v1/notes/\(encoded)") else {
            throw GranolaAPIError.badResponse(0)
        }
        return try await get(url: url)
    }

    // MARK: - Validate API key (used during onboarding)

    public static func validate(key: String) async -> Bool {
        guard !key.isEmpty else { return false }
        var components = URLComponents(string: "https://public-api.granola.ai/v1/notes")!
        components.queryItems = [URLQueryItem(name: "page_size", value: "1")]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else { return false }
        return (200..<300).contains(http.statusCode)
    }

    private func get<T: Decodable>(url: URL) async throws -> T {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw GranolaAPIError.badResponse(http.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw GranolaAPIError.decodingFailed(error)
        }
    }
}
