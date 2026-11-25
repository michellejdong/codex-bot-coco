import AppKit
import SwiftUI

struct CocoDragSurface: NSViewRepresentable {
    var label: String
    var help: String
    var onClick: () -> Void
    var onDrop: (() -> Void)?

    func makeNSView(context: Context) -> CocoDragView { CocoDragView() }

    func updateNSView(_ view: CocoDragView, context: Context) {
        view.setAccessibilityLabel(label)
        view.setAccessibilityHelp(help)
        view.toolTip = help
        view.onClick = onClick
        view.onDrop = onDrop
    }
}

final class CocoDragView: NSView {
    var onClick: (() -> Void)?
    var onDrop: (() -> Void)?
    private var mouseStart: NSPoint?
    private var windowStart: NSPoint?
    private var dragging = false

    init() {
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        mouseStart = window?.convertPoint(toScreen: event.locationInWindow)
        windowStart = window?.frame.origin
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let mouseStart, let windowStart else { return }
        let pointer = window.convertPoint(toScreen: event.locationInWindow)
        let dx = pointer.x - mouseStart.x
        let dy = pointer.y - mouseStart.y
        guard dragging || hypot(dx, dy) >= 4 else { return }
        if !dragging { NSCursor.closedHand.push() }
        dragging = true
        window.setFrameOrigin(NSPoint(x: windowStart.x + dx, y: windowStart.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseStart = nil
            windowStart = nil
            dragging = false
        }
        if dragging {
            NSCursor.pop()
            if let window,
               let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? window.screen {
                let frame = window.frame
                let bounds = screen.visibleFrame
                window.setFrameOrigin(NSPoint(x: min(max(frame.minX, bounds.minX), max(bounds.minX, bounds.maxX - frame.width)),
                                              y: min(max(frame.minY, bounds.minY), max(bounds.minY, bounds.maxY - frame.height))))
            }
            onDrop?()
        } else if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick?()
        }
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return onClick != nil
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 { onClick?() }
        else { super.keyDown(with: event) }
    }
}
