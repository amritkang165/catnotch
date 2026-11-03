import Testing
import CoreGraphics
@testable import CatNotchCore

@Test func notchedMacUsesHardwareSize() {
    // 1512pt wide screen, 32pt safe area, 660pt either side of the notch.
    let size = NotchSize.closed(screenWidth: 1512, safeTop: 32, leftWidth: 660, rightWidth: 660)
    #expect(size == CGSize(width: 192, height: 32))
}

@Test func macWithoutNotchUsesDefault() {
    #expect(NotchSize.closed(screenWidth: 1920, safeTop: 0, leftWidth: nil, rightWidth: nil) == NotchSize.fallback)
}

@Test func safeAreaWithoutSidesUsesDefault() {
    #expect(NotchSize.closed(screenWidth: 1920, safeTop: 32, leftWidth: nil, rightWidth: nil) == NotchSize.fallback)
}

@Test func notchedClosedGrowsWingsAroundTheCutout() {
    let bar = NotchSize.closedWithWings(screenWidth: 1512, safeTop: 32, leftWidth: 660, rightWidth: 660)
    #expect(bar.cutout == 192)
    #expect(bar.size == CGSize(width: 192 + 2 * NotchSize.wing, height: 32))
}

@Test func closedWithoutCutoutIsTheDefaultSize() {
    let bar = NotchSize.closedWithWings(screenWidth: 1920, safeTop: 0, leftWidth: nil, rightWidth: nil)
    #expect(bar.cutout == 0)
    #expect(bar.size == NotchSize.fallback)
}
