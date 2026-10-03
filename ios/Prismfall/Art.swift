// Palette and procedural artwork. Everything is drawn once with Core Graphics
// and cached as textures; nothing here runs per frame.

import CoreText
import SpriteKit
import SwiftUI

nonisolated struct RGB {
    var r: CGFloat
    var g: CGFloat
    var b: CGFloat

    static let white = RGB(0xFFFFFF)
    static let black = RGB(0)

    init(r: CGFloat, g: CGFloat, b: CGFloat) {
        self.r = r
        self.g = g
        self.b = b
    }
    init(_ hex: UInt32) {
        self.init(r: CGFloat(hex >> 16 & 255) / 255, g: CGFloat(hex >> 8 & 255) / 255, b: CGFloat(hex & 255) / 255)
    }

    func mix(_ other: RGB, _ t: CGFloat) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }
    func lighter(_ t: CGFloat) -> RGB { mix(.white, t) }
    func darker(_ t: CGFloat) -> RGB { mix(.black, t) }
    func cg(_ alpha: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: alpha) }
    var ui: UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }
    var color: Color { Color(red: r, green: g, blue: b) }
}

/// A luminous violet backdrop, cream surfaces, gold accents and grape ink, so all six block colours read against them.
nonisolated enum Theme {
    static let blocks = [0xFF239D, 0xFFC817, 0x08CFEE, 0x3275FF, 0xB232FF, 0xFF712B].map { RGB($0) }
    static let blockNames = ["Ribbon", "Halo", "Moon", "Wing", "Bloom", "Flare"]
    static let spent = RGB(0x4B4664)

    static let sky = [RGB(0x9A6BFF), RGB(0x6F3FF5), RGB(0x4722C4)]
    static let ink = RGB(0x2A1151)
    static let violet = RGB(0x7A35F2)
    static let cream = RGB(0xFFF7E4)
    static let gold = RGB(0xFFC817)
    static let amber = RGB(0xE99A1C)
    static let alert = RGB(0xFF4A5E)

    static func display(_ size: CGFloat, black: Bool = false) -> UIFont {
        UIFont(name: black ? "Unbounded-Black" : "Unbounded-Bold", size: size) ?? rounded(size, .black)
    }
    static func rounded(_ size: CGFloat, _ weight: UIFont.Weight = .bold) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        return base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
    }
}

nonisolated extension CGContext {
    /// Shadow in user-space units with y pointing down, like the rest of the drawing code.
    func shadow(dy: CGFloat = 0, blur: CGFloat, _ color: CGColor) {
        let k = hypot(ctm.a, ctm.b)
        setShadow(offset: CGSize(width: 0, height: -dy * k), blur: blur * k, color: color)
    }
    func fill(_ path: CGPath, _ color: CGColor, rule: CGPathFillRule = .winding) {
        addPath(path)
        setFillColor(color)
        fillPath(using: rule)
    }
    func stroke(_ path: CGPath, _ color: CGColor, width: CGFloat) {
        addPath(path)
        setStrokeColor(color)
        setLineWidth(width)
        strokePath()
    }
    func linear(_ stops: [(CGFloat, CGColor)], from: CGPoint, to: CGPoint) {
        drawLinearGradient(Art.gradient(stops), start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    /// Fills `path` with a linear gradient without disturbing the current clip.
    func fill(_ path: CGPath, linear stops: [(CGFloat, CGColor)], from: CGPoint, to: CGPoint, rule: CGPathFillRule = .winding) {
        saveGState()
        addPath(path)
        clip(using: rule)
        linear(stops, from: from, to: to)
        restoreGState()
    }
    func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, angle: CGFloat, fill: CGColor? = nil, stroke: CGColor? = nil, width: CGFloat = 0) {
        saveGState()
        translateBy(x: cx, y: cy)
        rotate(by: angle)
        let box = CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2)
        if let fill {
            setFillColor(fill)
            fillEllipse(in: box)
        }
        if let stroke {
            setStrokeColor(stroke)
            setLineWidth(width)
            strokeEllipse(in: box)
        }
        restoreGState()
    }
}

