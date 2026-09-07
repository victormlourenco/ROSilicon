// Draws AppIcon.icns for the launcher. Run by build.sh; no assets needed.
//   swift makeicon.swift <output.icns>
import AppKit

let output = CommandLine.arguments.count > 1
    ? URL(filePath: CommandLine.arguments[1])
    : URL(filePath: "AppIcon.icns")

/// One icon face, drawn fresh at each size so small ones stay sharp.
func draw(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    NSGraphicsContext.current?.imageInterpolation = .high
    let inset = size * 0.09
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22)

    NSGradient(colors: [
        NSColor(srgbRed: 0.16, green: 0.20, blue: 0.42, alpha: 1),
        NSColor(srgbRed: 0.35, green: 0.20, blue: 0.52, alpha: 1),
        NSColor(srgbRed: 0.62, green: 0.26, blue: 0.42, alpha: 1),
    ])?.draw(in: squircle, angle: -80)

    // A soft highlight across the top, the way macOS icons catch light.
    squircle.setClip()
    NSGradient(
        starting: NSColor(white: 1, alpha: 0.22),
        ending: NSColor(white: 1, alpha: 0)
    )?.draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2),
            angle: -90)

    let text = "RO" as NSString
    let fontSize = size * 0.38
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
        .foregroundColor: NSColor(white: 1, alpha: 0.96),
        .kern: fontSize * 0.02,
    ]
    let bounds = text.size(withAttributes: attributes)
    text.draw(
        at: NSPoint(x: rect.midX - bounds.width / 2, y: rect.midY - bounds.height * 0.42),
        withAttributes: attributes)

    // A thin gold rule under the wordmark.
    let rule = NSBezierPath(roundedRect: NSRect(
        x: rect.midX - rect.width * 0.18, y: rect.minY + rect.height * 0.22,
        width: rect.width * 0.36, height: max(1, size * 0.018)),
        xRadius: size * 0.01, yRadius: size * 0.01)
    NSColor(srgbRed: 0.98, green: 0.80, blue: 0.36, alpha: 0.95).setFill()
    rule.fill()

    return image
}

func png(_ image: NSImage, _ pixels: Int) throws -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        struct EncodeFailed: Error {}
        throw EncodeFailed()
    }
    return data
}

let iconset = URL(filePath: NSTemporaryDirectory())
    .appending(path: "ROLatamIcon-\(UUID().uuidString.prefix(6)).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try png(draw(size: CGFloat(pixels)), pixels).write(to: iconset.appending(path: name))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(filePath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
exit(iconutil.terminationStatus)
