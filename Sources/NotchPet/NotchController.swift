import AppKit
import Combine
import SwiftUI

final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // Let the panel sit over the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Places the panel over the notch and drives hover / toast / collapse.
@MainActor
final class NotchController {
    private let panel = NotchPanel()
    private let store: SessionStore
    private let ui: NotchUI
    private var screen: NSScreen = NSScreen.main ?? NSScreen.screens[0]
    private var hovering = false
    private var hoverIn: Date?
    private var hoverOut: Date?
    private var mouseTimer: Timer?
    private var bag: Set<AnyCancellable> = []

    init(store: SessionStore, ui: NotchUI) {
        self.store = store
        self.ui = ui
        let host = NSHostingView(rootView: RootView(store: store, ui: ui))
        host.sizingOptions = []
        panel.contentView = host
        updateGeometry()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateGeometry() }
        }
        store.$toast.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateMode() }
        }.store(in: &bag)

        mouseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackMouse() }
        }
    }

    private func updateGeometry() {
        screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        let top = screen.safeAreaInsets.top
        if top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            ui.notchWidth = screen.frame.width - l.width - r.width
            ui.notchHeight = top
        } else {
            // No notch: draw a small pill under the menu bar's top edge.
            ui.notchWidth = 120
            ui.notchHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
        }
        layoutWindow()
    }

    private func size(_ mode: NotchMode) -> CGSize { ui.size(for: mode, rows: store.sessions.count) }

    /// The panel never resizes (resizing made the content jump to a corner and back).
    /// It is sized for the biggest state; the black shape animates inside it, and clicks
    /// outside the shape pass through via `ignoresMouseEvents`.
    private func layoutWindow() {
        let big = ui.size(for: .expanded, rows: NotchUI.maxRows), toast = ui.size(for: .toast, rows: 0)
        let w = max(big.width, toast.width) + 20, h = max(big.height, toast.height) + 10
        let f = screen.frame
        panel.setFrame(NSRect(x: f.midX - w / 2, y: f.maxY - h, width: w, height: h), display: true)
    }

    private func shapeRect(_ mode: NotchMode) -> NSRect {
        let s = size(mode)
        let f = screen.frame
        return NSRect(x: f.midX - s.width / 2, y: f.maxY - s.height, width: s.width, height: s.height)
    }

    private func updateMode() {
        let desired: NotchMode = hovering ? .expanded : (store.toast != nil ? .toast : .collapsed)
        guard desired != ui.mode else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { ui.mode = desired }
    }

    private func trackMouse() {
        let p = NSEvent.mouseLocation
        let now = Date()
        let zone = shapeRect(ui.mode).insetBy(dx: -4, dy: -4)
        let overShape = shapeRect(ui.mode).contains(p)
        if panel.ignoresMouseEvents == overShape { panel.ignoresMouseEvents = !overShape }
        if zone.contains(p) {
            hoverOut = nil
            if !hovering {
                if hoverIn == nil { hoverIn = now }
                if now.timeIntervalSince(hoverIn!) > 0.12 {
                    hovering = true
                    store.dismissToast()
                    updateMode()
                }
            }
        } else {
            hoverIn = nil
            if hovering {
                if hoverOut == nil { hoverOut = now }
                if now.timeIntervalSince(hoverOut!) > 0.35 {
                    hovering = false
                    ui.showPicker = false
                    updateMode()
                }
            }
        }

        // Pip's eyes follow the cursor.
        let collapsed = size(.collapsed)
        let center = CGPoint(x: screen.frame.midX - ui.notchWidth / 2 - NotchUI.wing / 2,
                             y: screen.frame.maxY - collapsed.height / 2)
        let dx = p.x - center.x, dy = center.y - p.y
        let len = max(hypot(dx, dy), 1)
        let reach = min(len / 160, 1)
        let look = CGPoint(x: dx / len * reach, y: dy / len * reach)
        if abs(look.x - ui.look.x) > 0.03 || abs(look.y - ui.look.y) > 0.03 { ui.look = look }
    }
}