/// Drawing only touches its own bitmap, so the block artwork can be rendered off the main actor.
nonisolated enum Art {
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    static func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
        CGGradient(colorsSpace: srgb, colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))!
    }
    static func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
        let r = max(0, min(r, w / 2, h / 2))
        return CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
    }
    static func rr(_ rect: CGRect, _ r: CGFloat) -> CGPath { rr(rect.minX, rect.minY, rect.width, rect.height, r) }

    /// Renders with a top-left origin. `size` is in points; the bitmap is `scale` times larger.
    static func image(_ size: CGSize, scale: CGFloat, _ draw: (CGContext) -> Void) -> CGImage {
        let w = max(1, Int((size.width * scale).rounded(.up)))
        let h = max(1, Int((size.height * scale).rounded(.up)))
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        draw(ctx)
        return ctx.makeImage()!
    }
    @MainActor static func texture(_ size: CGSize, scale: CGFloat, _ draw: (CGContext) -> Void) -> SKTexture {
        SKTexture(cgImage: image(size, scale: scale, draw))
    }

    // MARK: Blocks

    /// Rounded-box height field lit by one studio key: shade, specular and coverage per pixel.
    static func shading(_ px: Int) -> [Float] {
        let s = Double(px)
        let edge = 0.055, radius = 0.19, bevel = 0.095, eps = 0.001
        func distance(_ x: Double, _ y: Double) -> Double {
            let qx = abs(x - 0.5) - (0.5 - edge - radius)
            let qy = abs(y - 0.475) - (0.475 - edge - radius)
            return radius - hypot(max(qx, 0), max(qy, 0)) - min(max(qx, qy), 0)
        }
        func height(_ x: Double, _ y: Double) -> Double {
            let t = max(0, min(1, distance(x, y) / bevel))
            let crown = max(0, 1 - ((x - 0.5) * (x - 0.5) + (y - 0.475) * (y - 0.475)) * 2.7)
            return bevel * (1 - (1 - t) * (1 - t)).squareRoot() + 0.024 * crown
        }
        var map = [Float](repeating: 0, count: px * px * 3)
        for y in 0..<px {
            for x in 0..<px {
                let u = (Double(x) + 0.5) / s
                let v = (Double(y) + 0.5) / s
                let alpha = max(0, min(1, distance(u, v) * s + 0.5))
                guard alpha > 0 else { continue }
                var nx = -(height(u + eps, v) - height(u - eps, v)) / (eps * 2)
                var ny = -(height(u, v + eps) - height(u, v - eps)) / (eps * 2)
                let length = (nx * nx + ny * ny + 1).squareRoot()
                nx /= length
                ny /= length
                let nz = 1 / length
                let diffuse = max(0, nx * -0.43 + ny * -0.55 + nz * 0.715)
                let i = (y * px + x) * 3
                map[i] = Float(0.42 + 0.64 * diffuse)
                map[i + 1] = Float(pow(max(0, nx * -0.23 + ny * -0.295 + nz * 0.927), 32) * 0.78)
                map[i + 2] = Float(alpha)
            }
        }
        return map
    }

    /// The lit body of a block in one colour, from a shading map.
    static func body(_ px: Int, _ color: RGB, _ map: [Float]) -> CGImage {
        let rgb = [Float(color.r), Float(color.g), Float(color.b)]
        var data = [UInt8](repeating: 0, count: px * px * 4)
        for i in 0..<px * px {
            let alpha = map[i * 3 + 2]
            guard alpha > 0 else { continue }
            for k in 0..<3 {
                let lit = rgb[k] * map[i * 3]
                data[i * 4 + k] = UInt8(min(1, lit + (1 - lit) * map[i * 3 + 1]) * alpha * 255)
            }
            data[i * 4 + 3] = UInt8(alpha * 255)
        }
        return CGImage(width: px, height: px, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: px * 4, space: srgb,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: Data(data) as CFData)!, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)!
    }

    /// Six molded emblems in a unit square: ribbon, halo, crescent, wing, bloom, flare.
    /// Built once and never mutated, so sharing them across threads is safe.
    nonisolated(unsafe) private static let emblems: [CGPath] = (0..<6).map { k in
        let p = CGMutablePath()
        func m(_ x: CGFloat, _ y: CGFloat) { p.move(to: CGPoint(x: x, y: y)) }
        func l(_ x: CGFloat, _ y: CGFloat) { p.addLine(to: CGPoint(x: x, y: y)) }
        func q(_ cx: CGFloat, _ cy: CGFloat, _ x: CGFloat, _ y: CGFloat) {
            p.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: cx, y: cy))
        }
        func c(_ ax: CGFloat, _ ay: CGFloat, _ bx: CGFloat, _ by: CGFloat, _ x: CGFloat, _ y: CGFloat) {
            p.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: ax, y: ay), control2: CGPoint(x: bx, y: by))
        }
        switch k {
        case 0:
            m(-0.9, 0); c(-0.9, -0.85, -0.12, -0.85, 0.28, -0.24); c(0.88, 0.4, 0.82, 0.83, 0.28, 0.79)
            c(-0.15, 0.78, -0.23, 0.28, -0.5, 0.28); c(-0.8, 0.28, -0.92, 0.2, -0.9, 0); p.closeSubpath()
            m(-0.49, -0.22); c(-0.2, -0.13, 0.12, 0.4, 0.37, 0.41); c(0.64, 0.4, 0.25, -0.08, -0.12, -0.31)
            c(-0.4, -0.5, -0.68, -0.5, -0.49, -0.22); p.closeSubpath()
        case 1:
            let tilt = CGAffineTransform(rotationAngle: 0.5)
            p.addEllipse(in: CGRect(x: -0.77, y: -0.88, width: 1.54, height: 1.76), transform: tilt)
            p.addEllipse(in: CGRect(x: -0.3, y: -0.43, width: 0.6, height: 0.86), transform: tilt)
        case 2:
            m(0.55, -0.73); c(-0.9, -1.05, -1.1, 0.68, -0.05, 0.85); c(0.42, 0.94, 0.8, 0.63, 0.86, 0.34)
            c(-0.19, 0.65, -0.43, -0.31, 0.55, -0.73); p.closeSubpath()
        case 3:
            m(-0.9, 0.55); q(-0.55, -0.45, 0.85, -0.8); q(0.46, -0.22, 0.11, -0.07); l(0.59, 0.04)
            q(0.03, 0.54, -0.42, 0.34); p.closeSubpath()
        case 4:
            for i in 0...120 {
                let t = CGFloat(i) / 120 * 2 * .pi
                let r = 0.63 + 0.2 * cos(3 * t - .pi / 2)
                i == 0 ? m(cos(t) * r, sin(t) * r) : l(cos(t) * r, sin(t) * r)
            }
            p.closeSubpath()
        default:
            m(-0.68, 0.67); q(-0.77, -0.32, -0.18, -0.87); q(-0.04, -0.45, 0.05, -0.26); l(0.49, -0.69)
            q(0.4, -0.23, 0.42, -0.1); l(0.83, -0.23); q(0.77, 0.68, -0.04, 0.81); p.closeSubpath()
        }
        return p
    }

    /// Draws one block in a `px` square at the origin, over its pre-lit `body`.
    /// A nil colour gives the spent, game-over block.
    static func drawBlock(_ ctx: CGContext, px: Int, color index: Int?, special: Special, symbol: Bool, body: CGImage) {
        let s = CGFloat(px)
        let color = index.map { Theme.blocks[$0] } ?? Theme.spent
        let white = RGB.white

        // lip and contact shadow, then the lit body
        ctx.saveGState()
        ctx.shadow(dy: s * 0.025, blur: s * 0.045, CGColor(srgbRed: 0.08, green: 0.1, blue: 0.12, alpha: 0.24))
        ctx.fill(rr(s * 0.065, s * 0.095, s * 0.87, s * 0.855, s * 0.19), color.darker(0.29).cg())
        ctx.restoreGState()
        ctx.saveGState()
        ctx.translateBy(x: 0, y: s)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(body, in: CGRect(x: 0, y: 0, width: s, height: s))
        ctx.restoreGState()

        // glaze, rim light and two speculars
        ctx.saveGState()
        ctx.addPath(rr(s * 0.055, s * 0.055, s * 0.89, s * 0.84, s * 0.19))
        ctx.clip()
        let glaze = CGMutablePath()
        glaze.move(to: CGPoint(x: s * 0.1, y: s * 0.3))
        glaze.addCurve(to: CGPoint(x: s * 0.86, y: s * 0.16), control1: CGPoint(x: s * 0.2, y: s * 0.05), control2: CGPoint(x: s * 0.65, y: s * 0.035))
        glaze.addCurve(to: CGPoint(x: s * 0.1, y: s * 0.3), control1: CGPoint(x: s * 0.65, y: s * 0.12), control2: CGPoint(x: s * 0.44, y: s * 0.26))
        ctx.fill(glaze, linear: [(0, white.cg(0.83)), (0.55, white.cg(0.15)), (1, white.cg(0))],
                 from: CGPoint(x: 0, y: s * 0.05), to: CGPoint(x: s * 0.4, y: s * 0.5))
        let rim = rr(s * 0.075, s * 0.07, s * 0.85, s * 0.8, s * 0.16).copy(strokingWithWidth: s * 0.021, lineCap: .butt, lineJoin: .round, miterLimit: 4)
        ctx.fill(rim, linear: [(0, white.cg(0.95)), (0.45, white.cg(0.08)), (1, white.cg(0.65))], from: .zero, to: CGPoint(x: s, y: s))
        ctx.ellipse(s * 0.17, s * 0.13, s * 0.065, s * 0.022, angle: -0.55, fill: white.cg(0.88))
        ctx.ellipse(s * 0.77, s * 0.84, s * 0.06, s * 0.009, angle: -0.12, fill: white.cg(0.6))
        ctx.restoreGState()

        let center = CGPoint(x: s * 0.5, y: s * 0.47)
        switch special {
        case .plain:
            guard let index else { break }
            ctx.saveGState()
            ctx.shadow(dy: s * 0.027, blur: s * 0.08, color.darker(0.5).cg())
            ctx.translateBy(x: s * 0.5, y: s * 0.49)
            ctx.scaleBy(x: s * 0.27, y: s * 0.27)
            ctx.fill(emblems[index], color.cg(), rule: .evenOdd)
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.fill(emblems[index], linear: [(0, color.lighter(0.82).cg()), (0.38, color.lighter(0.37).cg()), (1, color.cg())],
                     from: CGPoint(x: -0.5, y: -1), to: CGPoint(x: 0.4, y: 1), rule: .evenOdd)
            ctx.stroke(emblems[index], color.lighter(0.7).cg(), width: 0.055)
            ctx.restoreGState()
        case .lineH, .lineV:
            // chevrons along the row or column the blaster clears
            ctx.saveGState()
            ctx.shadow(dy: s * 0.035, blur: s * 0.045, color.darker(0.45).cg())
            ctx.translateBy(x: center.x, y: center.y)
            if special == .lineV { ctx.rotate(by: .pi / 2) }
            ctx.setLineJoin(.round)
            ctx.setLineCap(.round)
            let chevrons = CGMutablePath()
            for x in [-0.2, 0.13] as [CGFloat] {
                chevrons.addLines(between: [CGPoint(x: s * (x - 0.12), y: -s * 0.18), CGPoint(x: s * (x + 0.08), y: 0), CGPoint(x: s * (x - 0.12), y: s * 0.18)])
            }
            ctx.stroke(chevrons, RGB(0xFFF6EF).cg(), width: s * 0.09)
            ctx.restoreGState()
        case .bomb:
            // orbital sphere
            let r = s * 0.255
            let ball = CGPath(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2), transform: nil)
            ctx.saveGState()
            ctx.shadow(blur: s * 0.11, color.lighter(0.6).cg())
            ctx.fill(ball, color.cg())
            ctx.restoreGState()
            ctx.saveGState()
            ctx.addPath(ball)
            ctx.clip()
            ctx.drawRadialGradient(
                gradient([(0, RGB(0xFFF7FC).cg()), (0.28, color.lighter(0.65).cg()), (0.65, color.cg()), (1, color.darker(0.5).cg())]),
                startCenter: CGPoint(x: center.x - r * 0.4, y: center.y - r * 0.5), startRadius: 0, endCenter: center, endRadius: r,
                options: .drawsAfterEndLocation)
            ctx.restoreGState()
            ctx.ellipse(center.x, center.y, r * 1.18, r * 0.42, angle: -0.55, stroke: RGB(0xFFF5ED).cg(), width: s * 0.026)
        case .prism:
            // six-sector spectral core
            let r = s * 0.29
            let corner = { (k: Int) in CGPoint(x: center.x + cos(CGFloat(k) * .pi / 3) * r, y: center.y + sin(CGFloat(k) * .pi / 3) * r) }
            let hexagon = CGMutablePath()
            hexagon.addLines(between: (0..<6).map(corner))
            hexagon.closeSubpath()
            ctx.saveGState()
            ctx.shadow(blur: s * 0.1, RGB(0xFFE9FF).cg())
            ctx.fill(hexagon, white.cg())
            ctx.restoreGState()
            for k in 0..<6 {
                let sector = CGMutablePath()
                sector.addLines(between: [center, corner(k), corner(k + 1)])
                sector.closeSubpath()
                ctx.fill(sector, linear: [(0, white.cg()), (1, Theme.blocks[k].cg())], from: center, to: corner(k))
            }
        }

        // small high-contrast identity mark for colour-blind play
        if symbol, let index {
            ctx.saveGState()
            ctx.translateBy(x: s * 0.2, y: s * 0.21)
            ctx.scaleBy(x: s * 0.083, y: s * 0.083)
            ctx.stroke(emblems[index], color.darker(0.68).cg(), width: 0.22)
            ctx.fill(emblems[index], white.cg(), rule: .evenOdd)
            ctx.restoreGState()
        }
    }

    /// A standalone block image for the menus.
    @MainActor static func blockImage(_ color: Int, _ special: Special = .plain, symbol: Bool = false) -> CGImage {
        let key = color * 10 + special.rawValue + (symbol ? 100 : 0)
        if let cached = blockImages[key] { return cached }
        let px = 108
        let lit = body(px, Theme.blocks[color], menuShading)
        let made = image(CGSize(width: px, height: px), scale: 1) {
            drawBlock($0, px: px, color: color, special: special, symbol: symbol, body: lit)
        }
        blockImages[key] = made
        return made
    }
    @MainActor private static var blockImages: [Int: CGImage] = [:]
    @MainActor private static let menuShading = shading(108)

    // MARK: Text

    /// Text as one texture with an optional round-joined outline behind the fill.
    @MainActor static func text(_ string: String, font: UIFont, fill: CGColor, outline: CGColor? = nil, width: CGFloat = 0, scale: CGFloat) -> (texture: SKTexture, size: CGSize)? {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [.font: font]))
        let path = CGMutablePath()
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(), &glyphs)
            CTRunGetPositions(run, CFRange(), &positions)
            for i in 0..<count {
                guard let glyph = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) else { continue }
                path.addPath(glyph, transform: CGAffineTransform(translationX: positions[i].x, y: positions[i].y))
            }
        }
        guard !path.isEmpty else { return nil }
        let box = path.boundingBoxOfPath.insetBy(dx: -width / 2 - 1, dy: -width / 2 - 1)
        let w = Int((box.width * scale).rounded(.up))
        let h = Int((box.height * scale).rounded(.up))
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        if let outline {
            ctx.setLineJoin(.round)
            ctx.stroke(path, outline, width: width)
        }
        ctx.fill(path, fill)
        return (SKTexture(cgImage: ctx.makeImage()!), box.size)
    }
}

