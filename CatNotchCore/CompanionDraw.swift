import CoreGraphics
import Foundation

/// A small SVG path reader: `M L H V Q C A Z`, absolute and relative, which is all the outlines use. An arc is
/// turned into cubic curves as it is read. Anything else makes `parse` return nil rather than guess.
public enum SVGPath {
    public enum Command: Equatable, Sendable {
        case move(CGPoint), line(CGPoint), quad(CGPoint, CGPoint), cubic(CGPoint, CGPoint, CGPoint), close
    }

    private enum Token { case command(Character), number(Double) }

    private static func tokens(_ d: String) -> [Token]? {
        let c = Array(d)
        var out: [Token] = [], i = 0
        func digits() { while i < c.count, c[i].isASCII, c[i].isNumber { i += 1 } }
        while i < c.count {
            let ch = c[i]
            if ch == " " || ch == "," || ch == "\n" || ch == "\t" { i += 1; continue }
            if "MmLlHhVvQqCcAaZz".contains(ch) { out.append(.command(ch)); i += 1; continue }
            guard ch == "-" || ch == "+" || ch == "." || (ch.isASCII && ch.isNumber) else { return nil }
            let start = i
            if ch == "-" || ch == "+" { i += 1 }
            digits()
            if i < c.count, c[i] == "." { i += 1; digits() } // a second dot starts the next number
            if i < c.count, c[i] == "e" || c[i] == "E" {
                i += 1
                if i < c.count, c[i] == "-" || c[i] == "+" { i += 1 }
                digits()
            }
            guard let v = Double(String(c[start..<i])) else { return nil }
            out.append(.number(v))
        }
        return out
    }

    public static func parse(_ d: String) -> [Command]? {
        guard let tokens = tokens(d) else { return nil }
        var out: [Command] = [], i = 0
        var cmd: Character?, pos = CGPoint.zero, start = CGPoint.zero
        while i < tokens.count {
            if case .command(let c) = tokens[i] { cmd = c; i += 1 }
            guard let c = cmd else { return nil }
            let rel = c.isLowercase
            let arity = ["m": 2, "l": 2, "h": 1, "v": 1, "q": 4, "c": 6, "a": 7, "z": 0][Character(c.lowercased())] ?? 0
            if arity == 0 { out.append(.close); pos = start; cmd = nil; continue }
            // The numbers of one segment, repeated for as long as more follow ("L 1 2 3 4" is two lines, and
            // after a move the repeats are lines).
            var kind = Character(c.lowercased())
            while true {
                var n: [Double] = []
                while n.count < arity, i < tokens.count, case .number(let v) = tokens[i] { n.append(v); i += 1 }
                guard n.count == arity else { return nil }
                let ox = rel ? pos.x : 0, oy = rel ? pos.y : 0
                func pt(_ k: Int) -> CGPoint { CGPoint(x: n[k] + ox, y: n[k + 1] + oy) }
                switch kind {
                case "m": pos = pt(0); start = pos; out.append(.move(pos)); kind = "l"
                case "l": pos = pt(0); out.append(.line(pos))
                case "h": pos = CGPoint(x: n[0] + ox, y: pos.y); out.append(.line(pos))
                case "v": pos = CGPoint(x: pos.x, y: n[0] + oy); out.append(.line(pos))
                case "q": out.append(.quad(pt(0), pt(2))); pos = pt(2)
                case "a": out += arc(from: pos, rx: n[0], ry: n[1], rotation: n[2], large: n[3] != 0, sweep: n[4] != 0, to: pt(5)); pos = pt(5)
                default: out.append(.cubic(pt(0), pt(2), pt(4))); pos = pt(4)
                }
                guard i < tokens.count, case .number = tokens[i] else { break }
            }
        }
        return out
    }

