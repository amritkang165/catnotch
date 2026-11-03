import CoreGraphics

/// Where the Notch sits and when the pointer counts as hovering it. Pure geometry, screen coordinates (origin bottom left).
public struct NotchHover: Equatable, Sendable {
    public var closed: CGSize
    public var open: CGSize

    public init(closed: CGSize, open: CGSize) {
        self.closed = closed
        self.open = open
    }

    /// The Notch at a given size, centred and pinned to the top of the screen.
    private func rect(_ size: CGSize, in screen: CGRect) -> CGRect {
        CGRect(x: screen.midX - size.width / 2, y: screen.maxY - size.height, width: size.width, height: size.height)
    }

    public func size(isOpen: Bool) -> CGSize { isOpen ? open : closed }

    /// The one panel: the open size, pinned to the top centre of the screen.
    public func panelFrame(in screen: CGRect) -> CGRect { rect(open, in: screen) }

    /// Open while the pointer is inside the Notch's current shape: the open one if already open, else the closed one.
    public func isOpen(cursor: CGPoint, in screen: CGRect, wasOpen: Bool) -> Bool {
        let rect = rect(size(isOpen: wasOpen), in: screen)
        // CGRect.contains drops the top edge, but a pointer pushed to the top of the display sits exactly on it.
        return cursor.x >= rect.minX && cursor.x <= rect.maxX && cursor.y >= rect.minY && cursor.y <= rect.maxY
    }
}
