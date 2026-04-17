import OatsCore
import SwiftUI
import AppKit

struct TodoListView: View {
    @EnvironmentObject var store: TodoStore
    @State private var completingIds = Set<String>()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    // ── To-Dos ──
                    SectionHeader(label: "To-Dos", count: store.activeTodos.count)

                    if store.activeTodos.isEmpty {
                        EmptyRow()
                    } else {
                        ForEach(grouped(store.activeTodos)) { group in
                            MeetingGroupHeader(title: group.noteTitle, noteId: group.id, url: group.url, attendees: group.attendees)
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { i, item in
                                if i > 0 { RowDivider() }
                                TodoRowView(
                                    item: item,
                                    isSelected: store.selectedItemId == item.id
                                ) {
                                    complete(item)
                                }
                                .id(item.id)
                                .transition(.asymmetric(
                                    insertion: .opacity,
                                    removal: .opacity.combined(with: .offset(x: 16))
                                ))
                            }
                        }
                    }

                    // ── Follow-Ups ──
                    SectionHeader(label: "Follow-Ups", count: store.activeFollowups.count)
                        .padding(.top, 4)

                    if store.activeFollowups.isEmpty {
                        EmptyRow()
                    } else {
                        ForEach(grouped(store.activeFollowups)) { group in
                            MeetingGroupHeader(title: group.noteTitle, noteId: group.id, url: group.url, attendees: group.attendees)
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { i, item in
                                if i > 0 { RowDivider() }
                                TodoRowView(
                                    item: item,
                                    isSelected: store.selectedItemId == item.id
                                ) {
                                    complete(item)
                                }
                                .id(item.id)
                                .transition(.asymmetric(
                                    insertion: .opacity,
                                    removal: .opacity.combined(with: .offset(x: 16))
                                ))
                            }
                        }
                    }

                    // Bottom padding
                    Color.clear.frame(height: 8)
                }
                .animation(.easeInOut(duration: 0.3), value: store.todos.map(\.id))
            }
            .onChange(of: store.selectedItemId) { _, id in
                if let id {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Grouping

    private struct TodoGroup: Identifiable {
        let id: String       // noteId — stable identity for ForEach
        let noteTitle: String
        let url: URL?
        let attendees: [Attendee]
        var items: [TodoItem]
    }

    /// Preserves the existing sort order (newest meeting first) while
    /// collecting items from the same meeting into a single group.
    private func grouped(_ items: [TodoItem]) -> [TodoGroup] {
        var indexMap: [String: Int] = [:]
        var groups: [TodoGroup] = []
        for item in items {
            if let idx = indexMap[item.noteId] {
                groups[idx].items.append(item)
            } else {
                indexMap[item.noteId] = groups.count
                groups.append(TodoGroup(
                    id: item.noteId,
                    noteTitle: item.noteTitle,
                    url: item.granolaURL,
                    attendees: item.attendees,
                    items: [item]
                ))
            }
        }
        return groups
    }

    private func complete(_ item: TodoItem) {
        withAnimation(.easeInOut(duration: 0.3)) {
            store.complete(item)
        }
    }
}

// MARK: - Meeting group header

private struct MeetingGroupHeader: View {
    let title: String
    let noteId: String
    let url: URL?
    let attendees: [Attendee]
    @EnvironmentObject var store: TodoStore
    @State private var hovered = false

    private var hasNotes: Bool { PersistenceManager.noteExists(noteId: noteId) }
    private var notesActive: Bool { store.showingNoteId == noteId }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.textSecondary.opacity(0.55))

            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            if !attendees.isEmpty {
                GuestAvatarsView(attendees: attendees)
            }

            // Notes icon — shown when a .md file exists for this meeting
            if hasNotes {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        store.showingNoteId = notesActive ? nil : noteId
                    }
                } label: {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(notesActive ? .granolaGreen : (hovered ? .granolaGreen.opacity(0.7) : .textSecondary.opacity(0.4)))
                }
                .buttonStyle(.plain)
                .help(notesActive ? "Close meeting notes" : "View meeting notes")
                .animation(.easeInOut(duration: 0.12), value: notesActive)
            }

            if let url = url {
                Button { NSWorkspace.shared.open(url) } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(hovered ? .granolaGreen : .textSecondary.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help("Open in Granola")
                .animation(.easeInOut(duration: 0.12), value: hovered)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 2)
        .onHover { hovered = $0 }
    }
}

// MARK: - Supporting views

struct SectionHeader: View {
    let label: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.sectionLabel)
                .kerning(1.2)

            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.sectionLabel)
                    .padding(.horizontal, 6)
                    .background(Color.badgeBg, in: Capsule())
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}

struct RowDivider: View {
    var body: some View {
        Divider()
            .background(Color.creamDivider.opacity(0.6))
            .padding(.leading, 48)
            .padding(.trailing, 20)
    }
}

struct EmptyRow: View {
    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .stroke(Color.checkboxBorder.opacity(0.4), lineWidth: 1.5)
                .frame(width: 20, height: 20)
            Text("Nothing here")
                .font(.system(size: 13))
                .foregroundColor(.textSecondary.opacity(0.5))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}
