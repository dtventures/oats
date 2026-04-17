import Foundation
import ArgumentParser
import OatsCore
import Darwin

@main
struct OatsCLI: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "oats",
        abstract:    "Manage your Granola action items from the terminal.",
        subcommands: [InteractiveCommand.self, ListCommand.self, SyncCommand.self, DoneCommand.self, StatusCommand.self],
        defaultSubcommand: InteractiveCommand.self
    )
}

// MARK: - Interactive TUI (default)

struct InteractiveCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "ui",
        abstract:    "Interactive list with keyboard navigation (default)."
    )

    func run() async throws {
        try await TUI().run()
    }
}

// MARK: - TUI

private final class TUI {

    private var todos:         [TodoItem] = []
    private var selectedIndex: Int        = 0
    private var statusMessage: String     = ""
    private var oldTermios                = termios()

    // Ordered navigation list: todos first, then follow-ups
    private var navItems: [TodoItem] {
        let t = todos.filter { $0.isActive && $0.itemType == .todo     }.sorted { $0.createdAt > $1.createdAt }
        let f = todos.filter { $0.isActive && $0.itemType == .followup }.sorted { $0.createdAt > $1.createdAt }
        return t + f
    }

    func run() async throws {
        enableRawMode()
        print("\u{1B}[?25l", terminator: ""); fflush(stdout)   // hide cursor
        defer {
            print("\u{1B}[?25h", terminator: ""); fflush(stdout)  // show cursor
            restoreTerminal()
            print("\u{1B}[2J\u{1B}[H", terminator: ""); fflush(stdout)  // clear on exit
        }

        todos = loadTodos()
        clampSelection()
        render()

        while true {
            let key = readKey()
            switch key {

            case .up:
                if selectedIndex > 0 { selectedIndex -= 1; statusMessage = "" }

            case .down:
                let count = navItems.count
                if count > 0, selectedIndex < count - 1 { selectedIndex += 1; statusMessage = "" }

            case .enter, .space:
                completeSelected()

            case .char("g"), .char("G"):
                openSelected()
                continue   // openSelected renders itself

            case .char("e"), .char("E"):
                emailSelected()
                continue   // emailSelected renders itself

            case .char("n"), .char("N"):
                openNotesInPager()
                continue   // openNotesInPager re-renders on return

            case .char("c"), .char("C"):
                startWithClaude()
                return   // reached only if exec failed

            case .char("s"), .char("S"):
                await syncData()

            case .char("q"), .char("Q"), .escape, .ctrlC:
                return

            default:
                continue
            }

            render()
        }
    }

    // MARK: - Actions

    private func completeSelected() {
        let items = navItems
        guard !items.isEmpty, selectedIndex < items.count else { return }
        let item = items[selectedIndex]

        if let idx = todos.firstIndex(where: { $0.id == item.id }) {
            todos[idx].completed   = true
            todos[idx].archived    = true
            todos[idx].completedAt = Date()
        }
        PersistenceManager.save(todos, to: PersistenceManager.File.todos)
        clampSelection()
        statusMessage = "✓  \(item.text)"
    }

