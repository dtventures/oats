import Foundation
import CryptoKit

public struct NoteProcessingFingerprint: Codable, Equatable, Sendable {
    public let noteUpdatedAt: Date
    public let summaryHash: String
    public let userName: String
    public let userEmail: String
    public let claudeEnabled: Bool
    public let extractorVersion: Int

    public init(
        noteUpdatedAt: Date,
        summaryHash: String,
        userName: String,
        userEmail: String,
        claudeEnabled: Bool,
        extractorVersion: Int = 2
    ) {
        self.noteUpdatedAt = noteUpdatedAt
        self.summaryHash = summaryHash
        self.userName = userName
        self.userEmail = userEmail
        self.claudeEnabled = claudeEnabled
        self.extractorVersion = extractorVersion
    }

    public init(note: GranolaNote, identity: UserIdentity, claudeEnabled: Bool, extractorVersion: Int = 2) {
        self.init(
            noteUpdatedAt: note.updatedAt,
            summaryHash: Self.hash(note.summaryMarkdown ?? ""),
            userName: identity.trimmedName,
            userEmail: identity.normalizedEmail,
            claudeEnabled: claudeEnabled,
            extractorVersion: extractorVersion
        )
    }

    private static func hash(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
