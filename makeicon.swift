// Draws ROSilicon.icns for the launcher. Run by build.sh.
//   swift makeicon.swift <output.icns> [ROSilicon.icon]
//
// macOS 26 does not use this: it reads ROSilicon.icon, which build.sh compiles
// to an asset catalogue, and draws the shape, the shadow and the specular
// itself. This draws the icon macOS 14 through 25 read. Both come from the same
// artwork — the layer named in ROSilicon.icon/icon.json — so the two never
// drift apart. Large faces are that creature on a squircle drawn here; the 16-
// and 32-pixel faces are the wordmark instead, because at that size the
// creature is a pink smudge and the letters are still readable.
import AppKit

let output = CommandLine.arguments.count > 1
    ? URL(filePath: CommandLine.arguments[1])
    : URL(filePath: "ROSilicon.icns")

// Beside this script, not beside the caller: build.sh runs it from anywhere.
let document = CommandLine.arguments.count > 2
    ? URL(filePath: CommandLine.arguments[2])
    : URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "ROSilicon.icon")

/// Faces this size and under are the wordmark; larger ones are the creature.
/// At 64 pixels it still shows its eyes, the chip and the traces; at 32 it has
/// lost all three.
let wordmarkCeiling = 32

/// Under this, the creature is drawn larger so the face and the chip keep some
/// pixels. Cropping the antenna away would buy more room, but the cut lands in
/// the top of the head and leaves the stalk as a stub, so it stays.
let compactCeiling = 96

/// How much of the shape the creature is asked to fill. What it gets may be
/// less: see `Subject.ceiling`.
let compactFill: CGFloat = 0.84
let fullFill: CGFloat = 0.78

/// Apple's icon grid: the shape fills 824 of a 1024 canvas, and its corners are
/// rounded by 22.37% of its own width.
let insetFraction: CGFloat = 100.0 / 1024.0
let cornerFraction: CGFloat = 0.2237

/// The artwork, cropped to what is painted, with the two numbers the layout
/// needs. Both are measured rather than written down, so replacing the layer in
/// Icon Composer is enough — nothing here has to be re-tuned by hand.
struct Subject {
    let image: NSImage
    /// The antenna is a narrow stalk above the body, so the middle of the crop
    /// is not the middle of the creature. Centring the crop hangs the body low
    /// and drives its base into the curve of the shape; lifting the drawing by
    /// this fraction of its height puts the body back in the middle.
    let rise: CGFloat
    /// The most of the shape the creature can fill before a body lifted by
    /// `rise` pushes the antenna out through the top edge.
    var ceiling: CGFloat { 1 / (1 + 2 * rise) }
}

/// The layer image, as icon.json names it. Only the first layer is read: the
/// document is one creature on a fill, and that is the creature.
func layerURL(in document: URL) throws -> URL {
    struct NoLayer: Error {}
    let manifest = try JSONSerialization.jsonObject(
        with: try Data(contentsOf: document.appending(path: "icon.json")))
    guard let root = manifest as? [String: Any],
          let groups = root["groups"] as? [[String: Any]],
          let layers = groups.first?["layers"] as? [[String: Any]],
          let name = layers.first?["image-name"] as? String
    else { throw NoLayer() }
    return document.appending(path: "Assets").appending(path: name)
}

func loadSubject(_ url: URL) throws -> Subject {
    struct NotAnImage: Error {}
    guard let loaded = NSImage(contentsOf: url) else { throw NotAnImage() }
    let W = Int(loaded.size.width), H = Int(loaded.size.height)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: W * 4, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    loaded.draw(in: NSRect(x: 0, y: 0, width: W, height: H))
    NSGraphicsContext.restoreGraphicsState()
    let px = rep.bitmapData!

    // One pass, top-down: the painted rows, and the wide ones that are the body
    // rather than the antenna.
    var minX = W, maxX = -1, minY = H, maxY = -1, bodyMinY = H, bodyMaxY = -1
    for y in 0..<H {
        var lo = -1, hi = -1
        for x in 0..<W where px[(y * W + x) * 4 + 3] > 8 {
            if lo < 0 { lo = x }
            hi = x
        }
        guard lo >= 0 else { continue }
        if lo < minX { minX = lo }
        if hi > maxX { maxX = hi }
        if y < minY { minY = y }
        if y > maxY { maxY = y }
        if hi - lo + 1 > W / 2 {
            if y < bodyMinY { bodyMinY = y }
            if y > bodyMaxY { bodyMaxY = y }
        }
    }
    guard maxX >= minX, maxY >= minY else { throw NotAnImage() }

    let crop = NSRect(x: CGFloat(minX), y: CGFloat(H - 1 - maxY),
                      width: CGFloat(maxX - minX + 1), height: CGFloat(maxY - minY + 1))
    let cropped = NSImage(size: crop.size)
    cropped.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    rep.draw(in: NSRect(origin: .zero, size: crop.size), from: crop,
             operation: .copy, fraction: 1, respectFlipped: false, hints: nil)
    cropped.unlockFocus()

    var rise: CGFloat = 0
    if bodyMaxY >= bodyMinY {
        let bodyCentre = CGFloat(bodyMinY + bodyMaxY) / 2
        let cropCentre = CGFloat(minY + maxY) / 2
        rise = (bodyCentre - cropCentre) / crop.height   // both top-down
    }
    return Subject(image: cropped, rise: max(0, rise))
}

