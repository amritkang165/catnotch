import AVFoundation
import AppKit
import CatNotchCore
import CoreImage
import SwiftUI

/// The ambient glow: `loopbg.mp4` looping along the bottom of the open Notch while music plays, in an `AVPlayerLayer`.
/// A Core Image pass turns its hue towards the companion's colour. The layer is screen blended and faded upward, so
/// only the video's light lands on the Notch (its black is no rectangle). Make it only while it should play: leaving
/// the screen stops the player, so a hidden glow costs nothing.
struct AmbientVideo: NSViewRepresentable {
    let shift: AmbientShift

    func makeNSView(context: Context) -> PlayerView { PlayerView() }

    func updateNSView(_ view: PlayerView, context: Context) { view.shift = shift }

    static func dismantleNSView(_ view: PlayerView, coordinator: ()) { view.stop() }

    final class PlayerView: NSView {
        private let player = AVPlayer()
        private let playerLayer = AVPlayerLayer()
        private var ended: NSObjectProtocol?
        private var applied: AmbientShift?
        var shift = AmbientShift(accent: nil) { didSet { if shift != oldValue { grade() } } }

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true // layer-backed, not layer-hosting: AppKit sizes the root layer that carries the blend, the opacity and the fade
            guard let url = Bundle.main.url(forResource: "loopbg", withExtension: "mp4") else { return } // no file: no glow
            player.replaceCurrentItem(with: AVPlayerItem(asset: AVURLAsset(url: url)))
            player.isMuted = true
            player.actionAtItemEnd = .none
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspectFill
            // Screen keeps the video's black transparent; the opacity and the fade are the Electron app's.
            layer?.compositingFilter = "screenBlendMode"
            layer?.opacity = 0.32
            layer?.addSublayer(playerLayer)
            let fade = CAGradientLayer()
            fade.colors = [NSColor.black.cgColor, NSColor.black.withAlphaComponent(0.6).cgColor, NSColor.clear.cgColor]
            fade.locations = [0, 0.45, 1]
            fade.startPoint = CGPoint(x: 0, y: 0) // layer coordinates run up: opaque at the bottom
            fade.endPoint = CGPoint(x: 0, y: 1)
            layer?.mask = fade
            ended = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: player.currentItem, queue: .main) { [player] _ in
                player.seek(to: .zero)
                player.play()
            }
            grade()
            player.play()
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            playerLayer.frame = bounds
            layer?.mask?.frame = bounds
        }

        func stop() {
            player.pause()
            player.replaceCurrentItem(with: nil)
            if let ended { NotificationCenter.default.removeObserver(ended) }
        }

        /// The CSS filter chain of the Electron app, in Core Image: hue turn, saturation, a touch dimmer, more contrast.
        private func grade() {
            guard shift != applied, let item = player.currentItem else { return }
            applied = shift
            let angle = Double(shift.rotate) * .pi / 180, saturation = shift.saturation
            item.videoComposition = AVVideoComposition(asset: item.asset) { request in
                let image = request.sourceImage.clampedToExtent()
                    .applyingFilter("CIHueAdjust", parameters: [kCIInputAngleKey: angle])
                    .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: saturation])
                    .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: log2(0.95)])
                    .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.1])
                    .cropped(to: request.sourceImage.extent)
                request.finish(with: image, context: nil)
            }
        }
    }
}