    /// An elliptical arc as cubic curves, one per quarter turn or less (SVG's endpoint to centre conversion).
    private static func arc(from p0: CGPoint, rx: Double, ry: Double, rotation: Double, large: Bool, sweep: Bool, to p1: CGPoint) -> [Command] {
        if p0 == p1 { return [] }
        var rx = abs(rx), ry = abs(ry)
        if rx == 0 || ry == 0 { return [.line(p1)] }
        let phi = rotation * Double.pi / 180, cp = cos(phi), sp = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cp * dx + sp * dy, y1 = -sp * dx + cp * dy
        let grow = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
        if grow > 1 { rx *= grow.squareRoot(); ry *= grow.squareRoot() } // too small to reach: as small as will
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        let coef = (large == sweep ? -1.0 : 1.0) * max(0, (rx * rx * ry * ry - den) / den).squareRoot()
        let cx1 = coef * rx * y1 / ry, cy1 = -coef * ry * x1 / rx
        let cx = cp * cx1 - sp * cy1 + (p0.x + p1.x) / 2, cy = sp * cx1 + cp * cy1 + (p0.y + p1.y) / 2
        let start = atan2((y1 - cy1) / ry, (x1 - cx1) / rx)
        var sweepBy = atan2((-y1 - cy1) / ry, (-x1 - cx1) / rx) - start
        if !sweep && sweepBy > 0 { sweepBy -= 2 * Double.pi }
        if sweep && sweepBy < 0 { sweepBy += 2 * Double.pi }
        let parts = Int((abs(sweepBy) / (Double.pi / 2) - 1e-9).rounded(.up)), step = sweepBy / Double(parts)
        let k = 4.0 / 3 * tan(step / 4)
        func at(_ a: Double, _ along: Double = 0) -> CGPoint { // the point on the ellipse, moved `along` its tangent
            let x = cos(a) - along * sin(a), y = sin(a) + along * cos(a)
            return CGPoint(x: cx + rx * x * cp - ry * y * sp, y: cy + rx * x * sp + ry * y * cp)
        }
        return (0..<parts).map { i in
            let a = start + step * Double(i), b = a + step
            return .cubic(at(a, k), at(b, -k), i == parts - 1 ? p1 : at(b))
        }
    }

    public static func cgPath(_ d: String) -> CGPath? {
        guard let commands = parse(d) else { return nil }
        let path = CGMutablePath()
        for c in commands {
            switch c {
            case .move(let p): path.move(to: p)
            case .line(let p): path.addLine(to: p)
            case .quad(let c, let p): path.addQuadCurve(to: p, control: c)
            case .cubic(let c1, let c2, let p): path.addCurve(to: p, control1: c1, control2: c2)
            case .close: path.closeSubpath()
            }
        }
        return path
    }
}

/// Colours as 0xRRGGBB.
enum Shade {
    /// A shade of a colour: `dl` moves the lightness, `ds` the saturation (-1 to 1). A darker shade gets a touch more
    /// saturation so it stays rich rather than going grey, as the engine does.
    static func adjust(_ hex: UInt32, lightness dl: Double, saturation ds: Double = 0) -> UInt32 {
        let r = Double(hex >> 16 & 255) / 255, g = Double(hex >> 8 & 255) / 255, b = Double(hex & 255) / 255
        let hi = max(r, g, b), lo = min(r, g, b), d = hi - lo
        var l = (hi + lo) / 2, s = d == 0 ? 0 : d / (1 - abs(2 * l - 1))
        var h = 0.0
        if d != 0 {
            h = hi == r ? ((g - b) / d).truncatingRemainder(dividingBy: 6) : hi == g ? (b - r) / d + 2 : (r - g) / d + 4
            h = (h * 60 + 360).truncatingRemainder(dividingBy: 360)
        }
        l = min(1, max(0, l + dl))
        s = min(1, max(0, s + ds + (dl < 0 ? -dl * 0.25 : 0)))
        let c = (1 - abs(2 * l - 1)) * s, x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1)), m = l - c / 2
        let (r1, g1, b1): (Double, Double, Double) = switch Int(h / 60) % 6 {
        case 0: (c, x, 0)
        case 1: (x, c, 0)
        case 2: (0, c, x)
        case 3: (0, x, c)
        case 4: (x, 0, c)
        default: (c, 0, x)
        }
        func byte(_ v: Double) -> UInt32 { UInt32((min(1, max(0, v + m)) * 255).rounded()) }
        return byte(r1) << 16 | byte(g1) << 8 | byte(b1)
    }

    /// A colour part of the way from `a` to `b`.
    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func ch(_ shift: UInt32) -> UInt32 {
            let x = Double(a >> shift & 255), y = Double(b >> shift & 255)
            return UInt32((x + (y - x) * t).rounded())
        }
        return ch(16) << 16 | ch(8) << 8 | ch(0)
    }
}

