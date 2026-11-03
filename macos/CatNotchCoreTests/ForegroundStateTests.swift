import Testing
import CoreGraphics
@testable import CatNotchCore

private let main = DisplayBounds(id: 1, bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080))
private let side = DisplayBounds(id: 2, bounds: CGRect(x: 1920, y: 0, width: 1920, height: 1080))

private func state(_ windows: [WindowInfo], pid: Int32 = 10, bundle: String = "com.example.app") -> ForegroundState {
    ForegroundState.detect(pid: pid, bundle: bundle, windows: windows, displays: [main, side], mainDisplay: 1)
}

@Test func windowCoveringDisplayIsFullscreen() {
    let s = state([WindowInfo(pid: 10, layer: 0, bounds: main.bounds)])
    #expect(s.fullscreen && s.display == 1)
}

@Test func fullscreenOnSecondDisplayIsReportedThere() {
    let s = state([WindowInfo(pid: 10, layer: 0, bounds: side.bounds)])
    #expect(s.fullscreen && s.display == 2)
}

@Test func maximisedWindowBelowMenuBarIsNotFullscreen() {
    let s = state([WindowInfo(pid: 10, layer: 0, bounds: CGRect(x: 0, y: 25, width: 1920, height: 1055))])
    #expect(!s.fullscreen)
}

@Test func smallWindowIsNotFullscreenAndPicksDisplayByOverlap() {
    let s = state([WindowInfo(pid: 10, layer: 0, bounds: CGRect(x: 2000, y: 100, width: 800, height: 600))])
    #expect(!s.fullscreen && s.display == 2)
}

@Test func otherAppsAndNonZeroLayersAreIgnored() {
    #expect(!state([WindowInfo(pid: 99, layer: 0, bounds: main.bounds)]).fullscreen)
    #expect(!state([WindowInfo(pid: 10, layer: 25, bounds: main.bounds)]).fullscreen)
}

@Test func noWindowsFallsBackToMainDisplay() {
    let s = state([])
    #expect(!s.fullscreen && s.display == 1)
}

@Test func hidesOnlyTheFullscreenDisplay() {
    let s = state([WindowInfo(pid: 10, layer: 0, bounds: side.bounds)])
    #expect(s.hides(display: 2))
    #expect(!s.hides(display: 1))
}

@Test func windowedAppHidesNothing() {
    #expect(!state([]).hides(display: 1))
}

// Ported from main/fullscreen.test.ts
@Test(arguments: ["com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable"])
func terminalsCountAnyCase(bundle: String) {
    #expect(state([], bundle: bundle).isTerminalInFront(for: .cli))
}

@Test(arguments: ["com.google.Chrome", "com.apple.Safari", "com.microsoft.VSCode", ""])
func nonTerminals(bundle: String) {
    #expect(!state([], bundle: bundle).isTerminalInFront(for: .cli))
}

@Test func terminalAppliesToCliAndUnknownNeverVscode() {
    let s = state([], bundle: "com.apple.Terminal")
    #expect(s.isTerminalInFront(for: .cli))
    #expect(s.isTerminalInFront(for: .unknown))
    #expect(!s.isTerminalInFront(for: .vscode))
}