/// Every block texture on one sheet, so the board draws in a single batch.
struct BlockSheet {
    /// The rendered sheet and where each texture sits on it.
    nonisolated struct Bitmap: @unchecked Sendable {
        let image: CGImage
        let slots: [CGRect]
    }

    let blocks: [[SKTexture]]
    let spent: [SKTexture]
    /// Solid white block silhouette: flashes and confetti.
    let white: SKTexture
    /// Hollow rounded square: ghost piece and swap highlights. Tint it.
    let outline: SKTexture
    /// Soft radial glow. Tint it.
    let glow: SKTexture
    let dot: SKTexture

    /// Paints the sheet. This is the slowest part of start-up, so it runs off the main actor.
    nonisolated static func render(cell: CGFloat, scale: CGFloat, symbols: Bool) -> Bitmap {
        let gutter = 4
        let columns = 7
        // a power-of-two sheet so SpriteKit can mipmap it for the small HUD previews
        let px = min(Int((cell * scale).rounded()), 1024 / columns - gutter)
        let pitch = px + gutter
        var side = 64
        while side < columns * pitch { side *= 2 }
        let s = CGFloat(px)
        let map = Art.shading(px)
        var slots: [CGRect] = []
        let image = Art.image(CGSize(width: side, height: side), scale: 1) { ctx in
            func next(_ draw: () -> Void) {
                let x = CGFloat(slots.count % columns * pitch + gutter / 2)
                let y = CGFloat(slots.count / columns * pitch + gutter / 2)
                ctx.saveGState()
                ctx.translateBy(x: x, y: y)
                draw()
                ctx.restoreGState()
                slots.append(CGRect(x: x / CGFloat(side), y: 1 - (y + s) / CGFloat(side), width: s / CGFloat(side), height: s / CGFloat(side)))
            }
            for color in Theme.blocks.indices {
                let body = Art.body(px, Theme.blocks[color], map)
                for special in 0..<5 {
                    next { Art.drawBlock(ctx, px: px, color: color, special: Special(rawValue: special)!, symbol: symbols, body: body) }
                }
            }
            let spent = Art.body(px, Theme.spent, map)
            for special in 0..<5 {
                next { Art.drawBlock(ctx, px: px, color: nil, special: Special(rawValue: special)!, symbol: false, body: spent) }
            }
            next { ctx.fill(Art.rr(s * 0.045, s * 0.045, s * 0.91, s * 0.91, s * 0.2), RGB.white.cg()) }
            next {
                let box = Art.rr(s * 0.09, s * 0.09, s * 0.82, s * 0.82, s * 0.18)
                ctx.fill(box, RGB.white.cg(0.13))
                ctx.stroke(box, RGB.white.cg(0.8), width: max(1.5, s * 0.055))
            }
            next {
                ctx.drawRadialGradient(Art.gradient([(0, RGB.white.cg(0.75)), (1, RGB.white.cg(0))]),
                                       startCenter: CGPoint(x: s / 2, y: s / 2), startRadius: s * 0.1,
                                       endCenter: CGPoint(x: s / 2, y: s / 2), endRadius: s * 0.5, options: .drawsBeforeStartLocation)
            }
            next { ctx.fill(CGPath(ellipseIn: CGRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8), transform: nil), RGB.white.cg()) }
        }
        return Bitmap(image: image, slots: slots)
    }

    init(_ bitmap: Bitmap) {
        let atlas = SKTexture(cgImage: bitmap.image)
        atlas.usesMipmaps = true
        let textures = bitmap.slots.map { SKTexture(rect: $0, in: atlas) }
        blocks = (0..<6).map { Array(textures[$0 * 5..<$0 * 5 + 5]) }
        spent = Array(textures[30..<35])
        white = textures[35]
        outline = textures[36]
        glow = textures[37]
        dot = textures[38]
    }
}

