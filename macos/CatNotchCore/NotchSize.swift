import CoreGraphics

public enum NotchSize {
    /// The closed Notch on a Mac with no hardware notch.
    public static let fallback = CGSize(width: 200, height: 32)

    /// The hardware notch's size on a notched screen (the gap between the two top areas, as tall as the
    /// top safe area), else the fallback. Inputs are the NSScreen values; nil sides mean no notch.
    public static func closed(screenWidth: CGFloat, safeTop: CGFloat, leftWidth: CGFloat?, rightWidth: CGFloat?) -> CGSize {
        guard safeTop > 0, let leftWidth, let rightWidth else { return fallback }
        return CGSize(width: screenWidth - leftWidth - rightWidth, height: safeTop)
    }
}
