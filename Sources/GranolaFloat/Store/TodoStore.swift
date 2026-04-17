import OatsCore
import Foundation
import Combine
import UserNotifications
import AppKit

final class TodoStore: ObservableObject {
    @Published var todos:           [TodoItem] = []
    @Published var showPaywall:     Bool       = false
    @Published var isSyncing:       Bool       = false
    @Published var lastSynced:      Date?      = nil
    @Published var view:            AppView    = .list
    @Published var isCompact:       Bool       = false
    @Published var isExpanded:      Bool       = false
    @Published var syncError:       String?    = nil
    @Published var selectedItemId:  String?    = nil
    @Published var showingNoteId:   String?    = nil

    enum AppView { case list, archive, settings }

    private let api = GranolaAPI()
    private var processedNoteIds: Set<String> = []
    private var saveCancellable: AnyCancellable?

    // MARK: - Init

    init() {
        loadFromDisk()
        // Debounce saves — write at most once per second
        saveCancellable = $todos
            .debounce(for: .seconds(1), scheduler: DispatchQueue.global(qos: .utility))
            .sink { [weak self] todos in
                self?.saveToDisk(todos)
            }
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        if let saved = PersistenceManager.load([TodoItem].self, from: PersistenceManager.File.todos) {
            todos = saved
        }
        if let ids = PersistenceManager.load([String].self, from: PersistenceManager.File.processedNotes) {
            processedNoteIds = Set(ids)
        }
    }

    private func saveToDisk(_ items: [TodoItem]) {
        PersistenceManager.save(items, to: PersistenceManager.File.todos)
        PersistenceManager.save(Array(processedNoteIds), to: PersistenceManager.File.processedNotes)
    }

    // MARK: - Sync

    func syncAll() async {
        await syncPeriod(days: 365)
    }

    func syncPeriod(days: Int) async {
        // Clear processedNoteIds so all notes in the window are re-evaluated
        await MainActor.run { processedNoteIds = [] }
        await sync(daysBack: days)
    }

    func sync() async {
        await sync(daysBack: 14)
    }

    private func sync(daysBack: Int) async {
        await MainActor.run {
            isSyncing  = true
            syncError  = nil
        }

        do {
            let notes = try await api.fetchRecentNotes(daysBack: daysBack)
            let newNotes = notes.filter { processedNoteIds.insert($0.id).inserted }

            // Persist each note's markdown before extracting items
            for note in newNotes {
                if let md = note.summaryMarkdown, !md.isEmpty {
                    PersistenceManager.saveNote(md, noteId: note.id)
                }
            }

            let newItems = await withTaskGroup(of: [TodoItem].self) { group in
                for note in newNotes {
                    group.addTask { await ActionItemExtractor.extractAsync(from: note) }
                }
                var all: [TodoItem] = []
                for await items in group { all.append(contentsOf: items) }
                return all
            }

            await MainActor.run {
                if !newItems.isEmpty { todos.append(contentsOf: newItems) }
                lastSynced = Date()
                isSyncing  = false
                PersistenceManager.save(Array(processedNoteIds),
                                        to: PersistenceManager.File.processedNotes)
                updateBadge()
            }
            if !newItems.isEmpty {
                sendNotification(for: newItems)
            }
        } catch {
            await MainActor.run {
                isSyncing = false
                syncError = friendlyError(error)
            }
        }
    }

    // MARK: - Reset + Sync (used after onboarding to clear demo data)

    func resetAndSync() async {
        await MainActor.run {
            todos            = []
            processedNoteIds = []
            PersistenceManager.save([TodoItem](),  to: PersistenceManager.File.todos)
            PersistenceManager.save([String](),    to: PersistenceManager.File.processedNotes)
        }
        await sync()
    }

    // MARK: - Actions

    func complete(_ item: TodoItem) {
        guard let idx = todos.firstIndex(where: { $0.id == item.id }) else { return }
        todos[idx].completed   = true
        todos[idx].archived    = true
        todos[idx].completedAt = Date()
        updateBadge()
    }

    // MARK: - Keyboard navigation

    /// Ordered list used for arrow-key navigation: todos first, then follow-ups.
    var navItems: [TodoItem] { activeTodos + activeFollowups }

    func selectNext() {
        let items = navItems
        guard !items.isEmpty else { return }
        if let current = selectedItemId, let idx = items.firstIndex(where: { $0.id == current }) {
            selectedItemId = items[min(idx + 1, items.count - 1)].id
        } else {
            selectedItemId = items.first?.id
        }
    }

