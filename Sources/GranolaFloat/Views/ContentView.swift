import SwiftUI
import OatsCore

struct ContentView: View {
    @EnvironmentObject var store: TodoStore

    var body: some View {
        ZStack {
            // ── Card content ──────────────────────────────────────────────
            VStack(spacing: 0) {
                PanelHeaderView()

                if store.showPaywall {
                    // Trial expired — replace all content with the paywall
                    PaywallView {
                        store.showPaywall = false
                    }
                } else if !store.isCompact {
                    // SyncBar only on list/archive, not inside settings
                    if store.view != .settings {
                        SyncBarView()

                        if let err = store.syncError {
                            SyncErrorBanner(message: err) {
                                store.syncError = nil
                            } onRetry: {
                                store.syncError = nil
                                Task { await store.sync() }
                            }
                        }
                    }

                    Divider()
                        .background(Color.creamDivider)
                        .padding(.horizontal, 12)

                    Group {
                        switch store.view {
                        case .list:     TodoListView()
                        case .archive:  ArchiveView()
                        case .settings: AppSettingsView()
                        }
                    }
                    .animation(.easeInOut(duration: 0.18), value: store.view)

                    // Trial banner pinned to the bottom, above the resize handle
                    if LicenseManager.isTrialActive && !LicenseManager.isUnlocked {
                        TrialBannerView(daysLeft: LicenseManager.daysRemaining) {
                            store.view = .settings
                        }
                    }
                }
            }
            .background(Color.cream)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // ── Resize handles — always at actual window edges ────────────
            if !store.isCompact {
                // Bottom edge
                VStack(spacing: 0) {
                    Spacer()
                    ResizeBar()
                }

                // Left edge
                HStack(spacing: 0) {
                    LeftEdgeResizer().frame(width: 12)
                    Spacer()
                }

                // Bottom-left corner
                VStack(spacing: 0) {
                    Spacer()
                    HStack(spacing: 0) {
                        BottomLeftCornerResizer().frame(width: 20, height: 20)
                        Spacer()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.22), value: store.isCompact)
        .animation(.easeInOut(duration: 0.22), value: store.isExpanded)
        .preferredColorScheme(.light)
    }
}