/// A texture whose corners stay crisp while its middle stretches.
struct NineSlice {
    let texture: SKTexture
    let base: CGSize
    /// Corner size, measured from the texture edge.
    let inset: CGFloat
    /// Transparent room around the body for its shadow.
    var margin: CGFloat = 0

    /// A sprite whose body, not counting the margin, measures `size`.
    func node(_ size: CGSize) -> SKSpriteNode {
        let node = SKSpriteNode(texture: texture, size: base)
        let x = inset / base.width
        let y = min(0.49, inset / base.height)
        node.centerRect = CGRect(x: x, y: y, width: 1 - 2 * x, height: 1 - 2 * y)
        resize(node, size)
        return node
    }
    func resize(_ node: SKSpriteNode, _ size: CGSize) {
        node.xScale = (size.width + 2 * margin) / base.width
        node.yScale = (size.height + 2 * margin) / base.height
    }
}

// MARK: Chrome

@MainActor extension Art {
    /// Violet sky with soft flares. Smooth enough to render at quarter size.
    static func backdrop(_ size: CGSize) -> SKTexture {
        texture(size, scale: 0.25) { ctx in
            let w = size.width
            let h = size.height
            ctx.linear([(0, Theme.sky[0].cg()), (0.5, Theme.sky[1].cg()), (1, Theme.sky[2].cg())], from: .zero, to: CGPoint(x: w * 0.3, y: h))
            // faint rays fanning from above the screen
            let source = CGPoint(x: w * 0.5, y: -h * 0.12)
            let rays = CGMutablePath()
            for k in 0..<9 {
                let a = CGFloat.pi * (0.14 + 0.08 * CGFloat(k))
                rays.addLines(between: [source, CGPoint(x: source.x + cos(a) * h * 2, y: source.y + sin(a) * h * 2),
                                        CGPoint(x: source.x + cos(a + 0.11) * h * 2, y: source.y + sin(a + 0.11) * h * 2)])
                rays.closeSubpath()
            }
            ctx.fill(rays, linear: [(0, RGB.white.cg(0.13)), (0.7, RGB.white.cg(0))], from: source, to: CGPoint(x: source.x, y: h))
            for (x, y, r, a) in [(-0.08, 0.2, 0.62, 0.3), (1.1, 0.52, 0.6, 0.2), (-0.05, 0.92, 0.5, 0.16), (1, 1, 0.5, 0.14)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
                let center = CGPoint(x: w * x, y: h * y)
                ctx.drawRadialGradient(gradient([(0, RGB.white.cg(a)), (1, RGB.white.cg(0))]),
                                       startCenter: center, startRadius: 0, endCenter: center, endRadius: w * r, options: [])
            }
        }
    }

