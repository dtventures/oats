import Foundation

public struct UserIdentity: Equatable, Sendable {
    public let name: String
    public let email: String

    public init(name: String, email: String) {
        self.name = name
        self.email = email
    }

    public var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var normalizedEmail: String {
        trimmedEmail.lowercased()
    }

    public var firstName: String {
        trimmedName.split(separator: " ").first.map(String.init) ?? ""
    }

    public var isComplete: Bool {
        !trimmedName.isEmpty && !trimmedEmail.isEmpty
    }
}

public enum UserProfileStore {
    public static let suiteName = "oats.prefs"

    public static func current() -> UserIdentity {
        let defaults = UserDefaults(suiteName: suiteName)
        return UserIdentity(
            name: defaults?.string(forKey: "userName") ?? "",
            email: defaults?.string(forKey: "userEmail") ?? ""
        )
    }

    public static var missingIdentityMessage: String {
        "Add your name and email in Settings so Oats can identify your action items."
    }
}