    func selectPrevious() {
        let items = navItems
        guard !items.isEmpty else { return }
        if let current = selectedItemId, let idx = items.firstIndex(where: { $0.id == current }) {
            selectedItemId = idx > 0 ? items[idx - 1].id : nil
        }
    }

    func completeSelected() {
        guard let id = selectedItemId,
              let item = navItems.first(where: { $0.id == id }) else { return }
        // Advance selection before removing the item
        let items = navItems
        if let idx = items.firstIndex(where: { $0.id == id }) {
            if idx + 1 < items.count {
                selectedItemId = items[idx + 1].id
            } else if idx > 0 {
                selectedItemId = items[idx - 1].id
            } else {
                selectedItemId = nil
            }
        }
        complete(item)
    }

    func openSelectedInGranola() {
        guard let id = selectedItemId,
              let item = navItems.first(where: { $0.id == id }),
              let url = item.granolaURL else { return }
        NSWorkspace.shared.open(url)
    }

    func draftEmailForSelected() {
        guard let id = selectedItemId,
              let item = navItems.first(where: { $0.id == id }),
              item.itemType == .followup else { return }
        let email      = item.recipientEmail ?? ""
        let senderName = UserDefaults(suiteName: "oats.prefs")?.string(forKey: "userName") ?? ""
        let recipient  = item.attendees.first { $0.email == email }
        let firstName  = recipient?.firstName ?? ""
        let greeting   = firstName.isEmpty ? "Hi," : "Hi \(firstName),"
        let subject    = "Following up: \(item.noteTitle)"
        let body       = "\(greeting)\n\nFollowing up from \(item.noteTitle):\n\n\(item.text)\n\nBest,\n\(senderName)"
        if let service = NSSharingService(named: .composeEmail) {
            service.recipients = email.isEmpty ? [] : [email]
            service.subject    = subject
            service.perform(withItems: [body])
        }
    }

    // MARK: - Computed

    var activeTodos:     [TodoItem] { todos.filter { $0.isActive && $0.itemType == .todo }     .sorted { $0.createdAt > $1.createdAt } }
    var activeFollowups: [TodoItem] { todos.filter { $0.isActive && $0.itemType == .followup } .sorted { $0.createdAt > $1.createdAt } }
    var archivedItems:   [TodoItem] { todos.filter { $0.archived }                             .sorted { $0.completedAt ?? $0.createdAt > $1.completedAt ?? $1.createdAt } }

    var hasAPIKey: Bool { !(KeychainManager.load(KeychainManager.Key.granolaAPIKey) ?? "").isEmpty }

    // MARK: - Badge

    func updateBadge() {
        let count = activeTodos.count + activeFollowups.count
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }

    // MARK: - Notifications

    func sendNotification(for items: [TodoItem]) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let todos     = items.filter { $0.itemType == .todo }
        let followups = items.filter { $0.itemType == .followup }

        let title: String
        let body: String

        switch (todos.count, followups.count) {
        case (let t, 0) where t == 1:
            title = "New action item"
            body  = todos[0].text
        case (let t, 0) where t > 1:
            title = "\(t) new action items"
            body  = todos.prefix(2).map(\.text).joined(separator: "\n")
        case (0, let f) where f == 1:
            title = "New follow-up"
            body  = followups[0].text
        case (0, let f) where f > 1:
            title = "\(f) new follow-ups"
            body  = followups.prefix(2).map(\.text).joined(separator: "\n")
        default:
            title = "\(items.count) new items from Granola"
            body  = items.prefix(2).map(\.text).joined(separator: "\n")
        }

        let content         = UNMutableNotificationContent()
        content.title       = title
        content.body        = body
        content.sound       = .default

        let request = UNNotificationRequest(
            identifier: "oat.sync.\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil   // deliver immediately
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Helpers

    private func friendlyError(_ error: Error) -> String {
        switch error {
        case GranolaAPIError.noAPIKey:         return "No Granola API key set. Open Settings to add one."
        case GranolaAPIError.badResponse(401): return "Invalid Granola API key. Check Settings."
        case GranolaAPIError.badResponse(429): return "Granola rate limit hit. Will retry soon."
        case GranolaAPIError.badResponse(let c): return "Granola API error (HTTP \(c))."
        default:                               return "Sync failed: \(error.localizedDescription)"
        }
    }
}