extension Flavor {
    /// The accents the cat uses, 0xRRGGBB.
    public var mauve: UInt32 { switch self { case .mocha: 0xcba6f7; case .macchiato: 0xc6a0f6; case .frappe: 0xca9ee6 } }
    public var red: UInt32 { switch self { case .mocha: 0xf38ba8; case .macchiato: 0xed8796; case .frappe: 0xe78284 } }
    public var pink: UInt32 { switch self { case .mocha: 0xf5c2e7; case .macchiato: 0xf5bde6; case .frappe: 0xf4b8e4 } }
}

/// A character's colours: the body, the ink of the face, and the bow tie (the Catppuccin cat's only).
/// The cat's come from the chosen flavour: the dark body is its base, the face its Mauve, the bow its Red.
public struct CompanionLook: Equatable, Sendable {
    public var body: UInt32, ink: UInt32, bow: UInt32?
    public var character = CompanionCharacter.catppuccin

    public init(body: UInt32, ink: UInt32, bow: UInt32?, character: CompanionCharacter = .catppuccin) {
        (self.body, self.ink, self.bow, self.character) = (body, ink, bow, character)
    }

    public init(flavor: Flavor) { self.init(character: .catppuccin, flavor: flavor) }

    /// `coat` is the cat's chosen accent for its face; Mauve when nil.
    public init(character: CompanionCharacter, flavor: Flavor, coat: UInt32? = nil) {
        let body = character.body(flavor: flavor)
        if character == .catppuccin {
            let ink = coat ?? flavor.mauve
            self.init(body: body, ink: ink, bow: ink == flavor.red ? flavor.pink : flavor.red, character: character)
        } else {
            self.init(body: body, ink: CompanionCharacter.autoInk(on: body), bow: nil, character: character)
        }
    }
}

/// Draws the cat the way `bot-avatars` draws a bot: the outline stacked through a depth as shaded slices that tilt
/// with yaw, pitch and roll, then the face on the front, which slides over the head as it turns. The Electron app's
/// plastic matcap shading is replaced by its `smooth` look (a tone from dark at the back to the body colour at the
/// front, a soft shadow and a highlight), which it falls back to itself.
public enum CompanionRenderer {
    /// The canvas is this many boxes wide, so a hop and a spin are never clipped.
    public static let overscan = 1.5
    /// The body's centre sits this fraction of the box below the canvas centre: a hop needs the room above.
    public static let rise = 0.1

    // The Catppuccin mascot is our own outline (in `CompanionCharacter`): two pointed ears, a head, shoulders; a bow tie.
    nonisolated(unsafe) private static let bowPath = SVGPath.cgPath("M59 88 L51 84 L51 94 Z M59 88 L67 83 L68 93 Z")!

    private static let sliceCount = 17
    private static let halfDepth = 15 * 0.65
    private static let cap = 0.95 // how much of its size the front slice keeps
    private static let lightAngle = 265 * Double.pi / 180 // from the left
    private static let faceRadius = 30.0

    private static func cg(_ hex: UInt32, alpha: Double = 1) -> CGColor {
        CGColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
    }

