import SwiftUI
import AppKit

private func floatingPanel() -> FloatingPanel? {
    NSApp.windows.compactMap { $0 as? FloatingPanel }.first
}

struct PanelHeaderView: View {
    @EnvironmentObject var store: TodoStore
    @State private var trafficHovered = false

    var body: some View {
        HStack(spacing: 0) {
            // Traffic lights — all icons appear when hovering anywhere in the group
            HStack(spacing: 6) {
                TrafficLight(color: Color(red: 1, green: 0.357, blue: 0.341), icon: "xmark", showIcon: trafficHovered) {
                    floatingPanel()?.orderOut(nil)
                }
                TrafficLight(color: Color(red: 0.996, green: 0.737, blue: 0.180), icon: "minus", showIcon: trafficHovered) {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        store.isCompact.toggle()
                        if store.isCompact { store.isExpanded = false }
                    }
                }
                TrafficLight(color: Color(red: 0.157, green: 0.784, blue: 0.251), icon: "plus", showIcon: trafficHovered) {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        store.isExpanded.toggle()
                        if store.isExpanded { store.isCompact = false }
                    }
                }
            }
            .onHover { trafficHovered = $0 }
            .padding(.leading, 16)

            Spacer()

            // Right icons
            HStack(spacing: 2) {
                HeaderIconButton(systemImage: "checklist", active: store.view == .list) {
                    store.view = .list
                }
                HeaderIconButton(systemImage: "archivebox", active: store.view == .archive) {
                    store.view = .archive
                }
                HeaderIconButton(systemImage: "gearshape", active: store.view == .settings) {
                    store.view = .settings
                }
            }
            .padding(.trailing, 12)
        }
        .frame(height: 44)
    }
}

struct TrafficLight: View {
    let color:    Color
    let icon:     String   // SF Symbol shown when group is hovered
    let showIcon: Bool     // controlled by the parent HStack's onHover
    let action:   () -> Void
    @State private var selfHovered = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 13, height: 13)
                .overlay(Circle().stroke(Color.black.opacity(0.1), lineWidth: 0.5))

            if showIcon {
                Image(systemName: icon)
                    .font(.system(size: 6.5, weight: .black))
                    .foregroundColor(.black.opacity(0.45))
                    .transition(.opacity)
            }
        }
        .frame(width: 13, height: 13)
        .scaleEffect(selfHovered ? 1.12 : 1)
        .animation(.easeInOut(duration: 0.1), value: showIcon)
        .animation(.easeInOut(duration: 0.1), value: selfHovered)
        .onHover { selfHovered = $0 }
        .onTapGesture { action() }
        .cursor(.pointingHand)
    }
}

struct HeaderIconButton: View {
    let systemImage: String
    let active: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(active ? .textPrimary : .textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(active ? Color.creamHover : (hovered ? Color.creamHover.opacity(0.6) : Color.clear))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

struct SyncErrorBanner: View {
    let message:  String
    var onDismiss: () -> Void
    var onRetry:   () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundColor(Color(red: 0.75, green: 0.35, blue: 0.20))

            Text(message)
                .font(.system(size: 11))
                .foregroundColor(Color(red: 0.45, green: 0.22, blue: 0.10))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button("Retry") { onRetry() }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color(red: 0.75, green: 0.35, blue: 0.20))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Color(red: 0.90, green: 0.75, blue: 0.65).opacity(0.6),
                    in: RoundedRectangle(cornerRadius: 4)
                )

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color(red: 0.75, green: 0.35, blue: 0.20))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(red: 0.98, green: 0.93, blue: 0.88))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct SyncBarView: View {
    @EnvironmentObject var store: TodoStore

    var syncLabel: String {
        guard let d = store.lastSynced else { return "Never synced" }
        let diff = Int(Date().timeIntervalSince(d))
        if diff < 60 { return "Just now" }
        if diff < 3600 { return "\(diff / 60)m ago" }
        return "\(diff / 3600)h ago"
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(store.isSyncing ? Color.yellow : Color.granolaGreen)
                .frame(width: 6, height: 6)
                .opacity(store.isSyncing ? 0.8 : 1)

            Text(store.isSyncing ? "Syncing with Granola…" : "Granola · \(syncLabel)")
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)

            Spacer()

            Button("Sync") {
                Task { await store.sync() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.granolaGreen)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.granolaLight, in: RoundedRectangle(cornerRadius: 4))
            .disabled(store.isSyncing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}
