import SwiftUI
import CatNotchCore

@MainActor @Observable
final class NotchModel {
    var isOpen = false
    var hover: NotchHover
    /// Width of the black hardware cutout, 0 on a display without one.
    var cutout: CGFloat = 0
    var style = NotchStyle.black
    var flavor = Flavor.mocha
    var page = NotchPage.home

    init(open: CGSize) { hover = NotchHover(closed: NotchSize.fallback, open: open) }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 255) / 255, green: Double(hex >> 8 & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

/// The Notch's fill. Black is solid; Transparent and Glass tint the flavour over the desktop behind it,
/// with Liquid Glass on macOS 26 and a material before that.
private struct NotchFill<S: InsettableShape>: View {
    let style: NotchStyle
    let flavor: Flavor
    let shape: S

    private func material(glass: Bool, tint: Color) -> some View {
        shape.fill(glass ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.ultraThinMaterial))
            .overlay(shape.fill(tint))
    }

    var body: some View {
        let glass = style == .glass
        let tint = Color(hex: flavor.base).opacity(glass ? 0.45 : 0.22)
        switch style {
        case .black:
            shape.fill(.black)
        case .transparent, .glass:
            #if compiler(>=6.2) // glassEffect needs the macOS 26 SDK; CI builds with Xcode 16
            if #available(macOS 26, *) {
                Color.clear.glassEffect(glass ? .regular.tint(tint) : .clear.tint(tint), in: shape)
            } else {
                material(glass: glass, tint: tint)
            }
            #else
            material(glass: glass, tint: tint)
            #endif
        }
    }
}

/// The closed clock: 12-hour, with a small AM or PM. Redraws on the minute, no timer of ours.
private struct ClosedClock: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            let text = WallClock.text(context.date)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(text.time).font(.system(size: 12, weight: .semibold).monospacedDigit())
                Text(text.meridiem).font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.92))
            .shadow(color: .black.opacity(0.35), radius: 1, y: 1) // keeps it readable over a light wallpaper
        }
    }
}

/// Focus has its own colour, so it never reads as another meter.
private let focusColor = Color(red: 52 / 255, green: 211 / 255, blue: 153 / 255)

/// A ring that fills to `fraction`, starting at the top.
private struct FocusRing: View {
    let fraction: Double
    let width: CGFloat
    var color = Color.white

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.18), lineWidth: width)
            Circle().trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.linear(duration: 1), value: fraction) // one tick a second, so it glides rather than steps
    }
}

/// What the closed Notch says while a session runs: the ring draining and the time left, in the clock's place.
private struct ClosedFocus: View {
    var focus: FocusModel

    var body: some View {
        HStack(spacing: 5) {
            FocusRing(fraction: 1 - focus.progress, width: 2).frame(width: 11, height: 11)
            Text(FocusLength.clock(seconds: focus.remaining)).font(.system(size: 10, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(.white.opacity(0.85))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Focus, \(FocusLength.clock(seconds: focus.remaining)) left")
    }
}

/// The focus tile on the Focus & tasks view: ring, time, today's tally and the controls.
private struct FocusTile: View {
    var focus: FocusModel

    private var time: String {
        switch focus.phase {
        case .idle: FocusLength.format(focus.minutes)
        case .running, .paused: FocusLength.clock(seconds: focus.remaining)
        case .finished: "Break"
        }
    }

    var body: some View {
        let today = focus.today
        HStack(spacing: 16) {
            FocusRing(fraction: focus.phase == .idle ? 1 : focus.progress, width: 6, color: focusColor)
                .opacity(focus.phase == .idle ? 0.35 : 1)
                .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 4) {
                Text(focus.phase.title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.white.opacity(0.55))
                Text(time).font(.system(size: 26, weight: .semibold).monospacedDigit()).foregroundStyle(focus.phase == .idle ? .white : focusColor)
                Text(today.sessions == 0 ? "No sessions today" : "Today: \(today.sessions) \(today.sessions == 1 ? "session" : "sessions"), \(Int(today.minutes)) min")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            }
            VStack(spacing: 6) {
                Button(action: focus.toggle) {
                    Text(focus.phase.action).font(.system(size: 12, weight: .semibold)).foregroundStyle(.black)
                        .frame(width: 64).padding(.vertical, 6).background(Capsule().fill(.white))
                }
                if focus.phase != .idle {
                    Button("Reset", action: focus.reset).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                }
            }
            .buttonStyle(.plain)
        }
    }
}

/// One task: the whole row ticks it, the cross (on hover) removes it.
private struct TaskRow: View {
    let task: StoreTask
    var tasks: TaskModel
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(task.done ? .white.opacity(0.6) : focusColor.opacity(hovering ? 1 : 0.5))
            Text(task.label)
                .font(.system(size: 13)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.white.opacity(task.done ? 0.3 : 0.9)).strikethrough(task.done)
            Button { tasks.remove(task.id) } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                .buttonStyle(.plain).foregroundStyle(.white.opacity(0.5))
                .opacity(hovering ? 1 : 0).accessibilityLabel("Delete task")
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture { tasks.toggle(task.id) }
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(task.label), \(task.done ? "done" : "not done")")
    }
}

/// The task list: a line to type on, the open tasks, and the done ones folded below.
private struct TasksList: View {
    var tasks: TaskModel
    @State private var draft = ""
    @State private var showDone = false

