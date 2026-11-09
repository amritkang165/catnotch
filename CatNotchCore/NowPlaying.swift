import Foundation

/// A transport key for the adapter's `send` command. The numbers are MediaRemote's.
public enum Transport: Int, Sendable {
    case play = 0, pause = 1, playPause = 2, next = 4, previous = 5
}

/// What is playing, as the mediaremote-adapter reports it.
public struct NowPlaying: Equatable, Sendable {
    public var sourceAppId: String
    public var title: String
    public var artist: String
    public var album: String
    public var isPlaying: Bool
    /// Where the track was at `timestamp`; use `position(at:)` for where it is now.
    public var elapsed: TimeInterval
    public var timestamp: Date?
    public var duration: TimeInterval
    /// The album art as the player published it (any size), or nil.
    public var artwork: Data?

    /// Where the track is at `date`: the adapter reports a position and when it was true, so a playing track moves on from there.
    public func position(at date: Date) -> TimeInterval {
        var p = elapsed
        if isPlaying, let timestamp { p += max(0, date.timeIntervalSince(timestamp)) }
        return duration > 0 ? min(p, duration) : p
    }
}

extension NowPlaying {
    /// How far through the track it is, 0 to 1 (0 when the length is unknown, as for a live stream).
    public func fraction(at date: Date) -> Double { duration > 0 ? position(at: date) / duration : 0 }
}

/// Track times as a player shows them.
public enum TrackTime {
    /// "mm:ss" as the macOS Now Playing writes it, or "h:mm:ss" from an hour up. Rounds down, so a track never shows a second it has not reached.
    public static func text(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let (h, m, s) = (total / 3600, total / 60 % 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

/// Reads the adapter's `stream` output, one JSON line at a time, into the current `NowPlaying`.
/// A `diff` line only carries what changed, and a key set to null has gone away.
public struct NowPlayingStream {
    private var state: [String: Any] = [:]
    public private(set) var current: NowPlaying?

    public init() {}

    /// Takes one line. Returns true if it was a data line (the track may or may not have changed).
    @discardableResult
    public mutating func feed(_ line: String) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              object["type"] as? String == "data" else { return false }
        let payload = object["payload"] as? [String: Any] ?? [:]
        state = object["diff"] as? Bool == true ? state.merging(payload) { $1 } : payload
        state = state.filter { !($0.value is NSNull) }
        current = Self.make(state)
        return true
    }

    /// The adapter went away: nothing is playing as far as we know.
    public mutating func reset() {
        state = [:]
        current = nil
    }

    private static func make(_ s: [String: Any]) -> NowPlaying? {
        guard let title = s["title"] as? String, !title.isEmpty, let app = s["bundleIdentifier"] as? String, !app.isEmpty else { return nil }
        func number(_ key: String) -> Double { (s[key] as? NSNumber)?.doubleValue ?? 0 }
        let micros = number("timestampEpochMicros")
        return NowPlaying(
            sourceAppId: app, title: title,
            artist: s["artist"] as? String ?? "", album: s["album"] as? String ?? "",
            isPlaying: s["playing"] as? Bool ?? false,
            elapsed: number("elapsedTimeMicros") / 1e6,
            timestamp: micros > 0 ? Date(timeIntervalSince1970: micros / 1e6) : nil,
            duration: number("durationMicros") / 1e6,
            artwork: (s["artworkData"] as? String).flatMap { Data(base64Encoded: $0) })
    }
}

/// The colour of a piece of album art, for tinting the card.
public enum DominantColor {
    /// The average of the pixels weighted by how colourful they are, so a grey border does not win.
    /// `rgba` is 4 bytes a pixel (alpha ignored). Nil for no pixels.
    public static func of(rgba: [UInt8]) -> (red: Double, green: Double, blue: Double)? {
        var sum = (r: 0.0, g: 0.0, b: 0.0), weight = 0.0
        for i in stride(from: 0, through: rgba.count - 4, by: 4) {
            let r = Double(rgba[i]), g = Double(rgba[i + 1]), b = Double(rgba[i + 2])
            let w = (max(r, g, b) - min(r, g, b)) / 255 + 0.02 // the floor keeps a fully grey cover from dividing by zero
            sum.r += r * w; sum.g += g * w; sum.b += b * w
            weight += w
        }
        guard weight > 0 else { return nil }
        return (sum.r / weight / 255, sum.g / weight / 255, sum.b / weight / 255)
    }
}
