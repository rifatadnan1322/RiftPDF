import AppKit
import CoreGraphics
import Foundation

// RiftPDF mark: a red disc, an open book, an exploded pie chart on the left
// page and handwriting on the right.

let INK    = CGColor(red: 0.169, green: 0.204, blue: 0.251, alpha: 1)
let INK2   = CGColor(red: 0.451, green: 0.498, blue: 0.557, alpha: 1)
let ACCENT = CGColor(red: 0.851, green: 0.271, blue: 0.243, alpha: 1)
let PAPER  = CGColor(gray: 1, alpha: 1)
let EDGE   = CGColor(red: 0.831, green: 0.816, blue: 0.835, alpha: 1)
let STACK  = CGColor(red: 0.878, green: 0.863, blue: 0.882, alpha: 1)

// Corners of the LEFT page. Both pages splay up and away from the fold —
// that upward tilt is what reads as an open book rather than a folded card.
let foldTop   = CGPoint(x: 500, y: 600)
let outerTop  = CGPoint(x: 190, y: 682)
let outerBase = CGPoint(x: 190, y: 456)
let foldBase  = CGPoint(x: 500, y: 374)

func drawIcon(in ctx: CGContext, size S: CGFloat) {
    let u = S / 1024.0
    func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * u, y: y * u) }
    func L(_ v: CGFloat) -> CGFloat { v * u }
    let tiny = S <= 40

    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // ---- red disc ---------------------------------------------------------
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: L(32), y: L(32), width: L(960), height: L(960)))
    ctx.clip()
    let disc = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [CGColor(red: 0.898, green: 0.361, blue: 0.333, alpha: 1),
                 CGColor(red: 0.714, green: 0.196, blue: 0.184, alpha: 1)] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(disc, start: P(512, 992), end: P(512, 32), options: [])
    ctx.restoreGState()

    func flip(_ x: CGFloat, _ mirrored: Bool) -> CGFloat { mirrored ? 1024 - x : x }

    /// One page. The top and bottom edges bow gently, the way paper actually
    /// lies when a book is open.
    func page(mirrored: Bool, drop: CGFloat = 0) -> CGPath {
        func pt(_ p: CGPoint) -> CGPoint { P(flip(p.x, mirrored), p.y - drop) }
        let p = CGMutablePath()
        p.move(to: pt(foldTop))
        p.addQuadCurve(to: pt(outerTop),
                       control: P(flip(345, mirrored), 664 - drop))
        p.addQuadCurve(to: pt(outerBase),
                       control: P(flip(172, mirrored), 569 - drop))
        p.addQuadCurve(to: pt(foldBase),
                       control: P(flip(345, mirrored), 402 - drop))
        p.addLine(to: pt(foldTop))
        p.closeSubpath()
        return p
    }

    // ---- pages stacked underneath, for thickness --------------------------
    for drop in [CGFloat(30), 16] {
        ctx.setFillColor(STACK)
        ctx.addPath(page(mirrored: false, drop: drop))
        ctx.addPath(page(mirrored: true, drop: drop))
        ctx.fillPath()
    }

    // ---- the open spread ---------------------------------------------------
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: L(-14)), blur: L(30),
                  color: CGColor(red: 0.27, green: 0.04, blue: 0.03, alpha: 0.42))
    ctx.setFillColor(PAPER)
    ctx.addPath(page(mirrored: false))
    ctx.addPath(page(mirrored: true))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.setStrokeColor(EDGE)
    ctx.setLineWidth(L(3))
    ctx.addPath(page(mirrored: false))
    ctx.addPath(page(mirrored: true))
    ctx.strokePath()

    // ---- the gutter --------------------------------------------------------
    ctx.saveGState()
    let gutter = CGMutablePath()
    gutter.move(to: P(476, 604))
    gutter.addLine(to: P(548, 604))
    gutter.addLine(to: P(548, 372))
    gutter.addLine(to: P(476, 372))
    gutter.closeSubpath()
    ctx.addPath(gutter)
    ctx.clip()
    let shade = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [CGColor(red: 0.50, green: 0.44, blue: 0.46, alpha: 0.0),
                 CGColor(red: 0.38, green: 0.32, blue: 0.34, alpha: 0.38),
                 CGColor(red: 0.50, green: 0.44, blue: 0.46, alpha: 0.0)] as CFArray,
        locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(shade, start: P(476, 488), end: P(548, 488), options: [])
    ctx.restoreGState()

    // ---- content, tilted so it sits on the sloping pages -------------------
    let tilt = atan2(outerTop.y - foldTop.y, foldTop.x - outerTop.x)
    let centre = CGPoint(x: (foldTop.x + outerTop.x + outerBase.x + foldBase.x) / 4,
                         y: (foldTop.y + outerTop.y + outerBase.y + foldBase.y) / 4)

    // left page: exploded pie
    ctx.saveGState()
    ctx.translateBy(x: P(centre.x, centre.y).x, y: P(centre.x, centre.y).y)
    ctx.rotate(by: -tilt)
    let radius = L(tiny ? 94 : 90)
    let slices: [(CGFloat, CGColor, CGFloat)] = [
        (0.46, INK,    0),
        (0.28, INK2,   0),
        (0.26, ACCENT, L(32)),
    ]
    var cursor: CGFloat = 0
    for (fraction, colour, explode) in slices {
        let a0 = (90 - cursor * 360) * .pi / 180
        let a1 = (90 - (cursor + fraction) * 360) * .pi / 180
        let mid = (a0 + a1) / 2
        let o = CGPoint(x: cos(mid) * explode, y: sin(mid) * explode)

        let wedge = CGMutablePath()
        wedge.move(to: o)
        wedge.addArc(center: o, radius: radius, startAngle: a0, endAngle: a1, clockwise: true)
        wedge.closeSubpath()

        ctx.setFillColor(colour)
        ctx.addPath(wedge)
        ctx.fillPath()
        ctx.setStrokeColor(PAPER)
        ctx.setLineWidth(L(tiny ? 15 : 10))
        ctx.setLineJoin(.round)
        ctx.addPath(wedge)
        ctx.strokePath()
        cursor += fraction
    }
    ctx.restoreGState()

    // right page: handwriting
    ctx.saveGState()
    ctx.translateBy(x: P(1024 - centre.x, centre.y).x, y: P(1024 - centre.x, centre.y).y)
    ctx.rotate(by: tilt)
    ctx.setStrokeColor(INK)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    if tiny {
        ctx.setLineWidth(L(28))
        for y in [CGFloat(46), -46] {
            ctx.move(to: CGPoint(x: L(-100), y: L(y)))
            ctx.addCurve(to: CGPoint(x: L(100), y: L(y)),
                         control1: CGPoint(x: L(-36), y: L(y + 38)),
                         control2: CGPoint(x: L(36), y: L(y - 38)))
            ctx.strokePath()
        }
    } else {
        ctx.setLineWidth(L(17))
        for (i, y) in [CGFloat(76), 0, -76].enumerated() {
            let right: CGFloat = i == 2 ? 66 : 108
            ctx.move(to: CGPoint(x: L(-108), y: L(y)))
            ctx.addCurve(to: CGPoint(x: 0, y: L(y)),
                         control1: CGPoint(x: L(-72), y: L(y + 30)),
                         control2: CGPoint(x: L(-34), y: L(y - 30)))
            ctx.addCurve(to: CGPoint(x: L(right), y: L(y)),
                         control1: CGPoint(x: L(34), y: L(y + 30)),
                         control2: CGPoint(x: L(right - 20), y: L(y - 26)))
            ctx.strokePath()
        }
    }
    ctx.restoreGState()
}

func render(size: Int) -> Data {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    drawIcon(in: ctx, size: CGFloat(size))
    return NSBitmapImageRep(cgImage: ctx.makeImage()!)
        .representation(using: .png, properties: [:])!
}

for s in [16, 32, 64, 128, 256, 512, 1024] {
    try! render(size: s).write(to: URL(fileURLWithPath: "out_\(s).png"))
}
try? FileManager.default.createDirectory(atPath: "RiftPDF.iconset", withIntermediateDirectories: true)
for (name, s) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32),
                  ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256),
                  ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512),
                  ("icon_512x512@2x", 1024)] {
    try! render(size: s).write(to: URL(fileURLWithPath: "RiftPDF.iconset/\(name).png"))
}
print("rendered")
