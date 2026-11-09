import SwiftUI
import CatNotchCore

private let micColor = Color(red: 1, green: 0.62, blue: 0.04)
private let cameraColor = Color(red: 0.19, green: 0.82, blue: 0.35)

/// The dots the closed Notch shows while the microphone or camera is in use, as macOS does in the menu bar.
struct PrivacyDots: View {
    var system: SystemModel

    var body: some View {
        HStack(spacing: 8) {
            if system.micInUse { Circle().fill(micColor).frame(width: 6, height: 6) }
            if system.cameraInUse { Circle().fill(cameraColor).frame(width: 6, height: 6) }
        }
        .accessibilityElement()
        .accessibilityLabel([system.micInUse ? "Microphone in use" : nil, system.cameraInUse ? "Camera in use" : nil].compactMap { $0 }.joined(separator: ", "))
    }
}

/// What the closed Notch says for a moment when headphones connect, in the clock's place.
struct ClosedHeadphones: View {
    let name: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "headphones").font(.system(size: 10, weight: .semibold))
            Text(name).font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: 38, alignment: .leading) // a long name shrinks to fit the wing
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name) connected")
    }
}

/// One small pill: a symbol and a line of text.
private struct Chip<Icon: View>: View {
    @ViewBuilder var icon: Icon
    let text: String
    var tint = Color.white.opacity(0.75)

    var body: some View {
        HStack(spacing: 5) {
            icon.font(.system(size: 12)).foregroundStyle(tint)
            Text(text).font(.system(size: 11.5, weight: .medium).monospacedDigit()).lineLimit(1).truncationMode(.tail).frame(maxWidth: 150, alignment: .leading).fixedSize().foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(.white.opacity(0.09)))
        .accessibilityElement(children: .combine)
    }
}

/// The Home view's strip under the cards: Bluetooth devices and mic and camera in use.
/// A tile whose capability is missing is simply not there.
struct GlanceRow: View {
    var system: SystemModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(system.bluetooth.prefix(2)) { device in
                Chip(icon: { Image(systemName: Headphones.isWorn(device.name) ? "headphones" : "dot.radiowaves.right") },
                     text: device.battery.map { "\(device.name) \($0)%" } ?? device.name)
            }
            if system.micInUse { Chip(icon: { Image(systemName: "mic.fill") }, text: "Microphone", tint: micColor) }
            if system.cameraInUse { Chip(icon: { Image(systemName: "video.fill") }, text: "Camera", tint: cameraColor) }
        }
        .frame(height: 30)
        .task { // the Notch opening is the moment to look again; each call skips itself when it has looked recently
            system.refreshBluetooth()
        }
    }
}

extension View {
    /// The card every Home tile shares, like the Electron Notch's row: one height, a pale pane with a hairline edge,
    /// and optionally a hint of a colour (the album art's).
    func homeTile(width: CGFloat, tint: Color? = nil) -> some View {
        padding(12).frame(width: width, height: NotchLayout.tile)
            .background {
                let card = RoundedRectangle(cornerRadius: 18, style: .continuous)
                card.fill(.white.opacity(0.1)).overlay(card.fill((tint ?? .clear).opacity(0.14))).overlay(card.strokeBorder(.white.opacity(0.14)))
            }
    }
}

/// "6 AM" for a minute of the day.
private func hhmm(_ minute: Int) -> String { "\(minute / 60 % 12 == 0 ? 12 : minute / 60 % 12) \(minute < 720 ? "AM" : "PM")" }
/// "3h 21m", "45m".
private func span(_ minutes: Int) -> String { minutes >= 60 ? "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m" : "\(minutes)m" }

