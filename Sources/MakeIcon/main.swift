import AppKit
import ClipboardCore

// Renders the app icon into an .iconset folder for `iconutil`.
// Usage: make-icon <output>.iconset

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: make-icon <output>.iconset\n".data(using: .utf8)!)
    exit(1)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let image = StackIcon.appIcon(size: CGFloat(pixels))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { exit(1) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let file = output.appendingPathComponent("icon_\(base)x\(base)\(suffix).png")
        try rep.representation(using: .png, properties: [:])!.write(to: file)
    }
}
