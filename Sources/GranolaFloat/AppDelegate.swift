import OatsCore
import AppKit
import SwiftUI
import UserNotifications
import Combine

extension Notification.Name {
    static let showOnboarding = Notification.Name("showOnboarding")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: FloatingPanel!
    var statusItem: NSStatusItem!
    var onboardingWindow: NSWindow?
    var notesPanel: NSPanel?
    let store = TodoStore()

    private var syncTimer:   Timer?
    private var cancellables = Set<AnyCancellable>()
    private static let notesPanelWidth: CGFloat = 360
    // Height before settings/paywall was opened — restored on return to list
    private var priorPanelHeight: CGFloat = 560
    // Fixed heights for non-list views
    private static let settingsHeight: CGFloat = 580
    private static let paywallHeight:  CGFloat = 420

    func applicationDidFinishLaunching(_ notification: Notification) {
        KeychainManager.migrateFromUserDefaultsIfNeeded()
        LicenseManager.recordFirstLaunchIfNeeded()
        setupMainMenu()

        // Set Dock + App Switcher icon from bundled asset
        if let url = Bundle.appResources.url(forResource: "OatIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }

        setupPanel()
        setupStatusItem()

        // Re-pin if the screen configuration changes (resolution, display plugged in, etc.)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowOnboarding),
            name: .showOnboarding,
            object: nil
        )

        requestNotificationPermission()

        if needsOnboarding {
            showOnboarding()
        } else {
            Task { await store.sync() }
            startAutoSync()
        }

        // Re-validate cached license against Lemon Squeezy on each launch
        Task { await LicenseManager.revalidateCachedLicense() }
    }

    // Show onboarding whenever there is no API key — the completed flag alone
    // is not sufficient because a keychain migration wipes the old item.
    private var needsOnboarding: Bool {
        let hasKey = !(KeychainManager.load(KeychainManager.Key.granolaAPIKey) ?? "").isEmpty
        return !hasKey
    }

