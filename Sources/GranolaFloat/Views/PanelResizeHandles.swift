import AppKit
import SwiftUI

// MARK: - NSView that handles edge/corner drag-to-resize
// Pins the top-right corner of the panel so the window never "moves"
// during a height or width resize — only bottom/left edges move.

final class EdgeResizeView: NSView {
    enum Edge { case bottom, left, bottomLeft }

    private let edge: Edge
    private var dragStart:  NSPoint = .zero
    private var frameStart: NSRect  = .zero

    init(edge: Edge) {
        self.edge = edge
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() {
        let cursor: NSCursor
        switch edge {
        case .bottom:     cursor = .resizeUpDown
        case .left:       cursor = .resizeLeftRight
        case .bottomLeft: cursor = .crosshair
        }
        addCursorRect(bounds, cursor: cursor)
    }

    override func mouseDown(with event: NSEvent) {
        // Use absolute screen coordinates — these don't shift as the window resizes,
        // eliminating the "jumping" caused by view-local coordinate changes.
        dragStart  = NSEvent.mouseLocation
        frameStart = window?.frame ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let win = window else { return }
        let loc  = NSEvent.mouseLocation   // stable screen coords
        let minW = win.minSize.width
        let minH = win.minSize.height
        var f    = frameStart

        switch edge {
        case .bottom:
            // macOS y increases upward; dragging down → loc.y < dragStart.y → dY negative
            let dY = loc.y - dragStart.y
            f.size.height = max(minH, frameStart.height - dY)
            f.origin.y    = frameStart.maxY - f.size.height   // pin top

        case .left:
            // dragging left → loc.x < dragStart.x → dX negative → width grows
            let dX = loc.x - dragStart.x
            f.size.width  = max(minW, frameStart.width - dX)
            f.origin.x    = frameStart.maxX - f.size.width    // pin right

        case .bottomLeft:
            let dX = loc.x - dragStart.x
            let dY = loc.y - dragStart.y
            f.size.width  = max(minW, frameStart.width  - dX)
            f.size.height = max(minH, frameStart.height - dY)
            f.origin.x    = frameStart.maxX - f.size.width
            f.origin.y    = frameStart.maxY - f.size.height
        }

        win.setFrame(f, display: true, animate: false)
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - SwiftUI wrappers

struct BottomEdgeResizer: NSViewRepresentable {
    func makeNSView(context: Context) -> EdgeResizeView { EdgeResizeView(edge: .bottom) }
    func updateNSView(_ v: EdgeResizeView, context: Context) {}
}

struct LeftEdgeResizer: NSViewRepresentable {
    func makeNSView(context: Context) -> EdgeResizeView { EdgeResizeView(edge: .left) }
    func updateNSView(_ v: EdgeResizeView, context: Context) {}
}

struct BottomLeftCornerResizer: NSViewRepresentable {
    func makeNSView(context: Context) -> EdgeResizeView { EdgeResizeView(edge: .bottomLeft) }
    func updateNSView(_ v: EdgeResizeView, context: Context) {}
}

// MARK: - Invisible bottom resize bar (hit area only, no visual chrome)

struct ResizeBar: View {
    var body: some View {
        BottomEdgeResizer()
            .frame(height: 14)
            .frame(maxWidth: .infinity)
    }
}
