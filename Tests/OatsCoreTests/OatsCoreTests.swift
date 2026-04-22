import Foundation
import Testing
@testable import OatsCore

struct OatsCoreTests {
    @Test func structuredExtractionUsesCurrentIdentity() {
        let defaults = UserDefaults(suiteName: UserProfileStore.suiteName)!
        defaults.set("Dana", forKey: "userName")
        defaults.set("dana@example.com", forKey: "userEmail")

        let note = GranolaNote(
            id: "note-1",
            title: "Weekly Sync",
            owner: GranolaUser(name: "Dana Founder", email: "dana@example.com"),
            attendees: [GranolaUser(name: "Alex", email: "alex@example.com")],
            createdAt: .now,
            updatedAt: .now,
            summaryMarkdown: """
            ## Action Items
            - **Dana**: Send the proposal to Alex
            - **Alex**: Review pricing
            """,
            calendarEvent: nil,
            shareableLink: nil
        )

        let items = ActionItemExtractor.extract(from: note)

        #expect(items.count == 1)
        #expect(items.first?.text == "Send the proposal to Alex")
    }

    @Test func fingerprintChangesWhenExtractionInputsChange() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let note = GranolaNote(
            id: "note-2",
            title: "Roadmap",
            owner: GranolaUser(name: "Dana", email: "dana@example.com"),
            attendees: [],
            createdAt: now,
            updatedAt: now,
            summaryMarkdown: "Ship the beta next week",
            calendarEvent: nil,
            shareableLink: nil
        )

        let base = NoteProcessingFingerprint(
            note: note,
            identity: UserIdentity(name: "Dana", email: "dana@example.com"),
            claudeEnabled: false
        )
        let aiEnabled = NoteProcessingFingerprint(
            note: note,
            identity: UserIdentity(name: "Dana", email: "dana@example.com"),
            claudeEnabled: true
        )
        let differentUser = NoteProcessingFingerprint(
            note: note,
            identity: UserIdentity(name: "Morgan", email: "morgan@example.com"),
            claudeEnabled: false
        )
        let updatedNote = GranolaNote(
            id: "note-2",
            title: "Roadmap",
            owner: GranolaUser(name: "Dana", email: "dana@example.com"),
            attendees: [],
            createdAt: now,
            updatedAt: now.addingTimeInterval(60),
            summaryMarkdown: "Ship the beta after legal review",
            calendarEvent: nil,
            shareableLink: nil
        )
        let updatedFingerprint = NoteProcessingFingerprint(
            note: updatedNote,
            identity: UserIdentity(name: "Dana", email: "dana@example.com"),
            claudeEnabled: false
        )

        #expect(base != aiEnabled)
        #expect(base != differentUser)
        #expect(base != updatedFingerprint)
    }

    @Test func extractionReturnsEmptyWhenNoActionItemsArePresent() {
        let defaults = UserDefaults(suiteName: UserProfileStore.suiteName)!
        defaults.set("Dana", forKey: "userName")
        defaults.set("dana@example.com", forKey: "userEmail")

        let note = GranolaNote(
            id: "note-3",
            title: "Hiring Debrief",
            owner: GranolaUser(name: "Dana", email: "dana@example.com"),
            attendees: [GranolaUser(name: "Alex", email: "alex@example.com")],
            createdAt: .now,
            updatedAt: .now,
            summaryMarkdown: """
            ## Summary
            We discussed the candidate's strengths and open questions.

            ## Decisions
            Strong fit for product thinking and execution.
            """,
            calendarEvent: nil,
            shareableLink: nil
        )

        let items = ActionItemExtractor.extract(from: note)

        #expect(items.isEmpty)
    }
}
