import AppKit
import SwiftUI
import CatNotchCore

extension View {
    /// The hand cursor over anything that clicks. Deployment target is 14, so no `.pointerStyle`.
    func pointerCursor() -> some View { modifier(PointerCursor()) }
}

/// How many clickable things the pointer is on. A push/pop cursor loses to AppKit, which puts the arrow back on the next
/// mouse move of a panel that is not key, so the hosting view re-asserts `cursor` on every move (`TrackedHostingView`).
@MainActor
enum HandCursor {
    private(set) static var count = 0
    static var cursor: NSCursor { count > 0 ? .pointingHand : .arrow }

    static func enter() { count += 1; cursor.set() }
    static func leave() { count = max(0, count - 1); cursor.set() }
}

/// Counts the pointer in on enter and out on leave, and out on removal too: a view that goes away under the pointer
/// (a task ticked off, a page swapped) would otherwise leave the hand stuck.
private struct PointerCursor: ViewModifier {
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                guard inside != on else { return }
                on = inside
                if inside { HandCursor.enter() } else { HandCursor.leave() }
            }
            .onDisappear { if on { on = false; HandCursor.leave() } }
    }
}

/// A plain button that answers the pointer: it lifts and brightens on hover, sinks on press, and shows the hand.
struct LivelyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Lively(configuration: configuration) }

    private struct Lively: View {
        let configuration: Configuration
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .brightness(hovering && enabled ? 0.18 : 0)
                .scaleEffect(configuration.isPressed ? 0.9 : hovering && enabled ? 1.08 : 1)
                .opacity(configuration.isPressed ? 0.75 : 1)
                .animation(.spring(duration: 0.22, bounce: 0.35), value: hovering)
                .animation(.spring(duration: 0.15), value: configuration.isPressed)
                .onHover { hovering = $0 }
                .pointerCursor()
        }
    }
}

extension ButtonStyle where Self == LivelyButtonStyle {
    static var lively: LivelyButtonStyle { LivelyButtonStyle() }
}

/// The small info icon beside anything that reads from somewhere: hover for the one line, click to open the whole
/// list (`SourceLines`) in place. Not a popover: a popover is its own window, and the Notch closes when the pointer
/// leaves it.
struct SourceInfo: View {
    let source: DataSource
    @Binding var open: Bool

    var body: some View {
        Button { open.toggle() } label: {
            Image(systemName: open ? "info.circle.fill" : "info.circle")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(open ? 0.85 : 0.5))
                .frame(width: 18, height: 18).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help(source.summary)
        .accessibilityLabel("How CatNotch gets this")
        .accessibilityHint(source.summary)
    }
}

/// What `SourceInfo` opens: one short paragraph per fact.
struct SourceLines: View {
    let source: DataSource
    var size: CGFloat = 10.5

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(source.lines, id: \.self) { line in
                Text(line).font(.system(size: size)).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
