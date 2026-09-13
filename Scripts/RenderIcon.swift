import AppKit

// Renders the Yakitori app icon into an .iconset directory.
// Usage: swift RenderIcon.swift <output-iconset-dir>

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: RenderIcon.swift <iconset-dir>\n".utf8))
    exit(1)
}

let outputDirectory = URL(fileURLWithPath: arguments[1])
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let ember = NSColor(srgbRed: 0.93, green: 0.33, blue: 0.15, alpha: 1)
let gold = NSColor(srgbRed: 0.98, green: 0.70, blue: 0.25, alpha: 1)

func render(pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: pixels, height: pixels)
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    let size = CGFloat(pixels)
    let inset = size * 0.098
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = rect.width * 0.2237
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSGradient(starting: ember, ending: gold)?.draw(in: path, angle: -55)

    NSColor.white.withAlphaComponent(0.18).setStroke()
    path.lineWidth = max(1, size * 0.006)
    path.stroke()

    let symbolSize = size * 0.52
    let configuration = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .bold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    let target = NSRect(
        x: (size - symbolSize) / 2,
        y: (size - symbolSize) / 2,
        width: symbolSize,
        height: symbolSize
    )

    if let flame = NSImage(systemSymbolName: "flame.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) {
        flame.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
    } else {
        let text = "Y" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size * 0.5, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: (size - textSize.width) / 2, y: (size - textSize.height) / 2),
            withAttributes: attributes
        )
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let entries: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for entry in entries {
    guard let data = render(pixels: entry.pixels) else { continue }
    try? data.write(to: outputDirectory.appendingPathComponent(entry.name))
}

print("Wrote iconset to \(outputDirectory.path)")
