import Foundation
import Testing
@testable import CatNotchCore

private func line(_ payload: String, diff: Bool = false) -> String {
    #"{"type":"data","diff":\#(diff),"payload":\#(payload)}"#
}

private let track = #"{"bundleIdentifier":"com.spotify.client","title":"Song","artist":"Band","album":"LP","playing":true,"elapsedTimeMicros":10000000,"durationMicros":200000000,"timestampEpochMicros":1762000000000000}"#

@Test func streamReadsATrack() {
    var s = NowPlayingStream()
    let data = s.feed(line(track))
    #expect(data)
    let n = s.current
    #expect(n?.title == "Song" && n?.artist == "Band" && n?.album == "LP")
    #expect(n?.sourceAppId == "com.spotify.client")
    #expect(n?.isPlaying == true)
    #expect(n?.elapsed == 10 && n?.duration == 200)
}

@Test func diffMergesAndNullRemoves() {
    var s = NowPlayingStream()
    s.feed(line(track))
    s.feed(line(#"{"playing":false}"#, diff: true))
    #expect(s.current?.isPlaying == false)
    #expect(s.current?.title == "Song") // kept from the full line
    s.feed(line(#"{"artist":null}"#, diff: true))
    #expect(s.current?.artist == "")
    s.feed(line(#"{"title":null}"#, diff: true))
    #expect(s.current == nil) // no title, nothing playing
}

@Test func fullLineReplacesEverything() {
    var s = NowPlayingStream()
    s.feed(line(track))
    s.feed(line(#"{"bundleIdentifier":"com.apple.Safari","title":"Tab"}"#))
    #expect(s.current?.artist == "")
    #expect(s.current?.sourceAppId == "com.apple.Safari")
}

@Test func junkAndOtherLinesAreIgnored() {
    var s = NowPlayingStream()
    let junk = s.feed("not json"), other = s.feed(#"{"type":"error"}"#)
    #expect(!junk && !other)
    #expect(s.current == nil)
}

@Test func artworkDecodesFromBase64() {
    var s = NowPlayingStream()
    s.feed(line(#"{"bundleIdentifier":"a","title":"t","artworkData":"AQID"}"#))
    #expect(s.current?.artwork == Data([1, 2, 3]))
}

@Test func resetForgetsTheTrack() {
    var s = NowPlayingStream()
    s.feed(line(track))
    s.reset()
    #expect(s.current == nil)
    s.feed(line(#"{"playing":true}"#, diff: true))
    #expect(s.current == nil) // nothing left to merge into
}

@Test func positionMovesOnWhilePlayingOnly() {
    var s = NowPlayingStream()
    s.feed(line(track))
    let at = Date(timeIntervalSince1970: 1_762_000_000)
    #expect(s.current?.position(at: at.addingTimeInterval(5)) == 15)
    #expect(s.current?.position(at: at.addingTimeInterval(-5)) == 10) // a clock behind the timestamp never rewinds
    #expect(s.current?.position(at: at.addingTimeInterval(500)) == 200) // stops at the end
    s.feed(line(#"{"playing":false}"#, diff: true))
    #expect(s.current?.position(at: at.addingTimeInterval(5)) == 10)
}

@Test func transportKeysAreMediaRemotes() {
    #expect([Transport.play, .pause, .playPause, .next, .previous].map(\.rawValue) == [0, 1, 2, 4, 5])
}

@Test func dominantColorPrefersColourOverGrey() {
    // Two red pixels and six grey: the red should win.
    let red: [UInt8] = [220, 20, 20, 255], grey: [UInt8] = [128, 128, 128, 255]
    let c = DominantColor.of(rgba: Array([red, red, grey, grey, grey, grey, grey, grey].joined()))
    #expect(c != nil && c!.red > c!.green + 0.3)
}

@Test func dominantColorOfGreyAndEmpty() {
    let c = DominantColor.of(rgba: [100, 100, 100, 255])
    #expect(c != nil && abs(c!.red - 100.0 / 255) < 0.001)
    #expect(DominantColor.of(rgba: []) == nil)
}

@Test func trackTimeText() {
    #expect(TrackTime.text(0) == "00:00")
    #expect(TrackTime.text(59.9) == "00:59") // rounds down
    #expect(TrackTime.text(125) == "02:05")
    #expect(TrackTime.text(3600) == "1:00:00")
    #expect(TrackTime.text(3725) == "1:02:05")
    #expect(TrackTime.text(-4) == "00:00")
}

@Test func fractionIsHowFarThrough() {
    var s = NowPlayingStream()
    s.feed(line(track)) // 10 s of 200 s at the timestamp
    let at = Date(timeIntervalSince1970: 1_762_000_000)
    #expect(s.current?.fraction(at: at) == 0.05)
    #expect(s.current?.fraction(at: at.addingTimeInterval(90)) == 0.5)
    s.feed(line(#"{"durationMicros":null}"#, diff: true))
    #expect(s.current?.fraction(at: at) == 0) // unknown length
}