    // MARK: - Application menu

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // ── Oats ──────────────────────────────────────────────────────────
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Oats",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // ── Edit  (Cmd+V/C/X/A route through this menu to the first responder)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo",       action: Selector(("undo:")),                   keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo",       action: Selector(("redo:")),                   keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut",        action: #selector(NSText.cut(_:)),             keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy",       action: #selector(NSText.copy(_:)),            keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste",      action: #selector(NSText.paste(_:)),           keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)),       keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    private func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func startAutoSync() {
        syncTimer?.invalidate()
        // Sync every 30 seconds automatically
        syncTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { await self?.store.sync() }
        }
    }

    func showOnboarding() {
        let view = OnboardingView { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            Task { await self?.store.resetAndSync() }
            self?.startAutoSync()
        }
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = ""
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.setContentSize(NSSize(width: 480, height: 380))
        window.isReleasedWhenClosed = false
        window.center()
        window.backgroundColor = NSColor(Color.cream)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
        onboardingWindow = window
    }

    // MARK: - Panel

    func setupPanel() {
        panel = FloatingPanel()
        panel.store = store
        panel.contentView = PassthroughHostingView(rootView: ContentView().environmentObject(store))
        pinToTop()
        panel.makeKeyAndOrderFront(nil)

        // Auto-resize for settings and paywall; restore when returning to list/archive.
        store.$view
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newView in
                guard let self else { return }
                if newView == .settings {
                    self.priorPanelHeight = self.panel.frame.height
                    self.resizePanel(to: AppDelegate.settingsHeight)
                } else if !self.store.showPaywall {
                    self.resizePanel(to: self.priorPanelHeight)
                }
            }
            .store(in: &cancellables)

        // Show/resize paywall when trial expires
        store.$showPaywall
            .receive(on: DispatchQueue.main)
            .sink { [weak self] showing in
                guard let self else { return }
                if showing {
                    self.priorPanelHeight = self.panel.frame.height
                    self.resizePanel(to: AppDelegate.paywallHeight)
                } else {
                    self.resizePanel(to: self.priorPanelHeight)
                }
            }
            .store(in: &cancellables)

        // Open / close / update the notes side panel
        store.$showingNoteId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] noteId in
                guard let self else { return }
                if let noteId {
                    self.openNotesPanel(noteId: noteId)
                } else {
                    self.closeNotesPanel()
                }
            }
            .store(in: &cancellables)

        // Check license state now and whenever the app becomes active
        checkLicense()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(checkLicenseOnActivate),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    /// Resize the panel to the given height, keeping the top-right corner fixed.
    private func resizePanel(to newHeight: CGFloat) {
        var f = panel.frame
        let clampedH = max(CGFloat(panel.minSize.height), newHeight)
        f.origin.y    = f.maxY - clampedH
        f.size.height = clampedH
        panel.setFrame(f, display: true, animate: false)
    }

    /// Positions the panel at the top-right of the main screen, just below the menu bar.
    /// Called on launch and whenever the screen layout changes.
    func pinToTop() {
        guard let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame          // excludes menu bar and dock
        let pw = panel.frame.width
        let ph = panel.frame.height
        let x  = sf.maxX - pw - 16           // right-aligned with a small margin
        let y  = sf.maxY - ph                // flush with the top of the visible area
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        positionNotesPanel()
    }

    @objc private func screenDidChange() { pinToTop() }

    // MARK: - Notes panel

    private func openNotesPanel(noteId: String) {
        guard let markdown = PersistenceManager.loadNote(noteId: noteId), !markdown.isEmpty else {
            store.showingNoteId = nil
            return
        }
        let title = store.todos.first { $0.noteId == noteId }?.noteTitle ?? "Meeting Notes"

        let view = NotesPanelView(noteTitle: title, markdown: markdown)
            .environmentObject(store)

        if let existing = notesPanel {
            // Swap content in-place — no flicker
            existing.contentView = NSHostingView(rootView: view)
            positionNotesPanel()
        } else {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: AppDelegate.notesPanelWidth, height: panel.frame.height),
                styleMask:   [.borderless, .nonactivatingPanel],
                backing:     .buffered,
                defer:       false
            )
            p.level                       = .floating
            p.backgroundColor             = .clear
            p.isOpaque                    = false
            p.hasShadow                   = true
            p.hidesOnDeactivate           = false
            p.collectionBehavior          = [.managed, .fullScreenAuxiliary]
            p.contentView                 = NSHostingView(rootView: view)
            notesPanel = p
            positionNotesPanel()
            p.makeKeyAndOrderFront(nil)
        }
    }

    private func closeNotesPanel() {
        notesPanel?.close()
        notesPanel = nil
    }

    private func positionNotesPanel() {
        guard let np = notesPanel else { return }
        let gap: CGFloat = 8
        let x = panel.frame.minX - AppDelegate.notesPanelWidth - gap
        let y = panel.frame.minY
        let h = panel.frame.height
        np.setFrame(NSRect(x: x, y: y, width: AppDelegate.notesPanelWidth, height: h), display: true)
    }

    @objc private func handleShowOnboarding() {
        // Close any existing onboarding window first
        onboardingWindow?.close()
        onboardingWindow = nil
        showOnboarding()
    }

    // MARK: - Menu bar icon

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "checklist",
            accessibilityDescription: "Oats"
        )

        let menu = NSMenu()
        menu.addItem(withTitle: "Show Panel",   action: #selector(showPanel),  keyEquivalent: "")
        menu.addItem(withTitle: "Sync Now",     action: #selector(syncNow),    keyEquivalent: "r")
        menu.addItem(.separator())

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit",        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc func showPanel() {
        pinToTop()
        panel.makeKeyAndOrderFront(nil)
    }

    @objc func syncNow() {
        Task { await store.sync() }
    }

    // MARK: - License / paywall

    @objc private func checkLicenseOnActivate() { checkLicense() }

    private func checkLicense() {
        // Show paywall if trial has ended and no valid license
        let shouldShow = !LicenseManager.canUseApp
        if store.showPaywall != shouldShow {
            store.showPaywall = shouldShow
        }
    }
}
