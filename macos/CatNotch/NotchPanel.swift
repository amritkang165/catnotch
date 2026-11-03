import AppKit
import SwiftUI
import CatNotchCore

// Prototype constant: the open size. Real content sizes come with the features.
private let openSize = CGSize(width: 520, height: 200)

/// Hosting view with a tracking area, so the pointer leaving the panel is seen while it takes mouse events.
private final class TrackedHostingView<Content: View>: NSHostingView<Content> {
    var onPointer: () -> Void = {}
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) } // only ours: the hosting view keeps its own for SwiftUI hover
        let new = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(new)
        area = new
    }
    override func mouseMoved(with event: NSEvent) { onPointer() }
    override func mouseEntered(with event: NSEvent) { onPointer() }
    override func mouseExited(with event: NSEvent) { onPointer() }
}

/// A panel AppKit may not nudge below the menu bar: the drawn Notch must sit where the hit rect says.
private final class TopPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// One transparent panel at the top centre of one display. It ignores the mouse (clicks fall through) except while open.
/// Pointer input is event driven: NotchController owns the monitors and calls `update()`; the tracking area does too.
@MainActor
final class NotchPanel {
    let displayID: UInt32
    private let model = NotchModel(open: openSize)
    private let panel: TopPanel

    init(displayID: UInt32, data: StoreData) {
        self.displayID = displayID
        panel = TopPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = true

        let view = TrackedHostingView(rootView: NotchView(model: model))
        view.onPointer = { [weak self] in self?.update() }
        panel.contentView = view
        apply(data)
        reposition()
    }

    private var screen: NSScreen? {
        NSScreen.screens.first { $0.displayID == displayID }
    }

    /// Sizes the closed Notch from the hardware notch (or the default) and pins the panel to the display.
    func reposition() {
        guard let screen else { return }
        let bar = NotchSize.closedWithWings(
            screenWidth: screen.frame.width, safeTop: screen.safeAreaInsets.top,
            leftWidth: screen.auxiliaryTopLeftArea?.width, rightWidth: screen.auxiliaryTopRightArea?.width)
        model.hover.closed = bar.size
        model.cutout = bar.cutout
        panel.setFrame(model.hover.panelFrame(in: screen.frame), display: true)
        update()
    }

    /// Takes the saved look.
    func apply(_ data: StoreData) {
        model.style = data.notchStyle
        model.flavor = data.notchFlavor
    }

    func update() {
        guard let screen else { return }
        let open = model.hover.isOpen(cursor: NSEvent.mouseLocation, in: screen.frame, wasOpen: model.isOpen)
        guard open != model.isOpen else { return }
        model.isOpen = open
        panel.ignoresMouseEvents = !open
    }

    /// Hidden over a fullscreen app. Shown again it starts closed.
    func setHidden(_ hidden: Bool) {
        if hidden {
            panel.orderOut(nil)
        } else if !panel.isVisible {
            model.isOpen = false
            panel.ignoresMouseEvents = true
            panel.orderFrontRegardless()
            update()
        }
    }
}

extension NSScreen {
    var displayID: UInt32? { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }
}
