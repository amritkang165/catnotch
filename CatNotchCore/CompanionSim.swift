import Foundation

/// What the companion is doing: the three states of the `bot-avatars` engine the Electron app uses.
public enum CompanionState: Int, CaseIterable, Sendable {
    case idle, working, sleeping

    /// Busy for a moment after something happened (`bursting`), asleep through the night (23:00 to 06:00), else idle.
    /// With Sleep at night off (`sleeps` false) it never sleeps.
    public static func current(hour: Int, bursting: Bool, sleeps: Bool = true) -> CompanionState {
        bursting ? .working : sleeps && (hour >= 23 || hour < 6) ? .sleeping : .idle
    }
}

/// One frame of the companion's body, in the engine's units: angles in radians, `x`/`y` in the 100 by 100 body box.
public struct CompanionPose: Equatable, Sendable {
    /// Yaw above zero turns the face to the viewer's right, pitch above zero looks up.
    public var yaw = 0.0, pitch = 0.0, roll = 0.0
    public var x = 0.0, y = 0.0, sx = 1.0, sy = 1.0
    /// How far each lid is down, 0 open to 1 shut.
    public var blinkL = 0.0, blinkR = 0.0
    public var lookX = 0.0, lookY = 0.0
    /// The breathing cycle, -1 to 1.
    public var breath = 0.0
    /// Working only: how far the eyes have closed into a laugh, 0 to 1.
    public var laugh = 0.0
    /// Blend weights of the states (idle, working, sleeping); they sum to 1.
    public var w: [Double] = [1, 0, 0]

    public init() {}

    /// The still pose of a state, for the first paint.
    public init(rest state: CompanionState) {
        let b = Self.baseline[state.rawValue]
        pitch = b.pitch; roll = b.roll; y = b.y; lookX = b.lookX; lookY = b.lookY
        w = CompanionState.allCases.map { $0 == state ? 1 : 0 }
    }

    fileprivate static let baseline: [(pitch: Double, roll: Double, y: Double, lookX: Double, lookY: Double)] = [
        (0, 0, 0, 0, 0),
        (5 * deg, 0, 0, 0, 0),
        (-16 * deg, 6 * deg, 3, 0, 1),
    ]
}

private let deg = Double.pi / 180
private let tau = Double.pi * 2

/// The engine's seeded random numbers (mulberry32), so a companion's day is repeatable in a test.
private struct Rng {
    var s: UInt32

    init(seed: Double) {
        let v = UInt32(truncatingIfNeeded: UInt64(max(0, seed) * 1e6) &+ 1) &* 2654435761
        s = v == 0 ? 1 : v
    }

    mutating func next() -> Double {
        s &+= 1831565813
        var z = s
        z = (z ^ (z >> 15)) &* (z | 1)
        z ^= z &+ ((z ^ (z >> 7)) &* (z | 61))
        return Double(z ^ (z >> 14)) / 4294967296
    }
}