    private func openSelected() {
        guard selectedIndex < navItems.count,
              let url = navItems[selectedIndex].granolaURL else {
            statusMessage = "✗  No Granola link for this item"
            render(); return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments     = [url.absoluteString]
        try? p.run()
        statusMessage = "↗  Opened in Granola"
        render()
    }

    private func openNotesInPager() {
        let items = navItems
        guard selectedIndex < items.count else { return }
        let item = items[selectedIndex]
        guard PersistenceManager.noteExists(noteId: item.noteId) else {
            statusMessage = "✗  No notes saved for this meeting (run s to sync)"
            render(); return
        }

        // Hand off to less — restore terminal first, then re-enter raw mode after
        print("\u{1B}[?25h", terminator: ""); fflush(stdout)
        restoreTerminal()
        print("\u{1B}[2J\u{1B}[H", terminator: ""); fflush(stdout)

        let path = PersistenceManager.noteURL(noteId: item.noteId).path
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/less")
        p.arguments = ["--", path]
        try? p.run()
        p.waitUntilExit()

        // Re-enter raw mode and redraw
        enableRawMode()
        print("\u{1B}[?25l", terminator: ""); fflush(stdout)
        statusMessage = "↩  Back from notes"
        render()
    }

    private func emailSelected() {
        let items = navItems
        guard selectedIndex < items.count else { return }
        let item = items[selectedIndex]
        guard item.itemType == .followup else {
            statusMessage = "✗  E email is only available for follow-ups"
            render(); return
        }

        let email      = item.recipientEmail ?? ""
        let senderName = UserDefaults(suiteName: "oats.prefs")?.string(forKey: "userName") ?? ""
        let recipient  = item.attendees.first { $0.email == email }
        let firstName  = recipient?.firstName ?? ""
        let greeting   = firstName.isEmpty ? "Hi," : "Hi \(firstName),"
        let bodyText   = "\(greeting)\n\nFollowing up from \(item.noteTitle):\n\n\(item.text)\n\nBest,\n\(senderName)"

        guard let subject = "Following up: \(item.noteTitle)"
                                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let body    = bodyText
                                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url     = URL(string: "mailto:\(email)?subject=\(subject)&body=\(body)")
        else {
            statusMessage = "✗  Could not build email URL"
            render(); return
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments     = [url.absoluteString]
        try? p.run()
        statusMessage = "✉  Email draft opened"
        render()
    }

    private func startWithClaude() {
        let items = navItems
        guard selectedIndex < items.count else {
            statusMessage = "✗  Select an item first"
            render(); return
        }
        let item = items[selectedIndex]

        // Attach meeting notes if available
        let notesSection: String
        if let md = PersistenceManager.loadNote(noteId: item.noteId), !md.isEmpty {
            notesSection = "\n\n## Meeting Notes\n\n\(md)"
        } else {
            notesSection = ""
        }

        // Build a focused prompt Claude Code will receive as its first message
        let prompt: String
        if item.itemType == .followup {
            let email     = item.recipientEmail ?? ""
            let recipient = item.attendees.first { $0.email == email }
            let toName    = recipient?.name ?? (email.isEmpty ? "the recipient" : email)
            prompt = """
            I have a follow-up action item from my meeting "\(item.noteTitle)":

            \(item.text)

            Recipient: \(toName)\(email.isEmpty ? "" : " <\(email)>")\(notesSection)

            Please help me draft a concise, professional follow-up email to send to them.
            """
        } else {
            prompt = """
            I have a task from my meeting "\(item.noteTitle)":

            \(item.text)\(notesSection)

            I'm in the project directory. Please help me get started on this.
            """
        }

        // Restore terminal before handing off to claude
        print("\u{1B}[?25h", terminator: ""); fflush(stdout)
        restoreTerminal()
        print("\u{1B}[2J\u{1B}[H", terminator: ""); fflush(stdout)

        // exec into claude — replaces this process entirely so the terminal
        // is handed directly to Claude Code with no wrapper process in between
        let argStrings = ["claude", prompt]
        var cArgs = argStrings.map { strdup($0) as UnsafeMutablePointer<CChar>? }
        cArgs.append(nil)
        execvp("claude", &cArgs)

        // execvp only returns on failure (claude not found / not in PATH)
        print("Error: 'claude' command not found.")
        print("Install Claude Code: https://claude.ai/code")
    }

    private func syncData() async {
        statusMessage = "↻  Syncing with Granola…"
        render()

        guard !(KeychainManager.load(KeychainManager.Key.granolaAPIKey) ?? "").isEmpty else {
            statusMessage = "✗  No API key — open Oats app → Settings"
            return
        }

        var all          = todos
        var processedIds = loadProcessedIds()
        let api          = GranolaAPI()

        do {
            let notes    = try await api.fetchRecentNotes(daysBack: 14)
            let newNotes = notes.filter { processedIds.insert($0.id).inserted }
            var newItems: [TodoItem] = []
            for note in newNotes {
                if let md = note.summaryMarkdown, !md.isEmpty {
                    PersistenceManager.saveNote(md, noteId: note.id)
                }
                newItems.append(contentsOf: await ActionItemExtractor.extractAsync(from: note))
            }
            all.append(contentsOf: newItems)
            todos = all
            PersistenceManager.save(todos,               to: PersistenceManager.File.todos)
            PersistenceManager.save(Array(processedIds), to: PersistenceManager.File.processedNotes)
            statusMessage = newItems.isEmpty
                ? "✓  Up to date"
                : "✓  \(newItems.count) new item\(newItems.count == 1 ? "" : "s") from Granola"
        } catch {
            statusMessage = "✗  \(error.localizedDescription)"
        }
    }

    // MARK: - Rendering

    private func render() {
        let items = navItems
        let w     = termWidth()
        var lines: [String] = []

        // ── Header ──────────────────────────────────────────────────────────
        let tc = items.filter { $0.itemType == .todo }.count
        let fc = items.filter { $0.itemType == .followup }.count
        lines.append("\u{1B}[1mOATS\u{1B}[0m  \u{1B}[2m\(tc) to-do\(tc == 1 ? "" : "s")  ·  \(fc) follow-up\(fc == 1 ? "" : "s")\u{1B}[0m")
        lines.append("")

        // ── Sections ────────────────────────────────────────────────────────
        renderSection("TO-DOS",
                      sectionItems: items.filter { $0.itemType == .todo },
                      allItems: items, w: w, into: &lines)
        lines.append("")
        renderSection("FOLLOW-UPS",
                      sectionItems: items.filter { $0.itemType == .followup },
                      allItems: items, w: w, into: &lines)

        // ── Divider ─────────────────────────────────────────────────────────
        lines.append("\u{1B}[2m" + String(repeating: "─", count: w) + "\u{1B}[0m")

        // ── Status message ──────────────────────────────────────────────────
        if !statusMessage.isEmpty {
            lines.append("\u{1B}[2m\(statusMessage)\u{1B}[0m")
        }

        // ── Key hints (truncated to fit) ─────────────────────────────────────
        let selected = selectedIndex < items.count ? items[selectedIndex] : nil
        var hintParts = ["↑↓ move", "⏎ done", "g open"]
        if selected?.itemType == .followup { hintParts.append("e email") }
        if let sel = selected {
            if PersistenceManager.noteExists(noteId: sel.noteId) { hintParts.append("n notes") }
            hintParts.append("c claude")
        }
        hintParts += ["s sync", "q quit"]
        let hintLine  = hintParts.joined(separator: "  ·  ")
        let hintTrunc = hintLine.count > w ? String(hintLine.prefix(w - 1)) + "…" : hintLine
        lines.append("\u{1B}[2m\(hintTrunc)\u{1B}[0m")

        // Build output: clear screen then join lines with \r\n
        let out = "\u{1B}[2J\u{1B}[H" + lines.joined(separator: "\r\n")
        print(out, terminator: "")
        fflush(stdout)
    }

    private func renderSection(_ title: String, sectionItems: [TodoItem],
                               allItems: [TodoItem], w: Int, into lines: inout [String]) {
        // Section header: bold title + dim count
        var header = "\u{1B}[1m\(title)\u{1B}[0m"
        if !sectionItems.isEmpty { header += "  \u{1B}[2m(\(sectionItems.count))\u{1B}[0m" }
        lines.append(header)

        if sectionItems.isEmpty {
            lines.append("  \u{1B}[2m(none)\u{1B}[0m")
            return
        }

        // Group by meeting
        var groups: [(title: String, date: Date, items: [TodoItem])] = []
        var indexMap: [String: Int] = [:]
        for item in sectionItems {
            if let i = indexMap[item.noteId] { groups[i].items.append(item) }
            else {
                indexMap[item.noteId] = groups.count
                groups.append((item.noteTitle, item.createdAt, [item]))
            }
        }

        let dateFmt = RelativeDateFormatter()
        // Prefix structure: "  ▶ ●  " = 7 visible chars (2 indent + arrow + space + dot + 2 spaces)
        let prefixW = 7
        // [AI] suffix visible width: 5 (" [AI]")
        let aiW     = 5

        for group in groups {
            // Truncate meeting name to fit: "  <title>  ·  <date>"
            let dateStr    = dateFmt.string(for: group.date)
            let sepW       = 6   // "  ·  " = 5 chars + 2 indent
            let maxTitleW  = max(8, w - sepW - dateStr.count - 2)
            let title      = group.title.count > maxTitleW
                ? String(group.title.prefix(maxTitleW - 1)) + "…"
                : group.title
            lines.append("")
            lines.append("  \u{1B}[2m\(title)  ·  \(dateStr)\u{1B}[0m")

            for item in group.items {
                guard let gi = allItems.firstIndex(where: { $0.id == item.id }) else { continue }
                let sel    = gi == selectedIndex
                let arrow  = sel ? "\u{1B}[32m▶\u{1B}[0m" : " "
                let dot    = sel ? "\u{1B}[32m●\u{1B}[0m" : "\u{1B}[2m○\u{1B}[0m"
                let isAI      = item.source == .ai
                let hasNotes  = PersistenceManager.noteExists(noteId: item.noteId)
                let notesW    = hasNotes ? 3 : 0   // " ·" visible width
                let maxTxt    = max(8, w - prefixW - (isAI ? aiW : 0) - notesW)
                var txt       = item.text
                if txt.count > maxTxt { txt = String(txt.prefix(maxTxt - 1)) + "…" }
                let ai        = isAI    ? "  \u{1B}[32m[AI]\u{1B}[0m" : ""
                let notesDot  = hasNotes ? "  \u{1B}[2m·\u{1B}[0m"    : ""
                let bold      = sel ? "\u{1B}[1m" : ""
                let rst       = "\u{1B}[0m"
                lines.append("  \(arrow) \(dot)  \(bold)\(txt)\(rst)\(ai)\(notesDot)")
            }
        }
    }

    // MARK: - Terminal setup

    private func enableRawMode() {
        tcgetattr(STDIN_FILENO, &oldTermios)
        var raw = oldTermios
        cfmakeraw(&raw)
        // cfmakeraw disables OPOST, which strips the CR from \r\n output.
        // Re-enable it so our \r\n line joins render correctly.
        raw.c_oflag |= tcflag_t(OPOST)
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
    }

    private func restoreTerminal() {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &oldTermios)
    }

    private func termWidth() -> Int {
        var ws = winsize()
        ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &ws)
        return ws.ws_col > 10 ? Int(ws.ws_col) : 80
    }