    var body: some View {
        let open = tasks.open, done = tasks.done
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.4))
                TextField("What needs doing", text: $draft)
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .onChange(of: draft) { if draft.count > StoreData.taskMaxLength { draft = String(draft.prefix(StoreData.taskMaxLength)) } }
                    .onSubmit { tasks.add(draft); draft = "" }
                if !open.isEmpty { Text("\(open.count)").font(.system(size: 11).monospacedDigit()).foregroundStyle(.white.opacity(0.35)) }
            }
            .padding(.vertical, 6)
            .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.12)).frame(height: 1) }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(showDone ? open + done : open, id: \.id) { TaskRow(task: $0, tasks: tasks) }
                    if open.isEmpty && !showDone {
                        Text("Nothing left. Type the next thing above.")
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.35))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                    }
                }
            }
            .scrollIndicators(.never)

            if !done.isEmpty {
                HStack(spacing: 12) {
                    Button("\(done.count) done\(showDone ? " · hide" : "")") { showDone.toggle() }
                    Button("Clear", action: tasks.clearDone)
                }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
            }
        }
    }
}

/// The circles that move between views. The white highlight slides to the chosen one.
private struct ViewSwitcher: View {
    @Binding var page: NotchPage
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 6) {
            ForEach(NotchPage.allCases, id: \.self) { item in
                Button { withAnimation(.spring(duration: 0.3)) { page = item } } label: {
                    Image(systemName: item.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(item == page ? .black : .white.opacity(0.6))
                        .frame(width: 28, height: 28)
                        .background {
                            if item == page { Circle().fill(.white).matchedGeometryEffect(id: "highlight", in: highlight) }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(item.label)
                .accessibilityLabel(item.label)
                .accessibilityAddTraits(item == page ? .isSelected : [])
            }
        }
    }
}

struct NotchView: View {
    var model: NotchModel
    var focus: FocusModel
    var tasks: TaskModel

    var body: some View {
        let size = model.hover.size(isOpen: model.isOpen)
        let closed = model.hover.closed
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18)
        ZStack(alignment: .top) {
            NotchFill(style: model.style, flavor: model.flavor, shape: shape)
            // The hardware cutout stays black in every style, so the Notch still grows out of it.
            if model.cutout > 0 { Rectangle().fill(.black).frame(width: model.cutout, height: closed.height) }

            if model.isOpen {
                VStack(spacing: 14) {
                    ViewSwitcher(page: Bindable(model).page)
                    if model.page == .desk {
                        HStack(alignment: .top, spacing: 28) {
                            FocusTile(focus: focus)
                            TasksList(tasks: tasks)
                        }
                        .padding(.horizontal, 28).padding(.bottom, 14)
                    } else {
                        Text(model.page.label).font(.system(size: 15, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .padding(.top, closed.height + 10)
                .transition(.opacity)
            } else {
                // On a hardware notch the clock sits in the left wing; otherwise it centres in the closed Notch.
                Group {
                    // A running session takes the clock's place; a paused one gives it back.
                    if focus.phase == .running { ClosedFocus(focus: focus) } else { ClosedClock() }
                }
                    .frame(width: model.cutout > 0 ? NotchSize.wing : closed.width, height: closed.height)
                    .frame(width: closed.width, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(duration: 0.3), value: model.isOpen)
        .environment(\.colorScheme, .dark) // materials stay dark whatever the system appearance is
        .ignoresSafeArea() // a hardware notch would otherwise push the drawing below the hit rect
    }
}
