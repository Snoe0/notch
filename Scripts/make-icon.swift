// Renders AppIcon.icns from code, so the icon is reproducible and reviewable
// as source rather than an opaque binary checked into the repo.
//
//   swift Scripts/make-icon.swift
//
// Design: a warm paper card with the notch bitten out of its top edge, and
// three note lines below. At 16pt the lines disappear but the notch silhouette
// still reads, which is the whole point of the shape.

import AppKit
import Foundation

let canvas: CGFloat = 1024
let inset: CGFloat = 100
let cardRadius: CGFloat = 185

let notchWidth: CGFloat = 300
let notchHeight: CGFloat = 108
let notchRadius: CGFloat = 54

/// Convert a top-down y (design space) to CoreGraphics' bottom-up y.
func flip(_ yFromTop: CGFloat, height: CGFloat) -> CGFloat {
    canvas - yFromTop - height
}

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// A rect with independently rounded top and bottom corners.
func lozenge(_ rect: CGRect, topRadius: CGFloat, bottomRadius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.minX, y: rect.maxY - topRadius))
    path.addArc(
        tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
        tangent2End: CGPoint(x: rect.maxX, y: rect.maxY),
        radius: topRadius
    )
    path.addArc(
        tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
        tangent2End: CGPoint(x: rect.maxX, y: rect.minY),
        radius: topRadius
    )
    path.addArc(
        tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
        tangent2End: CGPoint(x: rect.minX, y: rect.minY),
        radius: bottomRadius
    )
    path.addArc(
        tangent1End: CGPoint(x: rect.minX, y: rect.minY),
        tangent2End: CGPoint(x: rect.minX, y: rect.maxY),
        radius: bottomRadius
    )
    path.closeSubpath()
    return path
}

func drawIcon(into ctx: CGContext) {
    ctx.setShouldAntialias(true)
    let card = CGRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
    let cardPath = CGPath(
        roundedRect: card, cornerWidth: cardRadius, cornerHeight: cardRadius, transform: nil
    )

    // Warm paper gradient.
    ctx.saveGState()
    ctx.addPath(cardPath)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(0xFDFBF5), color(0xEBE4D6)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: card.maxY),
        end: CGPoint(x: 0, y: card.minY),
        options: []
    )
    ctx.restoreGState()

    // The notch, hanging from the card's top edge.
    let notch = CGRect(
        x: (canvas - notchWidth) / 2,
        y: flip(inset, height: notchHeight),
        width: notchWidth,
        height: notchHeight
    )
    ctx.saveGState()
    ctx.addPath(cardPath)          // keep the notch inside the card's corners
    ctx.clip()
    ctx.addPath(lozenge(notch, topRadius: 0, bottomRadius: notchRadius))
    ctx.setFillColor(color(0x0B0B0C))
    ctx.fillPath()
    ctx.restoreGState()

    // Three note lines, shortening as they go.
    let lines: [(y: CGFloat, width: CGFloat, alpha: CGFloat)] = [
        (395, 500, 0.88),
        (520, 500, 0.66),
        (645, 300, 0.44),
    ]
    let lineHeight: CGFloat = 52
    for line in lines {
        let bar = CGRect(
            x: (canvas - line.width) / 2,
            y: flip(line.y, height: lineHeight),
            width: line.width,
            height: lineHeight
        )
        ctx.addPath(
            CGPath(
                roundedRect: bar,
                cornerWidth: lineHeight / 2,
                cornerHeight: lineHeight / 2,
                transform: nil
            )
        )
        ctx.setFillColor(color(0x2C2C2E, alpha: line.alpha))
        ctx.fillPath()
    }
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    let ctx = context.cgContext
    let scale = CGFloat(pixels) / canvas
    ctx.scaleBy(x: scale, y: scale)
    drawIcon(into: ctx)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: "build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// (base point size, scale) → the filenames iconutil expects.
let variants: [(base: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1),
    (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

for variant in variants {
    let suffix = variant.scale == 1 ? "" : "@2x"
    let name = "icon_\(variant.base)x\(variant.base)\(suffix).png"
    let data = render(pixels: variant.base * variant.scale)
    try data.write(to: iconset.appending(path: name))
}

print("wrote \(variants.count) sizes to \(iconset.path)")