    // MARK: - Input

    enum KeyPress {
        case up, down, left, right
        case enter, space, escape, ctrlC
        case char(Character)
        case unknown
    }

    private func readKey() -> KeyPress {
        var buf = [UInt8](repeating: 0, count: 4)
        let n = read(STDIN_FILENO, &buf, 4)
        guard n > 0 else { return .unknown }

        // Escape sequence (arrow keys)
        if n >= 3, buf[0] == 0x1B, buf[1] == 0x5B {
            switch buf[2] {
            case 0x41: return .up
            case 0x42: return .down
            case 0x43: return .right
            case 0x44: return .left
            default:   break
            }
        }

        switch buf[0] {
        case 0x03:       return .ctrlC
        case 0x0D, 0x0A: return .enter
        case 0x20:       return .space
        case 0x1B:       return .escape
        default:
            return .char(Character(Unicode.Scalar(buf[0])))
        }
    }

    // MARK: - Helpers

    private func clampSelection() {
        let count = navItems.count
        guard count > 0 else { selectedIndex = 0; return }
        if selectedIndex >= count { selectedIndex = count - 1 }
    }
}

// MARK: - list (static, pipe-friendly)

struct ListCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "list",
        abstract:    "Print active items (pipe-friendly, non-interactive)."
    )

    func run() async throws {
        let todos     = loadTodos()
        let todoItems = todos.filter { $0.isActive && $0.itemType == .todo }
                             .sorted { $0.createdAt > $1.createdAt }
        let followups = todos.filter { $0.isActive && $0.itemType == .followup }
                             .sorted { $0.createdAt > $1.createdAt }

        if todoItems.isEmpty && followups.isEmpty {
            print("No active items. Run 'oats sync' to fetch from Granola.")
            return
        }

        var index = 1
        printSection("TO-DOS",      items: todoItems, startIndex: &index)
        printSection("FOLLOW-UPS",  items: followups, startIndex: &index)
    }
}