    /// The board: a cream rim with a gold lip around a recessed grape well.
    static func frame(cell: CGFloat, rim: CGFloat, scale: CGFloat) -> NineSlice {
        let margin = cell * 0.75
        let inset = margin + rim + cell * 0.55
        let side = inset * 2 + 4
        let outer = CGRect(x: margin, y: margin, width: side - margin * 2, height: side - margin * 2)
        let well = outer.insetBy(dx: rim, dy: rim)
        let lip = max(2, cell * 0.08)
        let texture = texture(CGSize(width: side, height: side), scale: scale) { ctx in
            ctx.saveGState()
            ctx.shadow(dy: cell * 0.2, blur: cell * 0.5, RGB(0x16063D).cg(0.5))
            ctx.fill(rr(outer.offsetBy(dx: 0, dy: lip), cell * 0.4), Theme.amber.cg())
            ctx.restoreGState()
            ctx.fill(rr(outer, cell * 0.4), linear: [(0, RGB.white.cg()), (0.5, Theme.cream.cg()), (1, RGB(0xFFDF94).cg())],
                     from: CGPoint(x: 0, y: outer.minY), to: CGPoint(x: 0, y: outer.maxY))
            ctx.stroke(rr(outer.insetBy(dx: 0.75, dy: 0.75), cell * 0.4), RGB.white.cg(0.95), width: 1.5)
            ctx.stroke(rr(well.insetBy(dx: -rim * 0.3, dy: -rim * 0.3), cell * 0.24), Theme.amber.cg(0.55), width: max(1, rim * 0.2))
            let floor = rr(well, cell * 0.18)
            ctx.fill(floor, linear: [(0, RGB(0x190C36).cg()), (0.15, RGB(0x21103F).cg()), (1, RGB(0x2F1759).cg())],
                     from: CGPoint(x: 0, y: well.minY), to: CGPoint(x: 0, y: well.maxY))
            // inner shadow, so the well sits below the rim
            ctx.saveGState()
            ctx.addPath(floor)
            ctx.clip()
            ctx.shadow(dy: cell * 0.08, blur: cell * 0.22, RGB.black.cg(0.75))
            let hole = CGMutablePath()
            hole.addRect(outer.insetBy(dx: -margin, dy: -margin))
            hole.addPath(floor)
            ctx.fill(hole, RGB.black.cg(), rule: .evenOdd)
            ctx.restoreGState()
        }
        return NineSlice(texture: texture, base: CGSize(width: side, height: side), inset: inset, margin: margin + rim)
    }

