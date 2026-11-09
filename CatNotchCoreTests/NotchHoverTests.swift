import Testing
import CoreGraphics
@testable import CatNotchCore

private let screen = CGRect(x: 0, y: 0, width: 1000, height: 600)
private let hover = NotchHover(closed: CGSize(width: 200, height: 32), open: CGSize(width: 520, height: 200))

@Test func panelIsTopCentreAtOpenSize() {
    #expect(hover.panelFrame(in: screen) == CGRect(x: 240, y: 400, width: 520, height: 200))
}

@Test func hoveringClosedNotchOpensIt() {
    #expect(hover.isOpen(cursor: CGPoint(x: 500, y: 590), in: screen, wasOpen: false))
}

@Test func topEdgeOfScreenCountsAsInside() {
    #expect(hover.isOpen(cursor: CGPoint(x: 500, y: 600), in: screen, wasOpen: false))
}

@Test func besideClosedNotchStaysClosed() {
    #expect(!hover.isOpen(cursor: CGPoint(x: 700, y: 590), in: screen, wasOpen: false))
    #expect(!hover.isOpen(cursor: CGPoint(x: 500, y: 500), in: screen, wasOpen: false))
}

@Test func openNotchStaysOpenInsideItsLargerRect() {
    #expect(hover.isOpen(cursor: CGPoint(x: 700, y: 450), in: screen, wasOpen: true))
}

@Test func leavingOpenNotchClosesIt() {
    #expect(!hover.isOpen(cursor: CGPoint(x: 820, y: 450), in: screen, wasOpen: true))
    #expect(!hover.isOpen(cursor: CGPoint(x: 500, y: 300), in: screen, wasOpen: true))
}

@Test func dockUnderTheOpenNotchCountsAsInside() {
    let docked = NotchHover(closed: hover.closed, open: hover.open, chrome: 36)
    #expect(docked.panelFrame(in: screen) == CGRect(x: 240, y: 364, width: 520, height: 236))
    #expect(docked.isOpen(cursor: CGPoint(x: 500, y: 380), in: screen, wasOpen: true))
    #expect(!docked.isOpen(cursor: CGPoint(x: 500, y: 380), in: screen, wasOpen: false))
}

@Test func appsTrayBesideTheOpenNotchCountsAsInside() {
    let docked = NotchHover(closed: hover.closed, open: hover.open, side: 48)
    #expect(docked.panelFrame(in: screen) == CGRect(x: 192, y: 400, width: 616, height: 200))
    #expect(docked.isOpen(cursor: CGPoint(x: 780, y: 550), in: screen, wasOpen: true))
}

@Test func pointerNearTheClosedNotchOpensIt() {
    // closed spans x 400...600, y 568...600: a few points off its side or underside still counts, further does not
    #expect(hover.isOpen(cursor: CGPoint(x: 395, y: 590), in: screen, wasOpen: false))
    #expect(hover.isOpen(cursor: CGPoint(x: 500, y: 562), in: screen, wasOpen: false))
    #expect(!hover.isOpen(cursor: CGPoint(x: 380, y: 590), in: screen, wasOpen: false))
    #expect(!hover.isOpen(cursor: CGPoint(x: 500, y: 540), in: screen, wasOpen: false))
}

@Test func draggedFileOpensItFromFurtherOff() {
    #expect(hover.isOpen(cursor: CGPoint(x: 380, y: 590), in: screen, wasOpen: false, dragging: true))
    #expect(hover.isOpen(cursor: CGPoint(x: 500, y: 540), in: screen, wasOpen: false, dragging: true))
    #expect(!hover.isOpen(cursor: CGPoint(x: 300, y: 590), in: screen, wasOpen: false, dragging: true))
    #expect(!hover.isOpen(cursor: CGPoint(x: 500, y: 500), in: screen, wasOpen: false, dragging: true))
}

@Test func openNotchGetsNoExtraReach() {
    // a drag adds nothing once open: the same leave margin as without one
    let past = CGPoint(x: 760 + NotchHover.leaveReachSide + 5, y: 450)
    #expect(!hover.isOpen(cursor: past, in: screen, wasOpen: true, dragging: true))
}

