// Draws the app icon: swift scripts/make-icon.swift <output.png>
// A clothes hanger (fashion) with a ringing bell badge (stock alert).
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let rgb = CGColorSpaceCreateDeviceRGB()

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

// Background: warm sand to soft clay, like a boutique bag.
let bg = CGGradient(colorsSpace: rgb, colors: [color(246, 236, 222).cgColor, color(222, 200, 176).cgColor] as CFArray,
                    locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

let ink = color(32, 30, 34)

// Hanger hook.
let hook = NSBezierPath()
hook.move(to: CGPoint(x: 470, y: 600))
hook.line(to: CGPoint(x: 470, y: 640))
hook.curve(to: CGPoint(x: 470, y: 820), controlPoint1: CGPoint(x: 470, y: 700), controlPoint2: CGPoint(x: 380, y: 760))
hook.curve(to: CGPoint(x: 580, y: 760), controlPoint1: CGPoint(x: 540, y: 880), controlPoint2: CGPoint(x: 600, y: 820))
hook.lineWidth = 40
hook.lineCapStyle = .round
hook.lineJoinStyle = .round
ink.setStroke()
hook.stroke()

// Hanger body: two shoulders and the bottom bar.
let body = NSBezierPath()
body.move(to: CGPoint(x: 470, y: 600))
body.line(to: CGPoint(x: 150, y: 330))
body.curve(to: CGPoint(x: 200, y: 270), controlPoint1: CGPoint(x: 120, y: 300), controlPoint2: CGPoint(x: 150, y: 270))
body.line(to: CGPoint(x: 740, y: 270))
body.curve(to: CGPoint(x: 790, y: 330), controlPoint1: CGPoint(x: 790, y: 270), controlPoint2: CGPoint(x: 820, y: 300))
body.line(to: CGPoint(x: 470, y: 600))
body.lineWidth = 46
body.lineCapStyle = .round
body.lineJoinStyle = .round
body.stroke()

// Bell badge, top right.
let center = CGPoint(x: 770, y: 760)
let badgeR: CGFloat = 170
color(246, 236, 222).setFill()
NSBezierPath(ovalIn: CGRect(x: center.x - badgeR - 22, y: center.y - badgeR - 22, width: (badgeR + 22) * 2, height: (badgeR + 22) * 2)).fill()
let badgeGrad = CGGradient(colorsSpace: rgb, colors: [color(255, 98, 72).cgColor, color(226, 52, 60).cgColor] as CFArray,
                           locations: [0, 1])!
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: center.x - badgeR, y: center.y - badgeR, width: badgeR * 2, height: badgeR * 2))
ctx.clip()
ctx.drawLinearGradient(badgeGrad, start: CGPoint(x: center.x, y: center.y + badgeR), end: CGPoint(x: center.x, y: center.y - badgeR), options: [])
ctx.restoreGState()

// Bell glyph.
let bell = NSBezierPath()
let bx = center.x, by = center.y - 10
bell.move(to: CGPoint(x: bx - 85, y: by - 50))
bell.line(to: CGPoint(x: bx + 85, y: by - 50))
bell.curve(to: CGPoint(x: bx + 62, y: by - 10), controlPoint1: CGPoint(x: bx + 85, y: by - 35), controlPoint2: CGPoint(x: bx + 62, y: by - 30))
bell.line(to: CGPoint(x: bx + 62, y: by + 30))
bell.curve(to: CGPoint(x: bx - 62, y: by + 30), controlPoint1: CGPoint(x: bx + 62, y: by + 110), controlPoint2: CGPoint(x: bx - 62, y: by + 110))
bell.line(to: CGPoint(x: bx - 62, y: by - 10))
bell.curve(to: CGPoint(x: bx - 85, y: by - 50), controlPoint1: CGPoint(x: bx - 62, y: by - 30), controlPoint2: CGPoint(x: bx - 85, y: by - 35))
bell.close()
NSColor.white.setFill()
bell.fill()
NSBezierPath(ovalIn: CGRect(x: bx - 24, y: by - 90, width: 48, height: 40)).fill()
NSBezierPath(ovalIn: CGRect(x: bx - 13, y: by + 88, width: 26, height: 26)).fill()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