    /// One empty slot of the well.
    static func gridCell(_ cell: CGFloat, scale: CGFloat) -> SKTexture {
        texture(CGSize(width: cell, height: cell), scale: scale) { ctx in
            let slot = rr(cell * 0.07, cell * 0.07, cell * 0.86, cell * 0.86, cell * 0.17)
            ctx.fill(slot, RGB.white.cg(0.018))
            ctx.stroke(slot, RGB(0xC3A2FF).cg(0.15), width: 1 / scale)
        }
    }

    /// Raised grape panel behind the hold and next previews.
    static func panel(scale: CGFloat) -> NineSlice {
        let margin: CGFloat = 10
        let radius: CGFloat = 13
        let inset = margin + radius + 2
        let side = inset * 2 + 4
        let body = CGRect(x: margin, y: margin, width: side - margin * 2, height: side - margin * 2)
        let texture = texture(CGSize(width: side, height: side), scale: scale) { ctx in
            ctx.saveGState()
            ctx.shadow(dy: 3, blur: 7, Theme.ink.cg(0.4))
            ctx.fill(rr(body, radius), Theme.ink.cg())
            ctx.restoreGState()
            ctx.fill(rr(body, radius), linear: [(0, RGB(0x3B1D83).cg()), (1, RGB(0x1E0D49).cg())],
                     from: CGPoint(x: body.minX, y: body.minY), to: CGPoint(x: body.maxX, y: body.maxY))
            ctx.stroke(rr(body.insetBy(dx: 0.75, dy: 0.75), radius), Theme.cream.cg(0.7), width: 1.5)
        }
        return NineSlice(texture: texture, base: CGSize(width: side, height: side), inset: inset, margin: margin)
    }

