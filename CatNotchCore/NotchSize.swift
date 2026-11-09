import CoreGraphics

public enum NotchSize {
    /// The closed Notch on a Mac with no hardware notch (the Electron Notch's 240 by 30).
    public static let fallback = CGSize(width: 240, height: 30)

    /// The hardware notch's size on a notched screen (the gap between the two top areas, as tall as the
    /// top safe area), else the fallback. Inputs are the NSScreen values; nil sides mean no notch.
    public static func closed(screenWidth: CGFloat, safeTop: CGFloat, leftWidth: CGFloat?, rightWidth: CGFloat?) -> CGSize {
        guard safeTop > 0, let leftWidth, let rightWidth else { return fallback }
        return CGSize(width: screenWidth - leftWidth - rightWidth, height: safeTop)
    }

    /// Room either side of a hardware notch for the clock.
    public static let wing: CGFloat = 64

    /// Room either side of a hardware notch for the companion alone.
    public static let idleWing: CGFloat = 30

    /// How wide each wing is, fitted to the widest thing either side shows (`content`, 0 when nothing shows): the edge
    /// inset and a small gap round it, never under `idleWing` or over the Electron Notch's full `wing`.
    public static func wing(content: CGFloat) -> CGFloat {
        content > 0 ? min(wing, max(idleWing, NotchLayout.closedInset + content + 6)) : 0
    }

    /// The closed Notch as drawn. With a hardware notch it is the cutout plus a wing each side (so it stays centred
    /// on the cutout) and `cutout` is the cutout's width, which stays black. Without one it is the default size and `cutout` is 0.
    public static func closedWithWings(screenWidth: CGFloat, safeTop: CGFloat, leftWidth: CGFloat?, rightWidth: CGFloat?) -> (size: CGSize, cutout: CGFloat) {
        guard safeTop > 0, leftWidth != nil, rightWidth != nil else { return (fallback, 0) }
        let hardware = closed(screenWidth: screenWidth, safeTop: safeTop, leftWidth: leftWidth, rightWidth: rightWidth)
        return (CGSize(width: hardware.width + 2 * wing, height: hardware.height), hardware.width)
    }
}
