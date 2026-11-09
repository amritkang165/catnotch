import CoreGraphics
import Foundation
import Testing
@testable import CatNotchCore

// MARK: State

@Test func companionSleepsThroughTheNightAndBurstsBeatSleep() {
    #expect(CompanionState.current(hour: 12, bursting: false) == .idle)
    #expect(CompanionState.current(hour: 23, bursting: false) == .sleeping)
    #expect(CompanionState.current(hour: 2, bursting: false) == .sleeping)
    #expect(CompanionState.current(hour: 6, bursting: false) == .idle)
    #expect(CompanionState.current(hour: 2, bursting: true) == .working) // a task done at night still gets a cheer
    #expect(CompanionState.current(hour: 12, bursting: true) == .working)
}

// MARK: Simulation

/// Runs a sim for `seconds` at 60 fps and hands every pose to `body`.
private func run(_ sim: inout CompanionSim, seconds: Double, _ body: (CompanionPose) -> Void = { _ in }) {
    for _ in 0..<Int(seconds * 60) { sim.update(1.0 / 60); body(sim.pose) }
}

@Test func simIsRepeatableFromItsSeed() {
    var a = CompanionSim(seed: 0.42), b = CompanionSim(seed: 0.42), c = CompanionSim(seed: 0.43)
    run(&a, seconds: 10); run(&b, seconds: 10); run(&c, seconds: 10)
    #expect(a.pose == b.pose)
    #expect(a.pose != c.pose)
}

@Test func idleTurnsItsHeadBlinksAndGlances() {
    var sim = CompanionSim(seed: 0.1)
    var yaw = (min: 0.0, max: 0.0), blinked = false, glanced = false
    run(&sim, seconds: 40) { p in
        yaw = (min(yaw.min, p.yaw), max(yaw.max, p.yaw))
        if p.blinkL > 0.9 { blinked = true }
        if abs(p.lookX) > 2 { glanced = true }
    }
    #expect(yaw.min < -0.3 && yaw.max > 0.3) // turns both ways, in 3D
    #expect(blinked)
    #expect(glanced)
}

@Test func workingHopsSpinsEveryThirdHopAndLaughs() {
    var sim = CompanionSim(seed: 0.2, state: .working)
    var highest = 0.0, spun = false, laughed = false, squashed = false
    run(&sim, seconds: 20) { p in
        highest = max(highest, -p.y)
        if abs(p.yaw) > 3 { spun = true } // most of the way round
        if p.laugh > 0.9 { laughed = true }
        if p.sy < 0.9 { squashed = true }
    }
    #expect(highest > 20) // the big hop is 26 body units
    #expect(spun)
    #expect(laughed)
    #expect(squashed)
}

@Test func sleepingBreathesNodsAndNeverBlinks() {
    var sim = CompanionSim(seed: 0.3, state: .sleeping)
    var lowest = 0.0, breathMin = 1.0, breathMax = -1.0, blinked = false
    run(&sim, seconds: 30) { p in
        lowest = min(lowest, p.pitch)
        breathMin = min(breathMin, p.breath); breathMax = max(breathMax, p.breath)
        if p.blinkL > 0 { blinked = true }
    }
    #expect(sim.pose.w[2] > 0.99)
    #expect(lowest < -0.4) // head down (-16°) and then a nod (-13° more)
    #expect(breathMin < -0.9 && breathMax > 0.9)
    #expect(!blinked)
    #expect(sim.pose.y > 2) // sits lower than awake
}

@Test func leavingWorkFinishesTheHopAndSettlesIdle() {
    var sim = CompanionSim(seed: 0.4, state: .working)
    run(&sim, seconds: 3)
    sim.setState(.idle)
    run(&sim, seconds: 3)
    #expect(sim.pose.w[0] > 0.99)
    #expect(abs(sim.pose.sy - 1) < 0.1 && abs(sim.pose.y) < 3) // landed, no hop left over
}

@Test func pointerPullsTheHeadAndEyesTowardsIt() {
    func settled(x: Double) -> CompanionPose {
        var sim = CompanionSim(seed: 0.5)
        sim.setPointer(x: x, y: 0, strength: 1)
        run(&sim, seconds: 3)
        return sim.pose
    }
    let right = settled(x: 1), left = settled(x: -1)
    #expect(right.yaw > 0.15, "yaw \(right.yaw)") // 22° towards it, less the idle wander that is left
    #expect(left.yaw < -0.15, "yaw \(left.yaw)")
    #expect(right.lookX > 1.5, "lookX \(right.lookX)")
    #expect(left.lookX < -1.5, "lookX \(left.lookX)")
}