    static func capsule(height: CGFloat, fill: CGColor, stroke: CGColor? = nil, scale: CGFloat) -> NineSlice {
        let base = CGSize(width: height + 6, height: height + 2)
        let texture = texture(base, scale: scale) { ctx in
            ctx.fill(rr(1, 1, height + 4, height, height / 2), fill)
            if let stroke { ctx.stroke(rr(1.75, 1.75, height + 2.5, height - 1.5, height / 2), stroke, width: 1.5) }
        }
        return NineSlice(texture: texture, base: base, inset: height / 2 + 1, margin: 1)
    }

    static func pauseButton(_ d: CGFloat, scale: CGFloat) -> SKTexture {
        texture(CGSize(width: d, height: d + 3), scale: scale) { ctx in
            ctx.fillEllipse(in: CGRect(x: 1, y: 4, width: d - 2, height: d - 2), Theme.ink.cg())
            let face = CGPath(ellipseIn: CGRect(x: 1, y: 1, width: d - 2, height: d - 2), transform: nil)
            ctx.fill(face, linear: [(0, RGB(0x9A63FF).cg()), (1, RGB(0x5B22C4).cg())], from: .zero, to: CGPoint(x: 0, y: d))
            ctx.stroke(CGPath(ellipseIn: CGRect(x: 1.75, y: 1.75, width: d - 3.5, height: d - 3.5), transform: nil), Theme.cream.cg(0.85), width: 1.5)
            for x in [-0.14, 0.05] as [CGFloat] {
                ctx.fill(rr(d * (0.5 + x), d * 0.34, d * 0.09, d * 0.32, d * 0.04), RGB.white.cg())
            }
        }
    }

