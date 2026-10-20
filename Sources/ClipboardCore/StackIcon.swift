#if canImport(AppKit)
import AppKit

/// Draws the "Stack" app icon and its menu bar glyph in code, so the build needs no image assets.
public enum StackIcon {
    /// Full-color app icon following the macOS icon grid (an 824 pt squircle on a 1024 pt canvas).
    public static func appIcon(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            // The artwork is designed on a 100-unit grid whose squircle spans 4...96.
            let scale = size * (824.0 / 1024.0) / 92.0
            let origin = size * (100.0 / 1024.0) - 4 * scale
            func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
                NSRect(x: origin + x * scale, y: origin + y * scale, width: w * scale, height: h * scale)
            }

            let squircle = NSBezierPath(roundedRect: r(4, 4, 92, 92), xRadius: 22 * scale, yRadius: 22 * scale)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
            shadow.shadowOffset = NSSize(width: 0, height: -size * 0.01)
            shadow.shadowBlurRadius = size * 0.02
            shadow.set()
            NSColor(srgbRed: 0, green: 0.32, blue: 0.8, alpha: 1).setFill()
            squircle.fill()
            NSGraphicsContext.restoreGraphicsState()

            let top = NSColor(srgbRed: 0.227, green: 0.584, blue: 1, alpha: 1)
            let bottom = NSColor(srgbRed: 0, green: 0.322, blue: 0.8, alpha: 1)
            // Flipped context: 90° runs top to bottom.
            NSGradient(starting: top, ending: bottom)?.draw(in: squircle, angle: 90)

            func card(_ rect: NSRect, alpha: CGFloat) {
                NSColor.white.withAlphaComponent(alpha).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 7 * scale, yRadius: 7 * scale).fill()
            }
            card(r(36, 20, 44, 54), alpha: 0.3)
            card(r(31, 25, 44, 54), alpha: 0.55)
            card(r(24, 30, 46, 56), alpha: 1)

            let clip = NSBezierPath(roundedRect: r(35, 25, 24, 10), xRadius: 4 * scale, yRadius: 4 * scale)
            NSColor(srgbRed: 0.04, green: 0.373, blue: 0.839, alpha: 1).setFill()
            clip.fill()
            NSColor.white.setStroke()
            clip.lineWidth = 2.5 * scale
            clip.stroke()

            let lines = NSBezierPath()
            lines.lineWidth = 4 * scale
            lines.lineCapStyle = .round
            for (y, length) in [(48.0, 28.0), (57.0, 28.0), (66.0, 18.0)] {
                lines.move(to: NSPoint(x: origin + 33 * scale, y: origin + y * scale))
                lines.line(to: NSPoint(x: origin + (33 + length) * scale, y: origin + y * scale))
            }
            top.setStroke()
            lines.stroke()
            return true
        }
    }

    /// Monochrome template glyph for the menu bar: two overlapping outlined cards.
    public static func menuBarGlyph(pointSize: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: true) { _ in
            let s = pointSize / 24
            let back = NSBezierPath(roundedRect: NSRect(x: 9 * s, y: 3 * s, width: 11 * s, height: 14 * s), xRadius: 2 * s, yRadius: 2 * s)
            let front = NSBezierPath(roundedRect: NSRect(x: 4 * s, y: 7 * s, width: 11 * s, height: 14 * s), xRadius: 2 * s, yRadius: 2 * s)
            NSColor.black.setStroke()
            back.lineWidth = 1.6 * s
            back.stroke()
            // Knock out the part of the back card hidden behind the front one.
            NSGraphicsContext.current?.compositingOperation = .clear
            front.fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            front.lineWidth = 1.6 * s
            front.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
#endif