// MARK: - sync

struct SyncCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "sync",
        abstract:    "Fetch new action items from Granola."
    )

    @Option(name: .shortAndLong, help: "Days of history to fetch.")
    var days: Int = 14

    func run() async throws {
        guard !(KeychainManager.load(KeychainManager.Key.granolaAPIKey) ?? "").isEmpty else {
            print("No Granola API key set. Open the Oats app and add one in Settings.")
            throw ExitCode.failure
        }

        print("↻ Syncing with Granola (last \(days) days)…")

        var todos        = loadTodos()
        var processedIds = loadProcessedIds()
        let api          = GranolaAPI()

        let notes: [GranolaNote]
        do {
            notes = try await api.fetchRecentNotes(daysBack: days)
        } catch GranolaAPIError.badResponse(let code) {
            print("✗ Granola API error (HTTP \(code)).")
            throw ExitCode.failure
        } catch {
            print("✗ Sync failed: \(error.localizedDescription)")
            throw ExitCode.failure
        }

        let newNotes = notes.filter { processedIds.insert($0.id).inserted }
        var newItems: [TodoItem] = []
        for note in newNotes {
            if let md = note.summaryMarkdown, !md.isEmpty {
                PersistenceManager.saveNote(md, noteId: note.id)
            }
            newItems.append(contentsOf: await ActionItemExtractor.extractAsync(from: note))
        }

        todos.append(contentsOf: newItems)
        PersistenceManager.save(todos,               to: PersistenceManager.File.todos)
        PersistenceManager.save(Array(processedIds), to: PersistenceManager.File.processedNotes)

        if newItems.isEmpty {
            print("✓ Up to date — no new items found.")
        } else {
            let meetingCount = Set(newItems.map(\.noteId)).count
            print("✓ \(newItems.count) new item\(newItems.count == 1 ? "" : "s") from \(meetingCount) meeting\(meetingCount == 1 ? "" : "s").")
        }
    }
}