    /// Two opposed arrows.
    static func swapIcon(_ s: CGFloat, color: CGColor, scale: CGFloat) -> SKTexture {
        texture(CGSize(width: s * 1.2, height: s * 1.2), scale: scale) { ctx in
            ctx.translateBy(x: s * 0.6, y: s * 0.6)
            ctx.setLineCap(.round)
            let shafts = CGMutablePath()
            shafts.addLines(between: [CGPoint(x: -s * 0.45, y: -s * 0.2), CGPoint(x: s * 0.35, y: -s * 0.2)])
            shafts.addLines(between: [CGPoint(x: s * 0.45, y: s * 0.2), CGPoint(x: -s * 0.35, y: s * 0.2)])
            ctx.stroke(shafts, color, width: max(1.4, s * 0.13))
            let heads = CGMutablePath()
            heads.addLines(between: [CGPoint(x: s * 0.5, y: -s * 0.2), CGPoint(x: s * 0.22, y: -s * 0.44), CGPoint(x: s * 0.22, y: s * 0.04)])
            heads.closeSubpath()
            heads.addLines(between: [CGPoint(x: -s * 0.5, y: s * 0.2), CGPoint(x: -s * 0.22, y: -s * 0.04), CGPoint(x: -s * 0.22, y: s * 0.44)])
            heads.closeSubpath()
            ctx.fill(heads, color)
        }
    }

    /// The diamond that marks a banked swap, filled or hollow.
    static func pip(_ r: CGFloat, filled: Bool, scale: CGFloat) -> SKTexture {
        texture(CGSize(width: r * 2 + 2, height: r * 2 + 2), scale: scale) { ctx in
            let c = r + 1
            let diamond = CGMutablePath()
            diamond.addLines(between: [CGPoint(x: c, y: c - r), CGPoint(x: c + r, y: c), CGPoint(x: c, y: c + r), CGPoint(x: c - r, y: c)])
            diamond.closeSubpath()
            if filled {
                ctx.fill(diamond, Theme.gold.cg())
            } else {
                ctx.setLineJoin(.round)
                ctx.stroke(diamond, RGB.white.cg(0.4), width: 1.2)
            }
        }
    }

    /// Arrowhead pointing right, from a selected block toward a swap partner.
    static func chevron(_ s: CGFloat, scale: CGFloat) -> SKTexture {
        texture(CGSize(width: s * 0.5, height: s * 0.5), scale: scale) { ctx in
            ctx.translateBy(x: s * 0.25, y: s * 0.25)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            let mark = CGMutablePath()
            mark.addLines(between: [CGPoint(x: -s * 0.1, y: -s * 0.16), CGPoint(x: s * 0.08, y: 0), CGPoint(x: -s * 0.1, y: s * 0.16)])
            ctx.stroke(mark, RGB.white.cg(), width: max(2, s * 0.07))
        }
    }

    /// White strip that fades in from top to bottom. Tint and stretch it.
    static let fade = texture(CGSize(width: 2, height: 64), scale: 1) { ctx in
        ctx.linear([(0, RGB.white.cg(0)), (1, RGB.white.cg())], from: .zero, to: CGPoint(x: 0, y: 64))
    }
}

private extension CGContext {
    func fillEllipse(in rect: CGRect, _ color: CGColor) {
        setFillColor(color)
        fillEllipse(in: rect)
    }
}