@Test func clickHopsAndTurnsRightRound() {
    var sim = CompanionSim(seed: 0.6)
    run(&sim, seconds: 1)
    sim.poke()
    var highest = 0.0, yaw = (min: 0.0, max: 0.0)
    run(&sim, seconds: 1.5) { p in
        highest = max(highest, -p.y)
        yaw = (min(yaw.min, p.yaw), max(yaw.max, p.yaw))
    }
    #expect(highest > 20)
    #expect(yaw.max - yaw.min > 5) // about a full turn
}

// MARK: Path and colour

@Test func pathReadsAbsoluteRelativeAndPackedNumbers() {
    #expect(SVGPath.parse("M1 2 L3 4 Z") == [.move(CGPoint(x: 1, y: 2)), .line(CGPoint(x: 3, y: 4)), .close])
    #expect(SVGPath.parse("M0-5L-3-4") == [.move(CGPoint(x: 0, y: -5)), .line(CGPoint(x: -3, y: -4))])
    #expect(SVGPath.parse("M1 1 2 2 3 3") == [.move(CGPoint(x: 1, y: 1)), .line(CGPoint(x: 2, y: 2)), .line(CGPoint(x: 3, y: 3))]) // repeats after a move are lines
    #expect(SVGPath.parse("M10 10 l5 0 v5 h-5 z") == [.move(CGPoint(x: 10, y: 10)), .line(CGPoint(x: 15, y: 10)), .line(CGPoint(x: 15, y: 15)), .line(CGPoint(x: 10, y: 15)), .close])
    #expect(SVGPath.parse("M0 0 Q1 2 3 4") == [.move(.zero), .quad(CGPoint(x: 1, y: 2), CGPoint(x: 3, y: 4))])
    #expect(SVGPath.parse("M0 0 C1 2 3 4 5 6") == [.move(.zero), .cubic(CGPoint(x: 1, y: 2), CGPoint(x: 3, y: 4), CGPoint(x: 5, y: 6))])
    #expect(SVGPath.parse("M.5.25") == [.move(CGPoint(x: 0.5, y: 0.25))]) // a second dot starts a new number
}