// MARK: - done

struct DoneCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "done",
        abstract:    "Mark an item as complete."
    )

    @Argument(help: "Item number shown in 'oats list'.")
    var number: Int

    func run() async throws {
        var todos  = loadTodos()
        let active = todos.filter { $0.isActive }.sorted { $0.createdAt > $1.createdAt }

        guard number >= 1, number <= active.count else {
            print("No item #\(number). Run 'oats list' to see current items.")
            throw ExitCode.failure
        }

        let target = active[number - 1]
        guard let idx = todos.firstIndex(where: { $0.id == target.id }) else { throw ExitCode.failure }

        todos[idx].completed   = true
        todos[idx].archived    = true
        todos[idx].completedAt = Date()

        PersistenceManager.save(todos, to: PersistenceManager.File.todos)
        print("✓ Done: \(target.text)")
    }
}

// MARK: - status

struct StatusCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "status",
        abstract:    "Show API key and license status."
    )

    func run() async throws {
        let hasGranola = !(KeychainManager.load(KeychainManager.Key.granolaAPIKey) ?? "").isEmpty
        let hasClaude  = !(KeychainManager.load(KeychainManager.Key.claudeAPIKey)  ?? "").isEmpty
        let userName   = UserDefaults(suiteName: "oats.prefs")?.string(forKey: "userName") ?? "(not set)"

        print("Granola API key : \(hasGranola ? "✓ set" : "✗ not set")")
        print("Claude API key  : \(hasClaude  ? "✓ set" : "– not set (optional)")")
        print("User            : \(userName)")

        let todos  = loadTodos()
        let active = todos.filter { $0.isActive }.count
        print("Active items    : \(active)")
    }
}

// MARK: - Shared helpers

private func loadTodos() -> [TodoItem] {
    PersistenceManager.load([TodoItem].self, from: PersistenceManager.File.todos) ?? []
}

private func loadProcessedIds() -> Set<String> {
    Set(PersistenceManager.load([String].self, from: PersistenceManager.File.processedNotes) ?? [])
}

private func printSection(_ title: String, items: [TodoItem], startIndex: inout Int) {
    guard !items.isEmpty else {
        print("\n\(title)\n  (none)")
        return
    }

    print("\n\(title)")

    var groups: [(noteId: String, title: String, items: [TodoItem])] = []
    var indexMap: [String: Int] = [:]
    for item in items {
        if let i = indexMap[item.noteId] { groups[i].items.append(item) }
        else {
            indexMap[item.noteId] = groups.count
            groups.append((item.noteId, item.noteTitle, [item]))
        }
    }

    let dateFmt = RelativeDateFormatter()
    for group in groups {
        print("\n  \(group.title)  ·  \(dateFmt.string(for: group.items[0].createdAt))")
        for item in group.items {
            let aiTag    = item.source == .ai ? " [AI]" : ""
            let notesTag = PersistenceManager.noteExists(noteId: item.noteId) ? " [notes]" : ""
            print("  [\(startIndex)] \(item.text)\(aiTag)\(notesTag)")
            startIndex += 1
        }
    }
}

// MARK: - Relative date

private struct RelativeDateFormatter {
    private let cal = Calendar.current

    func string(for date: Date) -> String {
        let now  = Date()
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                               to:   cal.startOfDay(for: now)).day ?? 0
        switch days {
        case 0:     return "Today"
        case 1:     return "Yesterday"
        case 2...6:
            let fmt = DateFormatter(); fmt.dateFormat = "EEEE"
            return fmt.string(from: date)
        default:
            let fmt = DateFormatter(); fmt.dateFormat = "MMM d"
            return fmt.string(from: date)
        }
    }
}
