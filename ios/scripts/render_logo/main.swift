// Vyrenderuje ikonu appky a obrázek pro launch screen z MoonLogoDrawing.swift.
// Spuštění (z adresáře ios/):
//   swiftc -o /tmp/render_logo SleepApp/Design/MoonLogoDrawing.swift scripts/render_logo/main.swift && /tmp/render_logo
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let assets = URL(fileURLWithPath: "SleepApp/Assets.xcassets")

func render(px: Int, background: CGColor?, logoScale: CGFloat, to url: URL) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    // Ikona nesmí mít alfa kanál → u ikony bez alfy.
    let info = background == nil ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)!
    // Osa y dolů jako v UIKitu/SwiftUI.
    ctx.translateBy(x: 0, y: CGFloat(px))
    ctx.scaleBy(x: 1, y: -1)
    if let background {
        ctx.setFillColor(background)
        ctx.fill(CGRect(x: 0, y: 0, width: px, height: px))
    }
    let side = CGFloat(px) * logoScale
    let origin = (CGFloat(px) - side) / 2
    MoonLogoDrawing.draw(in: ctx, rect: CGRect(x: origin, y: origin, width: side, height: side))

    let image = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("✓ \(url.path)")
}

let bg = CGColor(srgbRed: 0x0B / 255, green: 0x0D / 255, blue: 0x12 / 255, alpha: 1)

// Ikona 1024 × 1024, měsíc zabírá 64 % šířky (poloměr 32 ze 100).
render(px: 1024, background: bg, logoScale: 1, to: assets.appendingPathComponent("AppIcon.appiconset/AppIcon.png"))

// Launch screen: 120 pt, průhledné pozadí (barvu dává LaunchBackground).
for scale in 1...3 {
    let suffix = scale == 1 ? "" : "@\(scale)x"
    render(px: 120 * scale, background: nil, logoScale: 1,
           to: assets.appendingPathComponent("LaunchLogo.imageset/LaunchLogo\(suffix).png"))
}
