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
                    Text(model.page.label).font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.top, closed.height + 10)
                .transition(.opacity)
            } else {
                // On a hardware notch the clock sits in the left wing; otherwise it centres in the closed Notch.
                ClosedClock()
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