    /// Draws into a context whose origin is the top left and y runs down, `box * overscan` points square.
    public static func draw(_ ctx: CGContext, box: CGFloat, pose: CompanionPose, look: CompanionLook) {
        guard let bodyPath = look.character.outline else { return }
        let k = Double(box) / 100, side = Double(box) * overscan
        let cr = cos(pose.roll), sr = sin(pose.roll), x = pose.sx * k, y = pose.sy * k, v = 50 * (1 - pose.sy) * k
        let body = CGAffineTransform(a: cr * x, b: sr * x, c: -sr * y, d: cr * y,
                                     tx: side / 2 + pose.x * k - sr * v, ty: side / 2 + rise * Double(box) + pose.y * k + cr * v)
        let cy = cos(pose.yaw), sy = sin(pose.yaw), cp = cos(pose.pitch), sp = sin(pose.pitch)
        let facing = cy * cp
        func floored(_ r: Double) -> Double { abs(r) < 0.22 ? (r < 0 ? -0.22 : 0.22) : r } // so a side-on body keeps some width
        let w = floored(cy), b = floored(cp)
        /// Where the slice at depth `st` (-1 back, 1 front) lands, in body space.
        func slice(_ st: Double) -> CGAffineTransform {
            let lt = cap + (1 - cap) * sqrt(max(0, 1 - st * st))
            let yt = w * lt, gt = sy * sp * lt, pt = b * lt
            return CGAffineTransform(a: yt, b: gt, c: 0, d: pt, tx: st * sy * halfDepth - 50 * yt, ty: -st * w * sp * halfDepth - 50 * gt - 50 * pt)
        }

        // The slices, back to front: dark far away, the body colour at the cap.
        let far = Shade.adjust(look.body, lightness: -0.3 * 0.35, saturation: 0.05 * 0.35)
        let front = facing >= 0 ? 1.0 : -1.0
        let outline = CGMutablePath()
        ctx.saveGState()
        for index in 0..<sliceCount {
            let st = -1 + 2 * Double(front > 0 ? index : sliceCount - 1 - index) / Double(sliceCount - 1)
            let place = slice(st).concatenating(body)
            let t = Double(index) / Double(sliceCount - 1)
            ctx.setFillColor(cg(t >= 0.5 ? look.body : Shade.mix(far, look.body, t / 0.5)))
            var m = place
            let placed = bodyPath.copy(using: &m)! // the outline as it lands on this slice
            ctx.addPath(placed)
            ctx.fillPath()
            outline.addPath(placed)
        }
        // A soft shadow away from the light and a highlight towards it, over the whole solid.
        ctx.saveGState()
        ctx.addPath(outline)
        ctx.clip()
        ctx.concatenate(body)
        let lx = sin(lightAngle), ly = -cos(lightAngle), spread = 1.55
        let space = CGColorSpaceCreateDeviceRGB()
        let shadow = CGGradient(colorsSpace: space, colors: [CGColor(gray: 0, alpha: 0.1225), CGColor(gray: 0, alpha: 0.043), CGColor(gray: 0, alpha: 0)] as CFArray, locations: [0, 0.5, 1])!
        ctx.setBlendMode(.multiply)
        ctx.drawRadialGradient(shadow, startCenter: CGPoint(x: -lx * 45, y: -ly * 45), startRadius: 4 * spread,
                               endCenter: CGPoint(x: -lx * 45, y: -ly * 45), endRadius: 84 * spread, options: [.drawsBeforeStartLocation])
        let shine = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 0.286), CGColor(gray: 1, alpha: 0.066), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 0.6, 1])!
        ctx.setBlendMode(.normal)
        ctx.drawRadialGradient(shine, startCenter: CGPoint(x: lx * 37, y: ly * 37), startRadius: 0,
                               endCenter: CGPoint(x: lx * 37, y: ly * 37), endRadius: 62 * spread, options: [])
        ctx.restoreGState()

        // The face, clipped to the front cap so it never leaves the head.
        if facing > -0.2 {
            ctx.saveGState()
            var cap = slice(front).concatenating(body)
            ctx.addPath(bodyPath.copy(using: &cap)!)
            ctx.clip()
            ctx.concatenate(body)
            let face = look.character.face
            ctx.translateBy(x: face.x - 50, y: face.y - 50)
            ctx.scaleBy(x: face.scale, y: face.scale)
            drawEyes(ctx, pose: pose, ink: look.ink, cap: look.character.squareEyes ? .square : .round)
            ctx.restoreGState()
        }

        // The bow sits on the front, so it hides when a spin shows the back, and slides against the head's turn.
        if cy > 0, let bow = look.bow {
            ctx.saveGState()
            ctx.concatenate(body)
            ctx.translateBy(x: -50 - sy * 6, y: -50)
            ctx.setFillColor(cg(bow))
            ctx.setStrokeColor(cg(bow))
            ctx.setLineWidth(1.5)
            ctx.setLineJoin(.round)
            ctx.addPath(bowPath)
            ctx.drawPath(using: .fillStroke)
            ctx.fillEllipse(in: CGRect(x: 59 - 2.6, y: 88 - 2.6, width: 5.2, height: 5.2))
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }

    /// A point on the face, put on the head's sphere: where it lands and how squashed it looks, `z` above 0 when it
    /// faces the viewer.
    private static func project(_ px: Double, _ py: Double, yaw: Double, pitch: Double) -> (x: Double, y: Double, sx: Double, sy: Double, z: Double) {
        let i = asin(max(-1, min(1, px / faceRadius))) + yaw, o = asin(max(-1, min(1, -py / faceRadius))) + pitch, r = cos(o)
        return (faceRadius * sin(i) * r, -faceRadius * sin(o), cos(i), r, cos(i) * r)
    }

    /// The eyes: a dot awake, a line when a lid is down, a happy arc in a laugh, a sleeping curve, blended by the weights.
    private static func drawEyes(_ ctx: CGContext, pose: CompanionPose, ink: UInt32, cap: CGLineCap) {
        let (a, i, o) = (pose.w[0], pose.w[1], pose.w[2])
        func dead(_ v: Double, _ c: Double) -> Double { abs(v) <= c ? 0 : (v < 0 ? -1 : 1) * (abs(v) - c) / (1 - c) }
        func unit(_ v: Double) -> Double { max(-1, min(1, v)) }
        let up = dead(unit(-pose.pitch / 0.26 - pose.lookY / 7), 0.34) // looking up opens the eyes taller
        let aside = abs(dead(unit(pose.lookX / 4.5), 0.4)) // looking aside narrows them
        let tall = max(0.3, 1 + 0.55 * up - 0.1 * aside), wide = 1 - 0.05 * up + 0.12 * aside
        let awake = a + i * (1 - pose.laugh), laugh = i * pose.laugh
        let hop = max(0, -pose.y) / 26, breath = 0.5 + 0.5 * pose.breath
        ctx.setStrokeColor(cg(ink))
        ctx.setLineCap(cap)
        for side in [-1.0, 1.0] {
            let lid = side < 0 ? pose.blinkL : pose.blinkR
            let open = max(0, min(1, 1 - lid))
            let x = awake * open, y = awake * (1 - open), v = laugh, l = o
            let half = x * 0.01 + y * 5.4 + v * 6.2 + l * 6
            let end = x * 1.1 * tall + y * 0.6 + v * (2.2 - hop * 1.5) + l * (-1.4 + breath)
            let control = x * (cap == .square ? 1.1 : -3.3) * tall + y * 0.6 + v * (-11.4 - 4 * hop) + l * (5.4 + 2 * breath)
            let width = x * 6.3 * 2 * wide + y * 2.8 + v * 4.4 + l * 4
            let gx = pose.lookX * (x + 0.5 * (y + v)), gy = pose.lookY * (x + 0.5 * y)
            let p = project(side * 12.5 + gx, 1 + gy, yaw: pose.yaw, pitch: pose.pitch)
            guard p.z > 0.02 else { continue }
            ctx.saveGState()
            ctx.setAlpha(min(1, p.z * 5))
            ctx.translateBy(x: p.x, y: p.y)
            ctx.scaleBy(x: max(0.02, p.sx), y: max(0.02, p.sy))
            if cap == .square { ctx.scaleBy(x: 1, y: 1 + 0.8 * x) } // an awake block eye is taller than wide; a lid down flattens it
            ctx.setLineWidth(width)
            ctx.move(to: CGPoint(x: -half, y: end))
            ctx.addQuadCurve(to: CGPoint(x: half, y: end), control: CGPoint(x: 0, y: control))
            ctx.strokePath()
            ctx.restoreGState()
        }
    }
}