let subject: Subject? = {
    do { return try loadSubject(try layerURL(in: document)) } catch {
        FileHandle.standardError.write(
            Data("warning: no artwork in \(document.path); drawing every face\n".utf8))
        return nil
    }
}()

/// The rounded square every face is built in.
func squircle(in rect: NSRect) -> NSBezierPath {
    let radius = rect.width * cornerFraction
    return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func paintBackground(_ rect: NSRect, size: CGFloat) {
    let shape = squircle(in: rect)
    // Magenta at the top down to indigo at the foot: the creature is pink, and
    // it needs the dark end of the gradient under it to keep its edge.
    NSGradient(colors: [
        NSColor(srgbRed: 0.62, green: 0.26, blue: 0.42, alpha: 1),
        NSColor(srgbRed: 0.35, green: 0.20, blue: 0.52, alpha: 1),
        NSColor(srgbRed: 0.16, green: 0.20, blue: 0.42, alpha: 1),
    ])?.draw(in: shape, angle: -80)

    NSGraphicsContext.saveGraphicsState()
    shape.setClip()

    // Stars, but only where there are pixels to hold them. Seeded, so two
    // builds of the same commit produce the same icon.
    if size >= 128 {
        var seed: UInt64 = 0x5D1C0
        func random() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 33) % 100_000) / 100_000
        }
        for _ in 0..<70 {
            let star = NSRect(x: rect.minX + random() * rect.width,
                              y: rect.minY + random() * rect.height,
                              width: size * 0.004, height: size * 0.004)
            let fade = (star.midY - rect.minY) / rect.height
            NSColor(white: 1, alpha: 0.10 + 0.45 * fade * random()).setFill()
            NSBezierPath(ovalIn: star).fill()
        }
    }

    // A warm glow where the creature sits, so it is lit rather than pasted on.
    NSGradient(starting: NSColor(srgbRed: 1, green: 0.62, blue: 0.55, alpha: 0.30),
               ending: NSColor(srgbRed: 1, green: 0.62, blue: 0.55, alpha: 0))?
        .draw(fromCenter: NSPoint(x: rect.midX, y: rect.midY - rect.height * 0.02),
              radius: 0,
              toCenter: NSPoint(x: rect.midX, y: rect.midY - rect.height * 0.02),
              radius: rect.width * 0.52, options: [])

    // A soft highlight across the top, the way macOS icons catch light.
    NSGradient(starting: NSColor(white: 1, alpha: 0.20), ending: NSColor(white: 1, alpha: 0))?
        .draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2),
              angle: -90)
    NSGraphicsContext.restoreGraphicsState()
}

/// The creature on the squircle. Drawn fresh at each size so it stays sharp.
func drawIllustration(size: CGFloat, subject: Subject, compact: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }
    NSGraphicsContext.current?.imageInterpolation = .high

    let inset = size * insetFraction
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    paintBackground(rect, size: size)

    let fill = min(compact ? compactFill : fullFill, subject.ceiling)
    let art = subject.image
    let scale = min(rect.width * fill / art.size.width, rect.height * fill / art.size.height)
    let drawn = NSSize(width: art.size.width * scale, height: art.size.height * scale)

    NSGraphicsContext.saveGraphicsState()
    squircle(in: rect).setClip()
    art.draw(in: NSRect(x: rect.midX - drawn.width / 2,
                        y: rect.midY - drawn.height / 2 + drawn.height * subject.rise,
                        width: drawn.width, height: drawn.height))
    NSGraphicsContext.restoreGraphicsState()
    return image
}

/// The wordmark, for faces too small to hold the creature.
func drawWordmark(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }
    NSGraphicsContext.current?.imageInterpolation = .high

    let inset = size * insetFraction
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    paintBackground(rect, size: size)

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

    // A thin gold rule under the wordmark, echoing the chip's traces.
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
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        struct EncodeFailed: Error {}
        throw EncodeFailed()
    }
    return data
}

func face(_ pixels: Int) -> NSImage {
    if pixels > wordmarkCeiling, let subject {
        return drawIllustration(size: CGFloat(pixels), subject: subject,
                                compact: pixels <= compactCeiling)
    }
    return drawWordmark(size: CGFloat(pixels))
}

let iconset = URL(filePath: NSTemporaryDirectory())
    .appending(path: "ROSiliconIcon-\(UUID().uuidString.prefix(6)).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try png(face(pixels), pixels).write(to: iconset.appending(path: name))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(filePath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
exit(iconutil.terminationStatus)