/// The clock beside the companion, as the Electron card's Clock mode: the time, the date and one line about the light
/// (sunrise and sunset are fixed at 6 AM and 6 PM, as there). Unfolded, the day is one wave through a horizon with the sun
/// (or the moon) riding it. Redraws on the minute.
struct ClockMode: View {
    var expanded: Bool
    @Environment(\.companionAccent) private var accent
    private static let sunrise = 6 * 60, sunset = 18 * 60
    private static let height: CGFloat = 44
    private nonisolated static let horizon: CGFloat = 25, amplitude: CGFloat = 17 // read inside the nonisolated Canvas closure

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date, clock = WallClock.text(now)
            let minute = Calendar.current.component(.hour, from: now) * 60 + Calendar.current.component(.minute, from: now)
            let up = minute >= Self.sunrise && minute < Self.sunset
            let note = up ? "\(span(Self.sunset - minute)) of daylight left" : "Sunrise in \(span((Self.sunrise - minute + 1440) % 1440))"
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(clock.time).font(.system(size: 28, weight: .semibold).monospacedDigit()).tracking(-1.2)
                        Text(clock.meridiem).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.65))
                    }
                    if expanded { // the date belongs with the time, stacked beside it
                        VStack(alignment: .leading, spacing: 3) {
                            Text(now.formatted(.dateTime.weekday(.wide))).font(.system(size: 11, weight: .semibold))
                            Text(now.formatted(.dateTime.day().month(.abbreviated))).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
                if expanded {
                    wave(minute: minute, up: up)
                    Text(note).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white.opacity(0.65))
                } else {
                    Text(now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))).font(.system(size: 11, weight: .semibold))
                    Label(up ? "\(span(Self.sunset - minute)) left" : "Up in \(span((Self.sunrise - minute + 1440) % 1440))", systemImage: up ? "sun.max.fill" : "moon.fill")
                        .font(.system(size: 10.5, weight: .medium)).foregroundStyle(up ? accent : .white.opacity(0.7)).labelStyle(.titleAndIcon)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(clock.time) \(clock.meridiem), \(now.formatted(.dateTime.weekday(.wide).day().month(.wide))), \(note)")
        }
    }

    /// One cosine over the day, peaking at midday and crossing the horizon at sunrise and sunset.
    private func wave(minute: Int, up: Bool) -> some View {
        Canvas { context, size in
            let w = size.width, h = Self.horizon
            func y(_ t: Double) -> CGFloat { h + Self.amplitude * CGFloat(cos(2 * .pi * t)) }
            var path = Path()
            for i in 0...120 { let t = Double(i) / 120; let p = CGPoint(x: w * t, y: y(t)); i == 0 ? path.move(to: p) : path.addLine(to: p) }
            var day = Path()
            day.move(to: CGPoint(x: w * 0.25, y: h))
            for i in 30...90 { let t = Double(i) / 120; day.addLine(to: CGPoint(x: w * t, y: y(t))) }
            day.addLine(to: CGPoint(x: w * 0.75, y: h)); day.closeSubpath()
            context.fill(day, with: .linearGradient(Gradient(colors: [accent.opacity(0.22), accent.opacity(0)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            context.stroke(Path { $0.move(to: CGPoint(x: 0, y: h)); $0.addLine(to: CGPoint(x: w, y: h)) }, with: .color(.white.opacity(0.22)), lineWidth: 1)
            context.stroke(path, with: .color(.white.opacity(0.13)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            let t = Double(minute) / 1440
            context.stroke(path.trimmedPath(from: 0, to: t), with: .color(accent.opacity(0.8)), style: StrokeStyle(lineWidth: 2, lineCap: .round)) // the part already gone
            for (at, label) in [(0.25, hhmm(Self.sunrise)), (0.75, hhmm(Self.sunset))] {
                context.fill(Path(ellipseIn: CGRect(x: w * at - 1.6, y: h - 1.6, width: 3.2, height: 3.2)), with: .color(.white.opacity(0.45)))
                context.draw(Text(label).font(.system(size: 8, weight: .medium).monospacedDigit()).foregroundStyle(.white.opacity(0.4)),
                             at: CGPoint(x: w * at + (at == 0.25 ? -5 : 5), y: h - 4), anchor: at == 0.25 ? .bottomTrailing : .bottomLeading)
            }
            let here = CGPoint(x: w * t, y: y(t))
            if up {
                context.drawLayer { layer in
                    layer.addFilter(.shadow(color: accent, radius: 5))
                    layer.fill(Path(ellipseIn: CGRect(x: here.x - 4.3, y: here.y - 4.3, width: 8.6, height: 8.6)), with: .color(accent))
                }
            } else {
                context.fill(Path(ellipseIn: CGRect(x: here.x - 4.3, y: here.y - 4.3, width: 8.6, height: 8.6)), with: .color(.white.opacity(0.9)))
                context.fill(Path(ellipseIn: CGRect(x: here.x - 2.3, y: here.y - 5.8, width: 8.6, height: 8.6)), with: .color(Color(hex: 0x0d0f14)))
            }
        }
        .frame(height: Self.height)
    }
}

/// The time on its own, when there is no companion, music or usage to lead with (the Electron time tile): "Monday afternoon",
/// the clock, the date.
struct TimeTile: View {
    private static let part = [(5, "night"), (12, "morning"), (17, "afternoon"), (21, "evening")]

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date, hour = Calendar.current.component(.hour, from: now)
            let part = Self.part.last { hour >= $0.0 }?.1 ?? "night"
            let clock = WallClock.text(now)
            VStack(alignment: .leading, spacing: 8) {
                Text("\(now.formatted(.dateTime.weekday(.wide))) \(part)".uppercased())
                    .font(.system(size: 8.5, weight: .bold)).tracking(1).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(clock.time).font(.system(size: 32, weight: .semibold).monospacedDigit()).tracking(-1)
                    Text(clock.meridiem).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                }
                Text(now.formatted(.dateTime.day().month(.wide))).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.65))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
        .homeTile(width: NotchLayout.timeWidth)
    }
}

/// One line under the tiles: the next event today and when it starts. Nothing when there is none.
struct NextEventLine: View {
    let event: AgendaEvent

    var body: some View {
        TimelineView(.everyMinute) { context in
            (Text(event.displayTitle).fontWeight(.semibold).foregroundStyle(.white.opacity(0.85)) + Text(" \(Agenda.until(event, now: context.date))"))
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity)
        }
        .frame(height: NotchLayout.nextEventLine)
    }
}
