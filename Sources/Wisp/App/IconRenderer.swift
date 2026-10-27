import AppKit
import SwiftUI

/// `Wisp --render-icon <folder.iconset>` draws the app icon from the mascot itself.
enum IconRenderer {
    struct IconView: View {
        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 185, style: .continuous)
                    .fill(LinearGradient(colors: [.hex("#232A52"), .hex("#07080F")], startPoint: .top, endPoint: .bottom))
                // A notch silhouette at the top, so the icon reads as "lives up there".
                IslandShape(top: 14, bottom: 38, floating: false)
                    .fill(Color.black)
                    .frame(width: 340, height: 78)
                    .frame(maxHeight: .infinity, alignment: .top)
                Circle().fill(Color.hex("#FF8A3D").opacity(0.4)).blur(radius: 70).frame(width: 420)
                    .offset(y: 50)
                Canvas { ctx, size in
                    MascotPainter(t: 0.4, rawTime: 10, mood: .happy, style: .flame, color: .hex("#FF8A3D")).draw(ctx, size)
                }
                .frame(width: 500, height: 500)
                .offset(y: 50)
            }
            .frame(width: 824, height: 824)
            .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous))
            .frame(width: 1024, height: 1024)
        }
    }

    @MainActor static func render(to folder: String) {
        let dir = URL(fileURLWithPath: folder)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let renderer = ImageRenderer(content: IconView())
        renderer.scale = 1
        guard let cg = renderer.cgImage else { print("render failed"); return }
        let full = NSImage(cgImage: cg, size: NSSize(width: 1024, height: 1024))
        if let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
            try? png.write(to: dir.deletingLastPathComponent().appendingPathComponent("icon-1024.png"))
        }
        for s in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let px = s * scale
                guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                 bytesPerRow: 0, bitsPerPixel: 0) else { continue }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                NSGraphicsContext.current?.imageInterpolation = .high
                full.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
                NSGraphicsContext.restoreGraphicsState()
                let name = scale == 1 ? "icon_\(s)x\(s).png" : "icon_\(s)x\(s)@2x.png"
                try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name))
            }
        }
    }
}
