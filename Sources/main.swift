import AppKit
import EventKit
import SwiftUI

final class CocoPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class CocoApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = CocoModel()
    private let window = CocoWindow()
    private var panel: CocoPanel!
    private var statusItem: NSStatusItem?
    private let compactSize = NSSize(width: 119, height: 112)
    private let anchorKey = "coco.windowAnchor"
    private var speechPanel: CocoPanel?
    private var speechHost: CocoSpeechHost?
    private var speechQueue: [CocoSpeech] = []
    private var visibleSpeech: CocoSpeech?
    private var speechLayout: (pointer: BubblePointer, fraction: CGFloat, size: CGSize)?
    private var dismissTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let size = compactSize
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        let initial = NSPoint(x: screen.maxX - 24, y: screen.maxY - 36)
        let saved = UserDefaults.standard.array(forKey: anchorKey) as? [Double] ?? []
        let remembered = saved.count == 2 ? NSPoint(x: saved[0], y: saved[1]) : initial
        let start = NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -1, dy: -1).contains(remembered) }) ? remembered : initial
        let restored = NSRect(origin: NSPoint(x: start.x - size.width, y: start.y - size.height), size: size)
        panel = CocoPanel(contentRect: restored, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.title = "Coco"
        panel.delegate = self
        panel.setAccessibilityTitle("Coco")
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        let host = NSHostingView(rootView: CocoView(model: model, window: window))
        host.sizingOptions = []
        panel.contentView = host
        panel.orderFrontRegardless()
        window.resize = { [weak self] expanded in self?.resize(expanded: expanded) }
        window.rememberPosition = { [weak self] in
            guard let self else { return }
            UserDefaults.standard.set([self.panel.frame.maxX, self.panel.frame.maxY], forKey: self.anchorKey)
        }
        model.show = { [weak self] in self?.showCoco() }
        model.speak = { [weak self] speech in self?.enqueueSpeech(speech) }
        model.refresh()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "heart.circle", accessibilityDescription: "Coco")
        item.button?.toolTip = "Coco"
        let menu = NSMenu(title: "Coco")
        let show = NSMenuItem(title: "Show Coco", action: #selector(showCoco), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        let collapse = NSMenuItem(title: "Collapse Coco", action: #selector(collapseCoco), keyEquivalent: "")
        collapse.target = self
        menu.addItem(collapse)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Coco", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--open") { showCoco() }
        if let sample: CocoTest = arguments.contains("--test-room") ? .room : (arguments.contains("--test-zoom") ? .zoom : nil) {
            showCoco()
            model.scheduleTest(sample) { [weak self] in self?.collapseCoco() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showCoco()
        return true
    }

    private func resize(expanded: Bool) {
        let current = panel.frame
        let bounds = (panel.screen ?? NSScreen.main)?.visibleFrame ?? current.insetBy(dx: -450, dy: -500)
        let width = min(expanded ? 400.0 : compactSize.width, bounds.width)
        let height = min(expanded ? 535.0 : compactSize.height, bounds.height)
        let x = min(max(current.maxX - width, bounds.minX), bounds.maxX - width)
        let y = min(max(current.maxY - height, bounds.minY), bounds.maxY - height)
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        if expanded {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
        positionSpeech()
    }

    @objc private func showCoco() {
        window.setExpanded(true)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func collapseCoco() { window.setExpanded(false) }

    func windowDidMove(_ notification: Notification) { positionSpeech() }

    private func enqueueSpeech(_ speech: CocoSpeech) {
        speechQueue.append(speech)
        if visibleSpeech == nil { showNextSpeech() }
    }

    private func showNextSpeech() {
        guard !speechQueue.isEmpty else { return }
        let speech = speechQueue.removeFirst()
        visibleSpeech = speech
        speechLayout = nil
        if speechPanel == nil {
            let bubble = CocoPanel(contentRect: NSRect(x: 0, y: 0, width: 302, height: 100),
                                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            bubble.title = "Coco reminder"
            bubble.setAccessibilityTitle("Coco reminder")
            bubble.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
            bubble.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            bubble.isOpaque = false
            bubble.backgroundColor = .clear
            bubble.hasShadow = false
            bubble.hidesOnDeactivate = false
            bubble.becomesKeyOnlyIfNeeded = true
            let host = CocoSpeechHost(rootView: speechView(speech, pointer: .left, fraction: 0.5))
            bubble.contentView = host
            speechHost = host
            speechPanel = bubble
        }
        positionSpeech()
        speechPanel?.orderFrontRegardless()
        if speech.lifetime > 24, let bubble = speechPanel {
            NSLog("Test reminder: visible=%@, size=%.0fx%.0f", bubble.isVisible ? "yes" : "no", bubble.frame.width, bubble.frame.height)
        }
        let timer = Timer(timeInterval: speech.lifetime, repeats: false) { [weak self] _ in self?.dismissSpeech() }
        dismissTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func speechView(_ speech: CocoSpeech, pointer: BubblePointer, fraction: CGFloat) -> CocoSpeechView {
        CocoSpeechView(speech: speech, pointer: pointer, fraction: fraction) { [weak self] in self?.dismissSpeech() }
    }

    private func positionSpeech() {
        guard let speech = visibleSpeech, let speechPanel, let speechHost, let screen = panel.screen ?? NSScreen.main else { return }
        let frame = panel.frame
        let avatar = window.expanded ? CGPoint(x: frame.minX + 64, y: frame.maxY - 55) : CGPoint(x: frame.midX, y: frame.midY + 4)
        var layout = speechLayout
        if layout == nil {
            speechHost.rootView = speechView(speech, pointer: .left, fraction: 0.5)
            layout = (.left, 0.5, CGSize(width: 302, height: max(52, speechHost.fittingSize.height)))
        }
        guard let layout else { return }
        var found = BubblePlacement.beside(window: frame, avatar: avatar, size: layout.size, on: screen.visibleFrame)
        let sideChanged = layout.pointer != found.pointer
        let shouldDraw = speechLayout == nil || sideChanged || abs(layout.fraction - found.fraction) > 0.025
        if shouldDraw {
            speechHost.rootView = speechView(speech, pointer: found.pointer, fraction: found.fraction)
            var size = layout.size
            if sideChanged {
                size = CGSize(width: 302, height: max(52, speechHost.fittingSize.height))
                found = BubblePlacement.beside(window: frame, avatar: avatar, size: size, on: screen.visibleFrame)
                speechHost.rootView = speechView(speech, pointer: found.pointer, fraction: found.fraction)
            }
            speechLayout = (found.pointer, found.fraction, size)
        }
        speechPanel.setFrame(found.frame, display: shouldDraw)
    }

    private func dismissSpeech() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        speechPanel?.orderOut(nil)
        visibleSpeech = nil
        showNextSpeech()
    }
}

if CommandLine.arguments.contains("--self-test") {
    runCocoChecks()
} else {
    let app = NSApplication.shared
    _ = app.setActivationPolicy(.accessory)
    let delegate = CocoApp()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
