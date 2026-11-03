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
    #expect(!hover.isOpen(cursor: CGPoint(x: 800, y: 450), in: screen, wasOpen: true))
    #expect(!hover.isOpen(cursor: CGPoint(x: 500, y: 300), in: screen, wasOpen: true))
}
