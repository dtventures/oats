import AppKit
import SwiftUI
import OatsCore

final class FloatingPanel: NSPanel {
    weak var store: TodoStore?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 560),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        level                       = .floating
        backgroundColor             = .clear
        isOpaque                    = false
        hasShadow                   = true         // system shadow follows rounded shape
        isMovableByWindowBackground = true
        hidesOnDeactivate           = false
        // .managed keeps it on one Space; omitting .canJoinAllSpaces stops it following swipes
        collectionBehavior          = [.managed, .fullScreenAuxiliary]
        animationBehavior           = .none
        minSize                     = NSSize(width: 320, height: 200)
    }

    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { false }

    // Become key on any click so SwiftUI receives the event immediately
    // instead of consuming it as a window-activation click
    override func mouseDown(with event: NSEvent) {
        if !isKeyWindow { makeKey() }
        super.mouseDown(with: event)
    }

    // Forward Cmd+V/C/X/A to the focused text field.
    // These shortcuts normally route through the MAIN window's responder chain.
    // Since this panel can't be main, we intercept them here and send directly.
    override func keyDown(with event: NSEvent) {
        // Always let text fields consume keys first
        if firstResponder is NSTextView {
            super.keyDown(with: event)
            return
        }

        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let code = event.keyCode

        // ── Arrow-key navigation (list view only, no modifiers) ──────────
        if mods.isEmpty, let store, store.view == .list {
            switch code {
            case 125: store.selectNext();     return  // ↓
            case 126: store.selectPrevious(); return  // ↑
            case 36, 49:                              // Return / Space
                store.completeSelected(); return
            case 53:                                  // Escape
                store.selectedItemId = nil; return
            default: break
            }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "g": store.openSelectedInGranola(); return
            case "e": store.draftEmailForSelected();  return
            default:  break
            }
        }

        // ── Cmd shortcuts forwarded to first responder ───────────────────
        guard mods == .command else {
            super.keyDown(with: event)
            return
        }
        let forwarded: Bool
        switch event.charactersIgnoringModifiers {
        case "v": forwarded = NSApp.sendAction(#selector(NSText.paste(_:)),     to: nil, from: self)
        case "c": forwarded = NSApp.sendAction(#selector(NSText.copy(_:)),      to: nil, from: self)
        case "x": forwarded = NSApp.sendAction(#selector(NSText.cut(_:)),       to: nil, from: self)
        case "a": forwarded = NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
        case "z": forwarded = NSApp.sendAction(Selector(("undo:")),             to: nil, from: self)
        default:  forwarded = false
        }
        if !forwarded { super.keyDown(with: event) }
    }
}

// NSHostingView that accepts the first mouse click as an action
// (default behaviour discards first click on non-key windows)
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var focusRingType: NSFocusRingType {
        get { .none }
        set { }
    }
    // Prevent SwiftUI from driving window resize via intrinsic content size.
    // The panel manages its own frame explicitly; letting the hosting view
    // report a changing intrinsic size causes width/height jumps when the
    // SwiftUI content switches between views (list → settings, etc.).
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}
