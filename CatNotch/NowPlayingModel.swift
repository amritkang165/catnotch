import AppKit
import ImageIO
import Observation
import SwiftUI
import CatNotchCore

/// What is playing, for the Notch on every display. It runs the vendored mediaremote-adapter under Apple's
/// own /usr/bin/perl (the one thing still allowed to read MediaRemote) and only reads its JSON lines.
/// No adapter, or one that keeps crashing, leaves `current` nil and the rest of the app untouched.
@MainActor @Observable
final class NowPlayingModel {
    private(set) var current: NowPlaying?
    /// The album art, shrunk once per track (players can hand over a 4K cover).
    private(set) var art: NSImage?
    /// The art's dominant colour, for tinting the card.
    private(set) var tint = Color.gray

    var isPlaying: Bool { current?.isPlaying ?? false }
    /// A track is loaded and, if paused, not for so long that it is stale (spec 0036). The card and the closed art follow this.
    var hasTrack: Bool { current != nil && !expired }
    private var expired = false
    private var pauseTimer: Task<Void, Never>?
    private static let pauseTimeout: Duration = .seconds(30 * 60)

    private var stream = NowPlayingStream()
    private var process: Process?
    private var crashes = 0
    private var stopped = false
    private var artSource: Data?

    private static let perl = URL(fileURLWithPath: "/usr/bin/perl")
    private static let dir = Bundle.main.resourceURL?.appendingPathComponent("mediaremote")
    private static let script = dir?.appendingPathComponent("mediaremote-adapter.pl")
    private static let framework = dir?.appendingPathComponent("MediaRemoteAdapter.framework")
    private static let maxCrashes = 3

    init() {
        // Lives as long as the app; the adapter must not outlive it.
        _ = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        start()
    }

    func send(_ key: Transport) {
        guard let command = adapter("send", String(key.rawValue)) else { return }
        try? command.run() // the stream reports the result
    }

    /// Jumps to `seconds`. The bar moves at once; the stream confirms a moment later.
    func seek(to seconds: TimeInterval) {
        guard let command = adapter("seek", String(Int(max(0, seconds) * 1_000_000))) else { return }
        try? command.run()
        current?.elapsed = seconds
        current?.timestamp = Date()
    }

    func stop() {
        stopped = true
        process?.terminate()
    }

    private func adapter(_ arguments: String...) -> Process? {
        guard let script = Self.script, let framework = Self.framework,
              FileManager.default.fileExists(atPath: script.path) else { return nil }
        let p = Process()
        p.executableURL = Self.perl
        p.arguments = [script.path, framework.path] + arguments
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        return p
    }

    private func start() {
        guard !stopped, let p = adapter("stream", "--micros", "--debounce=100") else { return }
        let pipe = Pipe()
        p.standardOutput = pipe
        guard (try? p.run()) != nil else { return }
        process = p
        Task {
            // The lines end when the adapter exits, whether it crashed or was stopped.
            do { for try await line in pipe.fileHandleForReading.bytes.lines { feed(line) } } catch {}
            ended(p)
        }
    }

    private func ended(_ p: Process) {
        guard process === p else { return }
        process = nil
        stream.reset()
        publish()
        crashes += 1
        guard !stopped, crashes <= Self.maxCrashes else { return }
        Task {
            try? await Task.sleep(for: .seconds(1))
            start()
        }
    }

    private func feed(_ line: String) {
        if stream.feed(line) { publish() }
    }

    private func publish() {
        let next = stream.current
        if next?.title != current?.title { pauseTimer?.cancel(); pauseTimer = nil; expired = false } // a new track starts its own wait
        if next != current { current = next }
        if next == nil || next?.isPlaying == true { pauseTimer?.cancel(); pauseTimer = nil; expired = false }
        else if pauseTimer == nil { // paused: gone after the timeout, unless it plays again first
            pauseTimer = Task { [weak self] in
                try? await Task.sleep(for: Self.pauseTimeout)
                guard !Task.isCancelled else { return }
                self?.expired = true
            }
        }
        let source = next?.artwork
        guard source != artSource else { return }
        artSource = source
        (art, tint) = source.flatMap(Self.decode) ?? (nil, .gray)
    }

    /// The art at most 256 px, and its colour read from a 16 px copy.
    private static func decode(_ data: Data) -> (NSImage, Color)? {
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 256,
                       kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        var pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
                .draw(image, in: CGRect(x: 0, y: 0, width: 16, height: 16)) != nil
        }
        let colour = drawn ? DominantColor.of(rgba: pixels).map { Color(red: $0.red, green: $0.green, blue: $0.blue) } : nil
        return (NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)), colour ?? .gray)
    }
}
