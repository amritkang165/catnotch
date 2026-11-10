import CoreGraphics
import Foundation

/// Where the Notch sits and when the pointer counts as hovering it. Pure geometry, screen coordinates (origin bottom left).
public struct NotchHover: Equatable, Sendable {
    public var closed: CGSize
    public var open: CGSize
    /// Height of the dock that hangs under the open Notch. The panel and the open hit area include it.
    public var chrome: CGFloat
    /// Room kept either side of the open Notch for the apps tray (and so it stays centred).
    public var side: CGFloat

    /// The open size before a page shrank the Notch. The pointer that clicked the dock is under the old dock, outside the
    /// smaller Notch, and must not close it: that area still counts until the pointer reaches the new Notch (see `settle`).
    public var shrunkFrom: CGSize?

    public init(closed: CGSize, open: CGSize, chrome: CGFloat = 0, side: CGFloat = 0) {
        self.side = side
        self.closed = closed
        self.open = open
        self.chrome = chrome
    }

    /// The Notch at a given size, centred and pinned to the top of the screen.
    private func rect(_ size: CGSize, in screen: CGRect) -> CGRect {
        CGRect(x: screen.midX - size.width / 2, y: screen.maxY - size.height, width: size.width, height: size.height)
    }

    public func size(isOpen: Bool) -> CGSize { isOpen ? open : closed }

    private var openWithChrome: CGSize { CGSize(width: open.width + 2 * side, height: open.height + chrome) }

    /// The one panel: the open size plus the dock under it, pinned to the top centre of the screen.
    public func panelFrame(in screen: CGRect) -> CGRect { rect(openWithChrome, in: screen) }

    /// Ends the grace of `shrunkFrom` once the pointer is inside the new, smaller Notch.
    public mutating func settle(cursor: CGPoint, in screen: CGRect) {
        if shrunkFrom != nil, Self.contains(rect(openWithChrome, in: screen), cursor) { shrunkFrom = nil }
    }

    // CGRect.contains drops the top edge, but a pointer pushed to the top of the display sits exactly on it.
    private static func contains(_ r: CGRect, _ p: CGPoint) -> Bool { p.x >= r.minX && p.x <= r.maxX && p.y >= r.minY && p.y <= r.maxY }

    /// How far past the closed Notch the pointer still counts as arriving. None: the Electron Notch opened on its exact shape,
    /// and any slop opened it as the pointer passed by on its way to the menu bar.
    public static let approach: CGFloat = 0
    /// The same for a file being dragged in: a longer reach, because the drag is aimed at the Notch and the Notch is small.
    public static let dragReach: CGFloat = 48

    /// How far past the open Notch (and its dock and tray) the pointer may drift before it counts as leaving, so a pointer going
    /// for the menu bar beside it, or overshooting the dock, does not close it (Electron's `LEAVE_MARGIN`).
    public static let leaveReach: CGFloat = 16
    /// The same, but below the Notch: the pointer drops that way toward the menu bar and the windows, so it gets more room.
    public static let leaveReachBelow: CGFloat = 48
    /// The same, but beside the Notch: tighter than `leaveReach`, so the pointer does not linger far out to the sides.
    public static let leaveReachSide: CGFloat = 8

    /// Open while the pointer is inside the Notch's current shape: the open one if already open (widened by `leaveReach`),
    /// else the closed one widened by `approach` (`dragReach` while a file is dragged).
    public func isOpen(cursor: CGPoint, in screen: CGRect, wasOpen: Bool, dragging: Bool = false) -> Bool {
        if wasOpen { return distance(from: cursor, in: screen) <= Self.leaveReach }
        let slop = dragging ? Self.dragReach : Self.approach
        return Self.contains(rect(closed, in: screen).insetBy(dx: -slop, dy: -slop), cursor)
    }

    /// How far the pointer is from the open Notch, its dock and tray: 0 on them. Straight-line, as Electron's `distance`,
    /// so a corner is not further reached than a side. Just after a page shrank the Notch, the pointer may still be where
    /// its dock was, and that counts as on it.
    public func distance(from cursor: CGPoint, in screen: CGRect) -> CGFloat {
        var rects = [rect(openWithChrome, in: screen)]
        if let from = shrunkFrom { rects.append(rect(CGSize(width: from.width + 2 * side, height: from.height + chrome), in: screen)) }
        // Below counts at `leaveReach / leaveReachBelow` of its length, so the one `leaveReach` test gives more room downward.
        let below = Self.leaveReach / Self.leaveReachBelow
        let side = Self.leaveReach / Self.leaveReachSide // beside counts for more, so it reaches less far
        return rects.map { r in hypot(max(r.minX - cursor.x, 0, cursor.x - r.maxX) * side, max((r.minY - cursor.y) * below, 0, cursor.y - r.maxY)) }.min()!
    }

    /// Whether the pointer is on the Notch itself (not just in the margin that keeps it open). Only there does the panel take
    /// the mouse; in the margin a click falls through to the app below, as the Electron strip does.
    public func hits(cursor: CGPoint, in screen: CGRect) -> Bool { distance(from: cursor, in: screen) == 0 }
}

/// When an open Notch lets go, judged by intent rather than by its edge, as Electron does: within `NotchHover.leaveReach` it
/// stays; past it, it closes once the pointer is heading further away, or has stopped there for `still` seconds; heading
/// back gives a fresh wait. A page resizing moves the dock from under a still pointer, which is not leaving, so for
/// `settle` seconds after a resize the distance is not trusted.
public struct LeaveIntent: Equatable, Sendable {
    public enum Verdict: Equatable, Sendable {
        /// Near, or settling: stay, and drop any wait.
        case stay
        /// Past the reach and going: close now.
        case close
        /// Past the reach: close if nothing moves for `still` seconds (start, or restart, that wait).
        case wait
        /// Past the reach and the wait is already running.
        case keep
    }

    public static let still: Double = 0.7
    public static let settle: Double = 0.9

    private var last: CGFloat = 0
    private var waiting = false

    public init() {}

    public mutating func step(distance d: CGFloat, settling: Bool) -> Verdict {
        defer { last = d }
        if d <= NotchHover.leaveReach || settling { waiting = false; return .stay }
        if !waiting { waiting = true; return .wait }
        if d > last { return .close }
        return d < last ? .wait : .keep
    }

    public mutating func reset() { last = 0; waiting = false }
}
