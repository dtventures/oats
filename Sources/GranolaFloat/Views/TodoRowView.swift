import OatsCore
import SwiftUI
import AppKit

struct TodoRowView: View {
    let item: TodoItem
    var isSelected: Bool = false
    let onComplete: () -> Void

    @EnvironmentObject var store: TodoStore
    @State private var checkState: CheckState = .idle
    @State private var rowHovered = false
    @State private var checkHovered = false
    @State private var showDetail = false

    enum CheckState { case idle, checking, done }

    private var rowBackground: Color {
        if isSelected && checkState == .idle { return Color.granolaLight }
        if rowHovered  && checkState == .idle { return Color.creamHover }
        return .clear
    }

    // Pre-compute note existence once per render so badge slots are stable
    private var noteExists: Bool { PersistenceManager.noteExists(noteId: item.noteId) }

    var body: some View {
        let notesOpen = store.showingNoteId == item.noteId
        let showAI    = item.source == .ai
        let badgeVisible = rowHovered && checkState == .idle

        VStack(spacing: 0) {
            HStack(spacing: 10) {

                // ── Checkbox ──────────────────────────────────────────
                CheckCircle(
                    state: checkState,
                    hovered: checkHovered
                )
                .frame(width: 24, height: 24)
                .contentShape(Circle())
                .onHover { checkHovered = $0 }
                .onTapGesture { triggerComplete() }

                // ── Task text — tap to expand ─────────────────────────
                Text(item.text)
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundColor(checkState != .idle ? .textSecondary : .textPrimary)
                    .strikethrough(checkState != .idle, color: .textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeInOut(duration: 0.2), value: checkState)
                    .onTapGesture { showDetail = true }
                    .popover(isPresented: $showDetail, arrowEdge: .bottom) {
                        TodoDetailView(item: item, onOpenGranola: openInGranola)
                    }

                // ── AI badge — always in layout, fades in/out ─────────
                // Rendered as a fixed-width slot to prevent text reflow on hover.
                if showAI {
                    Text("AI")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.granolaGreen)
                        .padding(6)
                        .background(Color.granolaLight,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .opacity(badgeVisible ? 1 : 0)
                        .allowsHitTesting(badgeVisible)
                }

                // ── Notes badge — always in layout when note exists ───
                if noteExists {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            store.showingNoteId = notesOpen ? nil : item.noteId
                        }
                    } label: {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.granolaGreen)
                            .padding(6)
                            .background(notesOpen ? Color.granolaGreen.opacity(0.15) : Color.granolaLight,
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help(notesOpen ? "Close meeting notes" : "View meeting notes")
                    .opacity(badgeVisible ? 1 : 0)
                    .allowsHitTesting(badgeVisible)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 11)
            .padding(.bottom, isSelected ? 6 : 11)

            // ── Keyboard hint bar (selected only) ─────────────────
            if isSelected && checkState == .idle {
                HStack(spacing: 0) {
                    KeyHint(key: "⏎", label: "done")
                    KeyHintSep()
                    KeyHint(key: "G", label: "open")
                    if item.itemType == .followup {
                        KeyHintSep()
                        KeyHint(key: "E", label: "email")
                    }
                    Spacer()
                    KeyHint(key: "↑↓", label: "navigate")
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 6)
        .onHover { hovered in
            withAnimation(.easeOut(duration: 0.12)) { rowHovered = hovered }
        }
        .opacity(checkState == .done ? 0 : 1)
        .offset(x: checkState == .done ? 14 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 1.0), value: checkState == .done)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }

    private func triggerComplete() {
        guard checkState == .idle else { return }
        withAnimation(.easeInOut(duration: 0.18)) { checkState = .checking }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeInOut(duration: 0.28)) { checkState = .done }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            onComplete()
        }
    }

    private func openInGranola() {
        if let url = item.granolaURL {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Checkbox circle

struct CheckCircle: View {
    let state: TodoRowView.CheckState
    let hovered: Bool

    private var showCheck: Bool { state != .idle || hovered }
    private var filled: Bool    { state != .idle }

    var body: some View {
        ZStack {
            Circle()
                .stroke(filled ? Color.granolaGreen : (hovered ? Color.granolaGreen.opacity(0.55) : Color.checkboxBorder), lineWidth: 1.5)
                .background(Circle().fill(filled ? Color.granolaGreen : Color.clear))
                .frame(width: 20, height: 20)
                .animation(.easeInOut(duration: 0.15), value: filled)
                .animation(.easeInOut(duration: 0.12), value: hovered)

            if showCheck {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(filled ? .white : Color.granolaGreen.opacity(0.6))
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showCheck)
        .cursor(.pointingHand)
    }
}

// MARK: - Hover icon button

struct HoverIconButton: View {
    let systemImage: String
    let tint: Color
    let bgColor: Color
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(tint)
            .frame(width: 22, height: 22)
            .background(hovered ? bgColor : Color.clear, in: RoundedRectangle(cornerRadius: 5))
            .onHover { hovered = $0 }
            .onTapGesture { action() }
    }
}

// MARK: - Detail popover

struct TodoDetailView: View {
    let item: TodoItem
    let onOpenGranola: () -> Void
    @EnvironmentObject var store: TodoStore

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Full text
            Text(item.text)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)

            Divider().background(Color.creamDivider).padding(.bottom, 14)

            // Meeting
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
                Text(item.noteTitle)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if PersistenceManager.noteExists(noteId: item.noteId) {
                    Button { openNotes() } label: {
                        Image(systemName: "doc.text")
                            .font(.system(size: 13))
                            .foregroundColor(.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Open meeting notes")
                }
                Button { onOpenGranola() } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 13))
                        .foregroundColor(.granolaGreen)
                }
                .buttonStyle(.plain)
                .help("Open in Granola")
            }
            .padding(.bottom, 8)

            // Date
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
                Text(Self.dateFormatter.string(from: item.createdAt))
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
            }
            .padding(.bottom, (item.attendees.isEmpty && !hasEmailDraft) ? 0 : 14)

            // Attendees
            if !item.attendees.isEmpty {
                Divider().background(Color.creamDivider).padding(.bottom, 12)
                HStack(spacing: -4) {
                    ForEach(item.attendees) { a in
                        AvatarBubble(attendee: a, borderColor: .cream)
                    }
                    Spacer()
                }
                .padding(.bottom, hasEmailDraft ? 14 : 0)
            }

            // Draft email — all follow-up items
            if item.itemType == .followup {
                let email     = item.recipientEmail
                let recipient = email.flatMap { e in item.attendees.first { $0.email == e } }
                Divider().background(Color.creamDivider).padding(.bottom, 12)
                HStack(spacing: 10) {
                    if let recipient {
                        AvatarBubble(attendee: recipient, borderColor: .cream)
                    } else {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.checkboxBorder)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(recipient?.name ?? (email ?? "Unknown recipient"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.textPrimary)
                        if let email {
                            Text(email)
                                .font(.system(size: 10))
                                .foregroundColor(.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Button { openDraft(to: email ?? "", recipient: recipient) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "envelope")
                                .font(.system(size: 10, weight: .medium))
                            Text("Draft Email")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Color.granolaGreen, in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .frame(width: 340)
        .background(Color.cream)
        .preferredColorScheme(.light)
    }

    private var hasEmailDraft: Bool {
        item.itemType == .followup
    }

    private func openNotes() {
        withAnimation(.easeInOut(duration: 0.18)) {
            store.showingNoteId = store.showingNoteId == item.noteId ? nil : item.noteId
        }
    }

    private func openDraft(to email: String, recipient: Attendee?) {
        let senderName = UserDefaults(suiteName: "oats.prefs")?.string(forKey: "userName") ?? ""
        let firstName  = recipient?.firstName ?? ""
        let greeting   = firstName.isEmpty ? "Hi," : "Hi \(firstName),"
        let subject    = "Following up: \(item.noteTitle)"
        let body       = "\(greeting)\n\nFollowing up from \(item.noteTitle):\n\n\(item.text)\n\nBest,\n\(senderName)"

        // NSSharingService opens a native compose sheet and avoids
        // mailto: being hijacked by the browser when Chrome/Gmail
        // is set as the system default mail handler.
        if let service = NSSharingService(named: .composeEmail) {
            service.recipients = email.isEmpty ? [] : [email]
            service.subject    = subject
            service.perform(withItems: [body])
        }
    }
}

// MARK: - Keyboard hint helpers

private struct KeyHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.textSecondary.opacity(0.7))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.creamDivider.opacity(0.7), in: RoundedRectangle(cornerRadius: 3))
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.textSecondary.opacity(0.55))
        }
    }
}

private struct KeyHintSep: View {
    var body: some View {
        Text("·")
            .font(.system(size: 9))
            .foregroundColor(.textSecondary.opacity(0.3))
            .padding(.horizontal, 5)
    }
}

// MARK: - Cursor modifier

private struct CursorModifier: ViewModifier {
    let cursor: NSCursor
    func body(content: Content) -> some View {
        content.onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        modifier(CursorModifier(cursor: cursor))
    }
}
