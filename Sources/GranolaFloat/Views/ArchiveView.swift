import OatsCore
import SwiftUI
import AppKit

struct ArchiveView: View {
    @EnvironmentObject var store: TodoStore

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SectionHeader(label: "Completed", count: store.archivedItems.count)

                if store.archivedItems.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 28))
                            .foregroundColor(.checkboxBorder.opacity(0.5))
                        Text("Nothing archived yet")
                            .font(.system(size: 13))
                            .foregroundColor(.textSecondary.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else {
                    ForEach(Array(store.archivedItems.enumerated()), id: \.element.id) { i, item in
                        if i > 0 { RowDivider() }
                        ArchivedRowView(item: item)
                    }
                }

                Color.clear.frame(height: 8)
            }
        }
        .frame(maxHeight: 520)
    }
}

struct ArchivedRowView: View {
    let item: TodoItem
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            // Completed checkbox
            ZStack {
                Circle()
                    .stroke(Color.checkboxBorder, lineWidth: 1.5)
                    .frame(width: 20, height: 20)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.checkboxBorder)
            }
            .frame(width: 24, height: 24)

            Text(item.text)
                .font(.system(size: 13.5))
                .foregroundColor(.textSecondary)
                .strikethrough(true, color: .checkboxBorder)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            GuestAvatarsView(attendees: item.attendees)
                .frame(width: 64, alignment: .trailing)

            if hovered {
                HoverIconButton(systemImage: "doc.text", tint: .checkboxBorder, bgColor: Color.creamHover) {
                    if let url = URL(string: "granola://note/\(item.noteId)") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .help("Open in Granola: \(item.noteTitle)")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(hovered ? Color.creamHover : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 6)
        .onHover { hovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: hovered)
    }
}