@Test func openNotchStaysOpenWithinTheLeaveMargin() {
    // the open rect ends at x 760; a pointer a little past it (heading for the menu bar) does not close it
    #expect(hover.isOpen(cursor: CGPoint(x: 760 + NotchHover.leaveReachSide - 2, y: 450), in: screen, wasOpen: true))
    #expect(!hover.isOpen(cursor: CGPoint(x: 760 + NotchHover.leaveReachSide + 5, y: 450), in: screen, wasOpen: true))
}

@Test func pointerOnTheOldDockStaysOpenAfterThePageShrinks() {
    // the tall page's dock sat at y 340...364; the short page's Notch and dock end at y 364
    var h = NotchHover(closed: hover.closed, open: CGSize(width: 520, height: 260), chrome: 36)
    let onOldDock = CGPoint(x: 500, y: 315) // more than the leave margin below the short page's Notch and dock
    #expect(h.isOpen(cursor: onOldDock, in: screen, wasOpen: true))
    h.shrunkFrom = h.open
    h.open = CGSize(width: 520, height: 200)
    #expect(h.isOpen(cursor: onOldDock, in: screen, wasOpen: true))
    h.settle(cursor: onOldDock, in: screen)
    #expect(h.shrunkFrom != nil) // still below the new Notch
    h.settle(cursor: CGPoint(x: 500, y: 450), in: screen)
    #expect(h.shrunkFrom == nil) // reached it: the new size rules from here
    #expect(!h.isOpen(cursor: onOldDock, in: screen, wasOpen: true))
}

// MARK: leaving by intent (Electron's away timer)

@Test func distanceIsStraightLineToTheOpenNotch() {
    #expect(hover.distance(from: CGPoint(x: 500, y: 450), in: screen) == 0)
    #expect(hover.distance(from: CGPoint(x: 760 + 30, y: 450), in: screen) == 60) // beside counts double
    // a corner is further than the same step along a side: 20 across (40 once scaled) and 120 down (40 once scaled) is 56 away
    let corner = hover.distance(from: CGPoint(x: 760 + 20, y: 400 - 120), in: screen)
    #expect(abs(corner - 40 * 2.0.squareRoot()) < 0.001)
}

@Test func theNotchLetsGoLaterBelowThanBesides() {
    // the open rect spans x 240...760, bottom at y 400
    #expect(hover.isOpen(cursor: CGPoint(x: 500, y: 400 - NotchHover.leaveReachBelow + 2), in: screen, wasOpen: true))
    #expect(!hover.isOpen(cursor: CGPoint(x: 500, y: 400 - NotchHover.leaveReachBelow - 5), in: screen, wasOpen: true))
}

@Test func theMarginLetsClicksThrough() {
    // on the Notch the panel takes the mouse; in the leave margin (still open) it does not
    #expect(hover.hits(cursor: CGPoint(x: 500, y: 450), in: screen))
    let margin = CGPoint(x: 760 + 4, y: 450)
    #expect(hover.isOpen(cursor: margin, in: screen, wasOpen: true))
    #expect(!hover.hits(cursor: margin, in: screen))
}

@Test func theOpenReachIsSixteen() {
    #expect(NotchHover.leaveReach == 16)
}

@Test func nearTheNotchItStaysAndPastItWaitsThenClosesWhenHeadingAway() {
    var intent = LeaveIntent()
    #expect(intent.step(distance: 10, settling: false) == .stay)
    #expect(intent.step(distance: 60, settling: false) == .wait) // just crossed: a beat to see where it goes
    #expect(intent.step(distance: 60, settling: false) == .keep) // still: the wait runs on
    #expect(intent.step(distance: 90, settling: false) == .close) // further out: going
}

@Test func headingBackGivesAFreshWaitAndComingNearDropsIt() {
    var intent = LeaveIntent()
    _ = intent.step(distance: 80, settling: false)
    #expect(intent.step(distance: 60, settling: false) == .wait)
    #expect(intent.step(distance: 10, settling: false) == .stay)
    #expect(intent.step(distance: 70, settling: false) == .wait) // out again: starts over, not closed at once
}

@Test func aPageResizingUnderAStillPointerIsNotLeaving() {
    var intent = LeaveIntent()
    #expect(intent.step(distance: 120, settling: true) == .stay)
    #expect(intent.step(distance: 130, settling: true) == .stay)
    #expect(intent.step(distance: 130, settling: false) == .wait)
}