@Test func pathReadsArcs() throws {
    func box(_ d: String) throws -> CGRect { try #require(SVGPath.cgPath(d)).boundingBox }
    func close(_ r: CGRect, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Bool {
        abs(r.minX - x) < 0.02 && abs(r.minY - y) < 0.02 && abs(r.width - w) < 0.04 && abs(r.height - h) < 0.04
    }
    #expect(close(try box("M0 0 A5 5 0 0 1 10 0"), 0, -5, 10, 5)) // sweep 1 goes clockwise on screen: over the top
    #expect(close(try box("M0 0 A5 5 0 0 0 10 0"), 0, 0, 10, 5)) // sweep 0 the other way: underneath
    #expect(close(try box("M4 62A7 7 0 1 1 18 62A7 7 0 1 1 4 62Z"), 4, 55, 14, 14)) // two halves make the droid's ear
    #expect(close(try box("M0 0 A1 1 0 0 1 10 0"), 0, -5, 10, 5)) // radii too small to reach are grown until they do
    #expect(close(try box("M0 0 a5 5 0 0 1 10 0"), 0, -5, 10, 5)) // relative
    #expect(SVGPath.parse("M0 0 A5 5 0 0 1 10 0")?.last.map { if case .cubic(_, _, let end) = $0 { end == CGPoint(x: 10, y: 0) } else { false } } == true)
    #expect(SVGPath.parse("M0 0 A5 5 0 0 1 10") == nil) // seven numbers or none
}

@Test func pathRefusesWhatItCannotRead() {
    #expect(SVGPath.parse("M0") == nil) // a point needs two numbers
    #expect(SVGPath.parse("1 2") == nil) // numbers with no command
    #expect(SVGPath.parse("M0 0 Z 1 2") == nil)
}

@Test func shadeMovesLightnessAndMixes() {
    #expect(Shade.adjust(0x808080, lightness: 0.1) == 0x9a9a9a)
    #expect(Shade.adjust(0xffffff, lightness: 0.5) == 0xffffff)
    #expect(Shade.adjust(0x1e1e2e, lightness: -0.1) < 0x1e1e2e) // darker
    #expect(Shade.adjust(0xcba6f7, lightness: 0) == 0xcba6f7) // a round trip loses nothing
    #expect(Shade.mix(0x000000, 0xffffff, 0.5) == 0x808080)
}

@Test func lookTakesItsFaceFromTheFlavour() {
    for flavor in Flavor.allCases {
        let look = CompanionLook(flavor: flavor)
        #expect(look.body == flavor.base)
        #expect(look.ink == flavor.mauve)
        #expect(look.bow == flavor.red)
    }
    #expect(CompanionLook(body: 0, ink: Flavor.mocha.red, bow: 0).ink == Flavor.mocha.red)
}

// MARK: Drawing

/// Renders a pose at 2x into RGBA bytes, `box * 1.5` points square, top left origin like a SwiftUI canvas.
private func render(_ pose: CompanionPose, look: CompanionLook, box: CGFloat = 72) -> (pixels: [UInt8], width: Int) {
    let width = Int(box * CGFloat(CompanionRenderer.overscan) * 2)
    var pixels = [UInt8](repeating: 0, count: width * width * 4)
    pixels.withUnsafeMutableBytes { raw in
        let ctx = CGContext(data: raw.baseAddress, width: width, height: width, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(width))
        ctx.scaleBy(x: 2, y: -2)
        CompanionRenderer.draw(ctx, box: box, pose: pose, look: look)
    }
    return (pixels, width)
}

/// Where pixels of `hex` are (within a rounding), as (count, mean y).
private func find(_ hex: UInt32, in image: (pixels: [UInt8], width: Int)) -> (count: Int, meanY: Double) {
    let r = Int(hex >> 16 & 255), g = Int(hex >> 8 & 255), b = Int(hex & 255)
    var count = 0, sum = 0
    for i in 0..<(image.width * image.width) {
        let p = i * 4
        guard image.pixels[p + 3] == 255 else { continue }
        if abs(Int(image.pixels[p]) - r) < 5, abs(Int(image.pixels[p + 1]) - g) < 5, abs(Int(image.pixels[p + 2]) - b) < 5 { count += 1; sum += i / image.width }
    }
    return (count, count == 0 ? 0 : Double(sum) / Double(count))
}

@Test func catIsDrawnWithFaceAboveBowInTheFlavoursColours() {
    for flavor in Flavor.allCases {
        let look = CompanionLook(flavor: flavor)
        let image = render(CompanionPose(rest: .idle), look: look)
        let opaque = (0..<(image.width * image.width)).filter { image.pixels[$0 * 4 + 3] > 0 }.count
        #expect(opaque > 2000) // a body, not an empty canvas
        let eyes = find(look.ink, in: image), bow = find(look.bow!, in: image)
        #expect(eyes.count > 30, "the eyes are the flavour's Mauve")
        #expect(bow.count > 30, "the bow is the flavour's Red")
        #expect(eyes.meanY < bow.meanY, "the face is above the bow")
    }
}

@Test func spunAroundTheCatShowsNeitherFaceNorBow() {
    var pose = CompanionPose(rest: .idle)
    pose.yaw = Double.pi // back to the viewer
    let look = CompanionLook(flavor: .mocha)
    let image = render(pose, look: look)
    #expect(find(look.ink, in: image).count == 0)
    #expect(find(look.bow!, in: image).count == 0)
}

@Test func closedEyesAreNarrowerThanOpenOnes() {
    let look = CompanionLook(flavor: .mocha)
    let open = find(look.ink, in: render(CompanionPose(rest: .idle), look: look)).count
    var blink = CompanionPose(rest: .idle)
    blink.blinkL = 1; blink.blinkR = 1
    #expect(find(look.ink, in: render(blink, look: look)).count < open / 2)
}

/// The idle cost, measured: one frame of the cat at the tile's size, drawn on a bitmap. It is printed, so a run
/// shows the number; the bound is only a guard against a slow drawing slipping in.
@Test func idleFrameCost() {
    var sim = CompanionSim(seed: 0.7)
    let look = CompanionLook(flavor: .mocha)
    let frames = 300
    let clock = ContinuousClock()
    let elapsed = clock.measure {
        for _ in 0..<frames {
            sim.update(1.0 / 30)
            _ = render(sim.pose, look: look)
        }
    }
    let ms = Double(elapsed.components.attoseconds) / 1e15 / Double(frames) + Double(elapsed.components.seconds) * 1000 / Double(frames)
    print("companion idle frame: \(String(format: "%.3f", ms)) ms (sim + draw + bitmap alloc), \(String(format: "%.1f", ms * 30 / 10))% of a core at 30 fps")
    #expect(ms < 25)
}

// MARK: Characters, switches, ambient video

@Test func theSavedCharacterIsReadBack() {
    #expect(CompanionCharacter(setting: nil) == .ghost) // unset: the Electron default
    #expect(CompanionCharacter(setting: "unicorn") == .ghost)
    #expect(CompanionCharacter(setting: "cat") == .cat) // the orange library cat stays itself
    #expect(CompanionCharacter(setting: "catppuccin") == .catppuccin)
    #expect(CompanionCharacter(setting: "photo") == .photo)
    for character in CompanionCharacter.allCases { #expect(CompanionCharacter(setting: character.rawValue) == character) }
    #expect(CompanionCharacter.allCases.map(\.rawValue) == ["catppuccin", "cat", "claude", "ghost", "blob", "clover", "droid", "alien", "cloud", "photo"]) // the picker's order
}

@Test func everyOutlineIsReadAndFillsItsBox() throws {
    for character in CompanionCharacter.allCases where character != .photo {
        let box = try #require(character.outline, "\(character) has no readable outline").boundingBox
        #expect(box.minX > -1 && box.minY > -1 && box.maxX < 101 && box.maxY < 101, "\(character) leaves the 100 box")
        #expect(box.width > 45 && box.height > 45, "\(character) is too small")
    }
    #expect(CompanionCharacter.photo.outline == nil)
}

@Test func charactersTakeTheirColoursAndAContrastingInk() {
    let ghost = CompanionLook(character: .ghost, flavor: .mocha)
    #expect(ghost.body == 0xf4f2fa && ghost.ink == 0x1e1a33 && ghost.bow == nil) // a light body gets dark ink
    #expect(CompanionLook(character: .alien, flavor: .frappe).body == 0x9be85a)
    #expect(CompanionLook(character: .catppuccin, flavor: .macchiato) == CompanionLook(flavor: .macchiato))
    #expect(CompanionLook(character: .claude, flavor: .mocha).body == 0xd77757)
    #expect(CompanionLook(character: .claude, flavor: .mocha).bow == nil)
    #expect(CompanionLook(character: .clover, flavor: .mocha) == CompanionLook(character: .clover, flavor: .frappe)) // only the cat follows the flavour
    #expect(CompanionLook(body: 0x1e1e2e, ink: 0, bow: nil).ink == 0)
    #expect(CompanionCharacter.autoInk(on: 0x1e1e2e) == 0xf7f5f2) // a dark body gets light ink
    #expect(CompanionCharacter.autoInk(on: 0xffffff) == 0x1e1a33)
}

@Test func companionSettingsStartOffAndKeepTheirKeys() {
    var data = StoreData()
    #expect(data.avatar == .ghost)
    #expect(!data.companionLook && !data.companionSleepOn && !data.companionReact)
    #expect(data.ambientVideo) // on unless switched off
    data.avatar = .photo; data.companionLook = true; data.companionSleepOn = true; data.companionReact = true; data.ambientVideo = false
    #expect(data.settings["avatar"] == .string("photo")) // the Electron keys, so the import carries them
    #expect(data.settings["companionLook"] == .bool(true) && data.settings["companionSleepOn"] == .bool(true) && data.settings["companionReact"] == .bool(true))
    #expect(data.settings["ambientVideo"] == .bool(false))
    #expect(data.avatar == .photo && data.companionLook && data.companionSleepOn && data.companionReact && !data.ambientVideo)
    data.settings["companionLook"] = .string("yes") // the wrong shape reads as off
    #expect(!data.companionLook)
}

@Test func sleepingOnlyHappensWhenSleepAtNightIsOn() {
    #expect(CompanionState.current(hour: 2, bursting: false, sleeps: false) == .idle)
    #expect(CompanionState.current(hour: 2, bursting: false, sleeps: true) == .sleeping)
    #expect(CompanionState.current(hour: 2, bursting: true, sleeps: false) == .working)
}

/// The most the head strays from front-on, in an idle minute and a half, once any change has settled.
private func straying(looksAround: Bool, pointer: Bool = true) -> Double {
    var sim = CompanionSim(seed: 0.3)
    sim.looksAround = looksAround
    if pointer { sim.setPointer(x: 1, y: 0.5, strength: 1) }
    var most = 0.0
    for frame in 0..<(30 * 90) {
        sim.update(1.0 / 30)
        if frame > 90 { most = max(most, abs(sim.pose.yaw), abs(sim.pose.pitch), abs(sim.pose.roll), abs(sim.pose.lookX)) }
    }
    return most
}

@Test func lookingAroundOffKeepsTheHeadAndEyesStill() {
    #expect(straying(looksAround: false) < 0.001) // no wander, no glances, no idle jump, and the pointer is ignored
    #expect(straying(looksAround: true) > 0.2)
}

@Test func aClickStillHopsWithLookingAroundOff() {
    var sim = CompanionSim(seed: 0.3)
    sim.looksAround = false
    for _ in 0..<90 { sim.update(1.0 / 30) }
    sim.poke()
    var highest = 0.0
    for _ in 0..<60 { sim.update(1.0 / 30); highest = max(highest, -sim.pose.y) }
    #expect(highest > 5)
}

@Test func theAmbientVideoTurnsTowardsTheCompanionsColour() {
    // The video's own light is a teal blue (hue 198): blues, lavenders and near whites already suit it.
    #expect(AmbientShift(accent: 0x35b8ff) == AmbientShift(rotate: 0, saturation: 0.35)) // clover blue
    #expect(AmbientShift(accent: 0xcba6f7) == AmbientShift(rotate: 0, saturation: 0.35)) // the cat's mauve
    #expect(AmbientShift(accent: 0xf4f2fa) == AmbientShift(rotate: 0, saturation: 0.35)) // ghost white
    #expect(AmbientShift(accent: nil) == AmbientShift(rotate: 0, saturation: 0.35))
    #expect(AmbientShift(accent: 0x9be85a) == AmbientShift(rotate: -105, saturation: 0.7)) // alien green, hue 92.5
    #expect(AmbientShift(accent: 0x2fcb7a) == AmbientShift(rotate: -49, saturation: 0.7)) // blob green, hue 148.8
    #expect(AmbientShift(accent: 0xff2a2a).rotate == -198) // red, hue 0: turned as far back as the video is from it
}

@Test func everyCharacterHasAnAmbientColour() {
    #expect(CompanionCharacter.photo.accent(flavor: .mocha) == 0xffffff)
    #expect(CompanionCharacter.catppuccin.accent(flavor: .frappe) == Flavor.frappe.mauve)
    #expect(CompanionCharacter.blob.accent(flavor: .mocha) == 0x2fcb7a)
    #expect(CompanionCharacter.cat.accent(flavor: .mocha) == 0xff8c42) // orange, hue 23.5: the video turns round to it
    #expect(AmbientShift(accent: 0xff8c42) == AmbientShift(rotate: -175, saturation: 0.7))
}

@Test func closedNotchAndFullscreenSwitchesAreOnUntilSavedOff() {
    var data = StoreData()
    #expect(data.closedClock && data.closedCompanion && data.hideOnFullscreen)
    data.closedClock = false; data.closedCompanion = false; data.hideOnFullscreen = false
    #expect(data.settings["closedClock"] == .bool(false) && data.settings["hideOnFullscreen"] == .bool(false))
    #expect(!data.closedClock && !data.closedCompanion && !data.hideOnFullscreen)
}

@Test func notchSectionsAreOnUntilSavedOffAndOffPagesLeaveTheDock() {
    var data = StoreData()
    #expect(data.showAvatar && data.showMusic && data.pagesOff == [.claude]) // the Claude page waits for Claude Code to be on
    data.showDesk = false; data.showFiles = false
    #expect(data.pagesOff == [.desk, .files, .claude])
    #expect(NotchPage.shown(calendar: true, off: data.pagesOff) == [.home, .calendar, .reminders])
    data.claudeHooks.enabled = true
    #expect(NotchPage.shown(calendar: true, off: data.pagesOff) == [.home, .calendar, .reminders, .claude])
    data.showClaude = false // its own switch: Claude Code stays on for the prompts
    #expect(NotchPage.shown(calendar: true, off: data.pagesOff) == [.home, .calendar, .reminders])
    #expect(data.claudeHooks.enabled)
}