/// An exponential approach: `a` moves towards `b` at `rate` per second.
private func approach(_ a: Double, _ b: Double, _ rate: Double, _ dt: Double) -> Double { a + (b - a) * (1 - exp(-rate * dt)) }
private func easeInOut(_ t: Double) -> Double { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
private func smooth(_ t: Double) -> Double { 0.5 - 0.5 * cos(Double.pi * t) }
private func clamp01(_ t: Double) -> Double { min(1, max(0, t)) }

/// A channel that picks a new target now and then and moves to it. The head channels are a lightly damped spring,
/// so a turn starts and ends softly; the eyes dart with an exponential approach.
private struct Wander {
    var amp: Double, holdMin: Double, holdMax: Double, rate: Double
    let spring: Bool
    var value = 0.0, vel = 0.0, target = 0.0, next = 0.0

    init(_ amp: Double, _ holdMin: Double, _ holdMax: Double, _ rate: Double, spring: Bool = false) {
        (self.amp, self.holdMin, self.holdMax, self.rate, self.spring) = (amp, holdMin, holdMax, rate, spring)
    }

    mutating func update(_ t: Double, _ dt: Double, _ rng: inout Rng) {
        if t >= next {
            target = (rng.next() * 2 - 1) * amp
            next = t + holdMin + rng.next() * (holdMax - holdMin)
        }
        if spring {
            let a = rate * 1.6, damping = 0.9
            vel += (a * a * (target - value) - 2 * damping * a * vel) * dt
            value += vel * dt
        } else {
            value = approach(value, target, rate, dt)
        }
    }

    /// Aim at a value and stay there; the caller picks the next one.
    mutating func aim(_ v: Double) { target = v; next = .infinity }

    mutating func set(_ amp: Double, _ holdMin: Double, _ holdMax: Double, _ rate: Double) {
        (self.amp, self.holdMin, self.holdMax, self.rate) = (amp, holdMin, holdMax, rate)
        next = 0
    }
}

/// A one-shot that runs for `duration` seconds.
private struct Event {
    var duration: Double
    var p = -1.0
    var active: Bool { p >= 0 }
    mutating func fire() { p = 0 }
    mutating func update(_ dt: Double) {
        guard active else { return }
        p += dt / duration
        if p >= 1 { p = -1 }
    }
}

/// The jump's numbers, the `bot-avatars` defaults (one `pulse` landing, one full turn).
private enum Jump {
    static let height = 26.0, time = 0.68, stretch = 1.0, squash = 1.15, squashTime = 0.37, groundTime = 0.11
    static let riseTime = 0.33, clickSquashTime = 0.24, spin = 1.0, lean = 6.0, every = 8.0, pulse = 2.0 / 7
    /// The crouch before take-off.
    static func windup(poked: Bool) -> Double { poked ? clickSquashTime : 0.2 * time }
    /// The whole jump, crouch to recovered.
    static func duration(poked: Bool) -> Double { windup(poked: poked) + time + pulse * (poked ? clickSquashTime : squashTime) + groundTime + riseTime + 0.05 }
    /// The squash of a landing, 0 to 1 and back.
    static func landing(_ t: Double) -> Double {
        guard t > 0, t < 1 else { return 0 }
        let i = 7 * t, s = i * i * exp(2 - i) / 4, a = t > 0.85 ? 1 - (t - 0.85) / 0.15 : 1
        return s * a * a * (3 - 2 * a)
    }
    /// Rising out of the squash: 1 at the bottom, 0 at the top.
    static func rise(_ t: Double) -> Double {
        guard t > 0 else { return 1 }
        guard t < 1 else { return 0 }
        let s = 4.2 * t
        return (1 + s) * exp(-s) - t * t * t * 0.078
    }
    static func ground(_ t: Double) -> Double { 1 + 0.25 * landing(t) }
    /// A peak at 0 and at 1.
    static func hit(_ t: Double) -> Double { exp(-pow(min(abs(t), abs(t - 1)) / 0.11, 2)) }
}

private let turnYaw = 35 * deg, turnPitch = 14 * deg, turnRoll = 3.2 * deg
private let hopTime = 0.68

/// The companion's body: turns its head, blinks, glances, hops when busy, breathes and nods when asleep.
/// A port of `BotAvatarSim` from `bot-avatars` (MIT), the engine behind the Electron companion, minus the whirl and
/// the tunable jump. It has no clock: `update` is given the seconds that passed, so a test can run a day in a blink.
public struct CompanionSim {
    public private(set) var pose = CompanionPose()
    public private(set) var state = CompanionState.idle
    /// The Look around switch. Off, the head and eyes keep still: no wander, glances or idle jump, and the pointer is
    /// ignored. A click still hops, and working and sleeping still move the body.
    public var looksAround = true

    private var rng: Rng
    private var t = 0.0
    private var wFrom: [Double] = [1, 0, 0]
    private var tr = 1.0, trDuration = 1.2
    private var yawW = Wander(36 * deg, 1.1, 2.6, 3, spring: true)
    private var pitchW = Wander(10 * deg, 1.1, 2.6, 2.6, spring: true)
    private var rollW = Wander(5 * deg, 1.6, 3.2, 2, spring: true)
    private var lookXW = Wander(3.6, 0.5, 2, 14)
    private var lookYW = Wander(2.4, 0.5, 2, 14)
    private var blink = Event(duration: 0.17), blinkAgain = false, blinkAt = 0.0
    private var dart = Event(duration: 0.12), dartAt = 0.0, dartX = 0.0, dartY = 0.0
    private var flip = Event(duration: Jump.duration(poked: false)), flipPoked = false, flipAt = 0.0, flipSide = 1.0
    private var nod = Event(duration: 1.7), nodAt = 0.0
    private var hopPhase = 0.0, hopCount = 0, hopGain = 0.0
    private var laughEv = Event(duration: 0.8), laughAt = 0.0
    private var prevYaw = 0.0, jelly = 0.0, jellyV = 0.0, gazeLead = 0.0
    private var gazeDir = (0.0, 0.0), gazeAt = 0.0
    private var breathPhase = 0.0
    private var ptrX = 0.0, ptrY = 0.0, ptrS = 0.0, ptrTargetX = 0.0, ptrTargetY = 0.0, ptrTargetS = 0.0
    private var baseYaw = 0.0, lookGain = 1.0

    public init(seed: Double, state: CompanionState = .idle) {
        rng = Rng(seed: seed)
        t = rng.next() * 10
        hopPhase = rng.next()
        breathPhase = rng.next()
        blinkAt = t + 1 + rng.next() * 3
        flipAt = nextFlip(1)
        nodAt = t + 3 + rng.next() * 4
        dartAt = t + 1 + rng.next() * 2
        laughAt = t + 0.6 + rng.next() * 1.5
        setState(state, immediately: true)
    }

    public mutating func setState(_ next: CompanionState, immediately: Bool = false) {
        if next == state && !immediately { return }
        let was = state
        state = next
        if immediately {
            pose.w = CompanionState.allCases.map { $0 == next ? 1 : 0 }
            tr = 1
        } else {
            wFrom = pose.w
            tr = 0
            trDuration = was == .sleeping ? 1 : [1.2, 0.7, 1.4][next.rawValue]
        }
        switch next {
        case .idle:
            yawW.set(turnYaw, 2.6, 5.4, 2); pitchW.set(turnPitch, 2.8, 5.8, 1.8); rollW.set(turnRoll, 3.4, 6.6, 1.5)
            gazeAt = 0; gazeDir = (0, 0)
            lookXW.set(3.6, 0.6, 2.2, 13); lookYW.set(2.4, 0.6, 2.2, 13)
            flipAt = nextFlip(0.6)
        case .working:
            yawW.set(16 * deg, 0.9, 1.8, 4); pitchW.set(3 * deg, 1.2, 2.4, 3); rollW.set(0, 1, 2, 3)
            lookXW.set(2, 0.5, 1.2, 12); lookYW.set(1, 0.5, 1.2, 12)
            hopPhase = 0; hopCount = 0
            laughAt = t + 0.5 + rng.next() * 1.2
        case .sleeping:
            yawW.set(7 * deg, 3, 6, 0.7); pitchW.set(3 * deg, 3, 6, 0.7); rollW.set(2 * deg, 3, 6, 0.6)
            lookXW.set(0, 2, 4, 2); lookYW.set(0, 2, 4, 2)
            nodAt = t + 2.5 + rng.next() * 4
        }
    }

    /// Where the pointer is relative to the head (-1 to 1 across a head width) and how strongly to follow it (0 lets go).
    public mutating func setPointer(x: Double, y: Double, strength: Double) {
        ptrTargetX = min(1.2, max(-1.2, x))
        ptrTargetY = min(1.2, max(-1.2, y))
        ptrTargetS = clamp01(strength)
    }

    /// A hop and a full turn, right now, whatever the state.
    public mutating func poke() {
        if flip.active && flip.p < 0.6 { return }
        flipPoked = true
        flip.duration = Jump.duration(poked: true)
        flipSide = rng.next() < 0.5 ? -1 : 1
        flip.fire()
        flipAt = nextFlip(1.1)
    }

    /// Where the head looks next: from a corner mostly straight across to the opposite one, now and then only sideways,
    /// or back to the middle for a beat.
    private mutating func nextGaze() -> (Double, Double) {
        let (s, a) = gazeDir
        if s != 0 || a != 0 {
            let o = rng.next()
            return o < 0.66 ? (-s, -a) : o < 0.85 ? (-s, a) : (0, 0)
        }
        return [(1, -1), (-1, 1), (-1, -1), (1, 1)][Int(rng.next() * 4)]
    }

    /// When the next idle jump is due: every 8 seconds, give or take 40 %.
    private mutating func nextFlip(_ scale: Double) -> Double { t + Jump.every * scale * (0.625 + rng.next() * 0.75) }

    /// Advances by `dt` seconds.
    public mutating func update(_ elapsed: Double) {
        let dt = min(elapsed, 0.05)
        t += dt
        let s = t
        if tr < 1 {
            tr = min(1, tr + dt / trDuration)
            let f = smooth(tr)
            for k in 0..<3 { pose.w[k] = wFrom[k] + ((k == state.rawValue ? 1 : 0) - wFrom[k]) * f }
        }
        let (o, r, c) = (pose.w[0], pose.w[1], pose.w[2])
        var rest = (pitch: 0.0, roll: 0.0, y: 0.0, lookX: 0.0, lookY: 0.0)
        for k in 0..<3 {
            let b = CompanionPose.baseline[k]
            rest.pitch += b.pitch * pose.w[k]; rest.roll += b.roll * pose.w[k]; rest.y += b.y * pose.w[k]
            rest.lookX += b.lookX * pose.w[k]; rest.lookY += b.lookY * pose.w[k]
        }
        lookGain = approach(lookGain, looksAround ? 1 : 0, 6, dt)
        if !looksAround { gazeAt = max(gazeAt, s + 1); dartAt = max(dartAt, s + 1); flipAt = max(flipAt, s + 2) } // so switching it on does not fire them all at once
        if state == .idle && s >= gazeAt && looksAround {
            let (f, k) = nextGaze()
            gazeDir = (f, k)
            let y = 0.84 + rng.next() * 0.16
            yawW.aim(f * turnYaw * y); pitchW.aim(k * turnPitch * y); rollW.aim(f * turnRoll * y)
            gazeAt = s + 2.6 + rng.next() * (4.4 - 2.6)
        }
        yawW.update(s, dt, &rng); pitchW.update(s, dt, &rng); rollW.update(s, dt, &rng)
        lookXW.update(s, dt, &rng); lookYW.update(s, dt, &rng)
        ptrS = approach(ptrS, looksAround ? ptrTargetS : 0, 8, dt)
        ptrX = approach(ptrX, ptrTargetX, 14, dt)
        ptrY = approach(ptrY, ptrTargetY, 14, dt)
        let h = ptrS, l = 1 - 0.75 * h // a pointer nearby damps the idle wander
        let g = lookGain
        baseYaw = approach(baseYaw, (yawW.value * l + 22 * deg * ptrX * h) * g, 5, dt)
        let pitch = rest.pitch + (pitchW.value * l - 12 * deg * ptrY * h) * g
        let roll = rest.roll + rollW.value * l * g
        let lookX = rest.lookX + (lookXW.value * l + 4.5 * ptrX * h) * g
        let lookY = rest.lookY + (lookYW.value * l + 3 * ptrY * h) * g

        var spin = 0.0, lift = 0.0, sx = 1.0, sy = 1.0, nodPitch = 0.0, lean = 0.0, blinkNow = 0.0
        var dartOffX = 0.0, dartOffY = 0.0, laughTarget = 0.0

        // Blink and glance, only while awake.
        if s >= blinkAt && !blink.active && o + r > 0.5 {
            blink.fire()
            blinkAgain = !blinkAgain && rng.next() < 0.22
            blinkAt = s + (blinkAgain ? 0.28 : 2.2 + rng.next() * 2.6)
        }
        blink.update(dt)
        if blink.active { blinkNow = sin(Double.pi * blink.p) }
        if s >= dartAt && !dart.active && o + r > 0.5 && looksAround {
            dart.fire()
            dartX = (rng.next() * 2 - 1) * 4
            dartY = (rng.next() * 2 - 1) * 2
            dart.duration = 0.25 + rng.next() * 0.45
            dartAt = s + 1.2 + rng.next() * 2.6
        }
        dart.update(dt)
        if dart.active {
            let f = dart.p, k = f < 0.15 ? f / 0.15 : f > 0.8 ? (1 - f) / 0.2 : 1
            dartOffX += dartX * k * (o + r); dartOffY += dartY * k * (o + r)
        }

        // The idle jump, and a poke: crouch, take off with a full turn, land, recover.
        if state == .idle && s >= flipAt && !flip.active && looksAround {
            flipPoked = false
            flip.duration = Jump.duration(poked: false)
            flipSide = rng.next() < 0.5 ? -1 : 1
            flip.fire()
            flipAt = nextFlip(1)
        }
        flip.update(dt)
        if flip.active {
            let windup = Jump.windup(poked: flipPoked)
            let y = (flip.p * flip.duration - windup) / Jump.time // below 0 crouching, 0 to 1 in the air, past 1 landed
            let q = clamp01(y), air = sin(Double.pi * q)
            spin += tau * Jump.spin * easeInOut(q)
            lift -= Jump.height * air
            let sinceLanding = (y - 1) * Jump.time
            let squashTime = flipPoked ? Jump.clickSquashTime : Jump.squashTime
            let pressed = Jump.pulse * squashTime, held = sinceLanding - pressed - Jump.groundTime
            let landed = sinceLanding <= pressed ? Jump.landing(sinceLanding / squashTime)
                : held <= 0 ? Jump.ground((sinceLanding - pressed) / Jump.groundTime)
                : Jump.rise(held / Jump.riseTime)
            let crouch: Double = {
                if y < 0 {
                    let u = max(0, 1 + y * Jump.time / windup)
                    return flipPoked ? u * u * (3 - 2 * u) : Jump.hit(u - 1)
                }
                return sinceLanding > 0 ? landed : y < 0.2 ? Jump.hit(y) : 0
            }() * Jump.squash
            sx += 0.16 * crouch - 0.06 * air * Jump.stretch
            sy += -0.18 * crouch + 0.09 * air * Jump.stretch
            lean += flipSide * Jump.lean * deg * air
            laughTarget = max(laughTarget, air) // the eyes squeeze shut in the air
        }

        // Working: hop, every third hop a spin. The hop under way finishes whole when the state is left.
        let settle = Jump.groundTime + Jump.riseTime
        if state == .working { hopGain = r }
        if hopGain > 0.02 && (state == .working || hopPhase > 0) {
            hopPhase += dt / hopTime
            if hopPhase >= 1 {
                if state == .working { hopPhase -= 1; hopCount += 1 }
                else if (hopPhase - 1) * hopTime >= settle { hopPhase = 0; hopGain = 0 }
            }
            let f = hopGain, k = min(1, hopPhase), air = sin(Double.pi * k), big = hopCount % 3 == 2
            lift -= (big ? Jump.height : 18) * air * f
            let after = state != .working && hopPhase > 1 ? (hopPhase - 1) * hopTime : -1
            let landed = after < 0 ? Jump.hit(hopPhase) : after < Jump.groundTime ? Jump.ground(after / Jump.groundTime) : Jump.rise((after - Jump.groundTime) / Jump.riseTime)
            sx += (0.16 * landed - 0.06 * air) * f
            sy += (-0.18 * landed + 0.09 * air) * f
            if big { spin += tau * easeInOut(k) * f; laughTarget = max(laughTarget, air * f) }
            lean += (hopCount % 2 == 0 ? 1 : -1) * 6 * deg * air * f
        }

        // Working: the odd laugh, eyes closing.
        if state == .working && s >= laughAt && !laughEv.active {
            laughEv.fire()
            laughEv.duration = 0.6 + rng.next() * 0.5
            laughAt = s + 1.6 + rng.next() * 2.2
        }
        laughEv.update(dt)
        if laughEv.active {
            let f = laughEv.p
            laughTarget = max(laughTarget, f < 0.18 ? f / 0.18 : f > 0.78 ? (1 - f) / 0.22 : 1)
        }

        // Sleeping: the odd nod.
        if state == .sleeping && s >= nodAt && !nod.active {
            nod.fire()
            nodAt = s + 4 + rng.next() * 4
        }
        nod.update(dt)
        if nod.active {
            let f = nod.p, k = f < 0.72 ? easeInOut(f / 0.72) : 1 - easeInOut((f - 0.72) / 0.28)
            nodPitch -= 13 * deg * k * c
        }

        // Breathing, deeper asleep; awake the body floats a little.
        breathPhase += dt / (3.6 + 1.2 * c)
        let breath = sin(breathPhase * tau)
        sx += breath * (0.008 + 0.014 * c)
        sy += breath * (0.012 + 0.02 * c)
        let float = sin(s * tau / 3.4) * 2 * (1 - c)

        pose.yaw = baseYaw + spin
        var turned = baseYaw - prevYaw
        turned = (turned + Double.pi).truncatingRemainder(dividingBy: tau)
        turned = (turned + tau).truncatingRemainder(dividingBy: tau) - Double.pi
        prevYaw = baseYaw
        let speed = dt > 0 ? abs(turned) / dt : 0
        // The eyes run ahead of a head turn, and the body wobbles like jelly when the head snaps round.
        gazeLead = approach(gazeLead, dt > 0 ? max(-2.2, min(2.2, turned / dt * 2.4)) : 0, 9, dt)
        let push = min(0.22, 0.055 * speed), spring = 16.0, damping = 0.45
        jellyV += (spring * spring * (push - jelly) - 2 * damping * spring * jellyV) * dt
        jelly += jellyV * dt
        let wobble = max(-0.08, min(0.28, jelly)) * 0.6
        sx *= 1 + wobble
        sy *= 1 - 0.55 * wobble

        pose.pitch = pitch + nodPitch
        pose.roll = roll + lean
        pose.x = 0
        pose.y = rest.y + lift + float
        pose.sx = sx; pose.sy = sy
        pose.laugh = approach(pose.laugh, laughTarget, 30, dt)
        pose.blinkL = blinkNow; pose.blinkR = blinkNow
        pose.lookX = lookX + dartOffX + gazeLead
        pose.lookY = lookY + dartOffY
        pose.breath = breath
    }
}
