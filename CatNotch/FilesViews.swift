import AppKit
import QuickLookThumbnailing
import SwiftUI
import CatNotchCore

/// A picture of the file itself where macOS has one (image, video frame, PDF page), else its icon.
private struct FileThumb: View {
    let url: URL?
    let side: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else if let url { Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit() }
            else { Image(systemName: "questionmark.square.dashed").resizable().scaledToFit().foregroundStyle(.white.opacity(0.5)) }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: url) {
            guard let url else { image = nil; return }
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side), scale: 2, representationTypes: .thumbnail)
            image = (try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request))?.nsImage
        }
    }
}

/// A file you can open (click), drag into another app, and act on from its menu. A missing file shows dimmed and does nothing.
/// With `onRemove`, a cross on its corner appears on hover (the Electron shelf's chip) and grows when pointed at, like the tile.
private struct FileTile<Menu: View>: View {
    let url: URL?
    let name: String
    var onRemove: (() -> Void)?
    @ViewBuilder let menu: Menu
    @State private var hovering = false
    @State private var overCross = false

    var body: some View {
        let tile = VStack(spacing: 5) {
            FileThumb(url: url, side: 52)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.14)))
                .overlay(alignment: .topTrailing) {
                    if let onRemove, hovering {
                        Button(action: onRemove) {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(overCross ? 1 : 0.85))
                                .frame(width: 17, height: 17).background(Circle().fill(Color(white: overCross ? 0.28 : 0.17)))
                                .overlay(Circle().strokeBorder(.white.opacity(0.14)))
                                .scaleEffect(overCross ? 1.15 : 1)
                        }
                        .buttonStyle(.plain).onHover { overCross = $0 }.pointerCursor()
                        .animation(.spring(duration: 0.25), value: overCross).offset(x: 6, y: -6).accessibilityLabel("Remove \(name)")
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                    }
                }
            Text(name).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                .lineLimit(1).truncationMode(.middle).frame(width: 70)
        }
        .frame(width: 74)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(hovering && url != nil ? 0.08 : 0)).padding(.horizontal, -2).padding(.vertical, -4))
        .scaleEffect(hovering && url != nil ? 1.05 : 1)
        .animation(.spring(duration: 0.25), value: hovering)
        .opacity(url == nil ? 0.4 : 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(url == nil ? "\(name) can't be found" : "\(name)\nClick to open, drag out to use it elsewhere")
        .contextMenu { menu }
        if let url {
            tile
                .onTapGesture { NSWorkspace.shared.open(url) }
                .pointerCursor()
                .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() } // the real file, so any app can take it
        } else {
            tile
        }
    }
}

/// The shelf, after the Electron one: a dashed well you drop onto. Empty it says so; with files they sit left to right
/// (newest at the end, scrolled into view) with a clear-all beside them. The well lights up while a file is on its way.
private struct ShelfWell: View {
    @Environment(\.companionAccent) private var accent
    let shelf: ShelfModel
    let lit: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        HStack(spacing: 8) {
            if shelf.entries.isEmpty {
                VStack(spacing: 5) {
                    Image(systemName: lit ? "arrow.down.circle.fill" : "arrow.down.to.line").font(.system(size: 18, weight: .medium))
                        .foregroundStyle(lit ? accent : .white.opacity(0.35)).symbolEffect(.bounce, value: lit)
                    Text(lit ? "Drop to keep it here" : "Drop files here").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(lit ? 1 : 0.4))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(shelf.entries) { entry in
                                FileTile(url: entry.url, name: entry.name, onRemove: { shelf.remove(entry) }) {
                                    if let url = entry.url { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                                    Button("Remove from Shelf") { shelf.remove(entry) }
                                }
                                .id(entry.id)
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                            }
                        }
                        .padding(.horizontal, 4).padding(.vertical, 10) // room for the cross, which sits past the thumbnail's corner
                        .frame(maxHeight: .infinity)
                    }
                    .scrollIndicators(.never)
                    .onChange(of: shelf.entries.last?.id) { _, last in
                        if let last { withAnimation { proxy.scrollTo(last, anchor: .trailing) } }
                    }
                }
                .mask(HStack(spacing: 0) { // fades at the edges once there is more than fits
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: 10)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 10)
                })
                if shelf.entries.count > 1 {
                    VStack(spacing: 4) {
                        Button { withAnimation(.spring(duration: 0.3)) { shelf.clear() } } label: {
                            Image(systemName: "trash").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                                .frame(width: 28, height: 28).background(Circle().fill(.white.opacity(0.08)))
                        }
                        .buttonStyle(.lively).help("Clear all").accessibilityLabel("Clear the shelf")
                        Text("\(shelf.entries.count)").font(.system(size: 10, weight: .semibold).monospacedDigit()).foregroundStyle(.white.opacity(0.4))
                    }
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(accent.opacity(lit ? 0.14 : 0)))
        // Grey dashes at rest, the accent while a file is on its way in.
        .overlay(shape.strokeBorder(lit ? accent.opacity(0.85) : .white.opacity(0.18), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        .animation(.spring(duration: 0.3), value: shelf.entries.map(\.id))
        .animation(.easeOut(duration: 0.2), value: lit)
    }
}

/// The newest screenshots, on a quiet card beside the shelf.
private struct ScreenshotsCard: View {
    let shelf: ShelfModel
    let screenshots: ScreenshotModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Screenshots", systemImage: "camera.viewfinder").font(.system(size: 10, weight: .semibold)).tracking(0.4)
                .foregroundStyle(.white.opacity(0.5))
            if screenshots.items.isEmpty {
                Text("No screenshots yet").font(.system(size: 12)).foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(screenshots.items, id: \.self) { url in
                            FileTile(url: url, name: url.deletingPathExtension().lastPathComponent, onRemove: { screenshots.hide(url) }) {
                                Button("Keep on Shelf") { shelf.add([url]) }
                                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                Button("Remove from List") { screenshots.hide(url) }
                                Button("Move to Trash", role: .destructive) { screenshots.trash(url) }
                            }
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 6).padding(.vertical, 10) // room for the cross, which sits past the thumbnail's corner
                }
                .animation(.spring(duration: 0.3), value: screenshots.items)
                .scrollIndicators(.never)
            }
        }
        .padding(10)
        .frame(width: 216, alignment: .topLeading).frame(maxHeight: .infinity)
        .background {
            let card = RoundedRectangle(cornerRadius: 18, style: .continuous)
            card.fill(.white.opacity(0.06)).overlay(card.strokeBorder(.white.opacity(0.1)))
        }
    }
}

/// The Files view: the shelf you drop onto, and the newest screenshots.
struct FilesPage: View {
    let shelf: ShelfModel
    let screenshots: ScreenshotModel
    /// A file is over the Notch, or being dragged toward it.
    let targeted: Bool

    var body: some View {
        HStack(spacing: NotchLayout.gap) {
            ShelfWell(shelf: shelf, lit: targeted)
            ScreenshotsCard(shelf: shelf, screenshots: screenshots)
        }
        .frame(width: NotchLayout.filesContent.width, height: NotchLayout.filesContent.height)
        .onAppear { shelf.refresh() }
    }
}
