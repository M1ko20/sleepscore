import CoreGraphics

/// Logo Bedrival: osvětlený srpek s krátery, zbytek měsíce ve stínu (varianta 3, docs/design.md → Logo).
/// Jediný zdroj tvaru – kreslí ho `MoonLogo` v appce i `scripts/render_logo.swift` (ikona, launch screen).
/// Souřadnice v prostoru 100 × 100, osa y dolů; měsíc má střed (50, 50) a poloměr 32.
enum MoonLogoDrawing {
    private static let moonCenter = CGPoint(x: 50, y: 50)
    private static let moonRadius: CGFloat = 32
    /// Kruh, který „ukusuje“ stín: prochází horním a dolním okrajem měsíce, střed vpravo.
    private static let shadowCenter = CGPoint(x: 100.75, y: 50)
    private static let shadowRadius: CGFloat = 60

    private static let darkSide = CGColor(srgbRed: 0x1C / 255, green: 0x20 / 255, blue: 0x29 / 255, alpha: 1) // surfaceRaised
    private static let darkCrater = CGColor(srgbRed: 0x26 / 255, green: 0x2B / 255, blue: 0x36 / 255, alpha: 1) // hairline
    private static let lit = CGColor(srgbRed: 0xF2 / 255, green: 0xF1 / 255, blue: 0xEC / 255, alpha: 1) // textPrimary
    private static let craterRim = CGColor(srgbRed: 0xBD / 255, green: 0xB9 / 255, blue: 0xAD / 255, alpha: 1)
    private static let craterFloor = CGColor(srgbRed: 0xD9 / 255, green: 0xD6 / 255, blue: 0xCC / 255, alpha: 1)

    /// Krátery na stínové straně (x, y, r).
    private static let darkCraters: [(CGFloat, CGFloat, CGFloat)] = [(61, 59, 6), (60, 35, 4), (70, 46, 2.5)]
    /// Krátery na srpku (x, y, r) – tmavší okraj nahoře vlevo, světlejší dno posunuté dolů vpravo.
    private static let litCraters: [(CGFloat, CGFloat, CGFloat)] = [(31, 40, 6), (37, 64, 5), (24, 55, 3)]

    /// Nakreslí logo do obdélníku `rect` (čtverec; osa y dolů).
    static func draw(in ctx: CGContext, rect: CGRect) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.minY)
        ctx.scaleBy(x: rect.width / 100, y: rect.height / 100)

        let moon = circle(moonCenter, moonRadius)
        ctx.setFillColor(darkSide)
        ctx.addPath(moon)
        ctx.fillPath()
        ctx.setFillColor(darkCrater)
        for (x, y, r) in darkCraters {
            ctx.addPath(circle(CGPoint(x: x, y: y), r))
            ctx.fillPath()
        }

        // Srpek = měsíc minus kruh stínu (měsíc ∩ (měsíc XOR stín)).
        ctx.saveGState()
        ctx.addPath(moon)
        ctx.clip()
        ctx.addPath(moon)
        ctx.addPath(circle(shadowCenter, shadowRadius))
        ctx.clip(using: .evenOdd)

        ctx.setFillColor(lit)
        ctx.addPath(moon)
        ctx.fillPath()
        for (x, y, r) in litCraters {
            ctx.setFillColor(craterRim)
            ctx.addPath(circle(CGPoint(x: x, y: y), r))
            ctx.fillPath()
            ctx.setFillColor(craterFloor)
            ctx.addPath(circle(CGPoint(x: x + r * 0.18, y: y + r * 0.18), r * 0.85))
            ctx.fillPath()
        }
        ctx.restoreGState()

        ctx.restoreGState()
    }

    private static func circle(_ c: CGPoint, _ r: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), transform: nil)
    }
}
