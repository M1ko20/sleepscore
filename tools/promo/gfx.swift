import AppKit
let W: CGFloat = 1080, H: CGFloat = 1920
let bg = NSColor(srgbRed: 0x0B/255, green: 0x0D/255, blue: 0x12/255, alpha: 1)
let accent = NSColor(srgbRed: 0xF5/255, green: 0xC5/255, blue: 0x42/255, alpha: 1)
let text1 = NSColor(srgbRed: 0xF2/255, green: 0xF1/255, blue: 0xEC/255, alpha: 1)
let text2 = NSColor(srgbRed: 0x9A/255, green: 0xA0/255, blue: 0xAB/255, alpha: 1)
let out = CommandLine.arguments[1]
// telefon: šířka 700, poměr 1178x2556
let pw: CGFloat = 700; let ph: CGFloat = (CGFloat(700) * CGFloat(2556) / CGFloat(1178)).rounded()
let px = ((W - pw) / 2).rounded(), pyTop: CGFloat = H - ph - 40   // od shora
func font(_ s: CGFloat, _ w: NSFont.Weight, condensed: Bool = false) -> NSFont {
    condensed ? NSFont.systemFont(ofSize: s, weight: w, width: .condensed) : NSFont.systemFont(ofSize: s, weight: w)
}
func draw(_ str: String, _ f: NSFont, _ c: NSColor, x: CGFloat, yTop: CGFloat, width: CGFloat, align: NSTextAlignment = .center, kern: CGFloat = 0) {
    let p = NSMutableParagraphStyle(); p.alignment = align; p.lineSpacing = -4
    let a = NSAttributedString(string: str, attributes: [.font: f, .foregroundColor: c, .paragraphStyle: p, .kern: kern])
    let r = a.boundingRect(with: NSSize(width: width, height: 1000), options: [.usesLineFragmentOrigin])
    a.draw(with: NSRect(x: x, y: H - yTop - r.height, width: width, height: r.height), options: [.usesLineFragmentOrigin])
}
func png(_ name: String, _ body: () -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    body()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}
// rám: pozadí s dírou se zaoblenými rohy + titulek nahoře
func frame(_ name: String, label: String, title: String) {
    png(name) {
        let path = NSBezierPath(rect: NSRect(x: 0, y: 0, width: W, height: H))
        let hole = NSRect(x: px, y: 40, width: pw, height: ph)
        path.append(NSBezierPath(roundedRect: hole, xRadius: 62, yRadius: 62).reversed)
        bg.setFill(); path.fill()
        NSColor(srgbRed: 0x26/255, green: 0x2B/255, blue: 0x36/255, alpha: 1).setStroke()
        let rim = NSBezierPath(roundedRect: hole.insetBy(dx: -3, dy: -3), xRadius: 65, yRadius: 65); rim.lineWidth = 6; rim.stroke()
        draw(label.uppercased(), font(26, .semibold), accent, x: 60, yTop: 52, width: W - 120, kern: 3)
        draw(title, font(64, .black, condensed: true), text1, x: 60, yTop: 92, width: W - 120)
    }
}
let scenes: [(String, String, String)] = [
    ("feed", "Feed", "Každé ráno je tvoje noc karta"),
    ("night", "Detail noci", "Fáze, tep, rozpad skóre"),
    ("challenges", "Výzvy", "Vyzvi kámoše. Sázku si napíšete sami."),
    ("challenge", "Souboj", "Rozhoduje jen sleep score"),
    ("result", "Konec výzvy", "Prohraješ? Přijdeš o duši."),
    ("profile", "Profil", "Bilance, odznaky, co ti kazí spánek"),
    ("recap", "Pondělí", "Týden v číslech"),
    ("wrapped", "Konec roku", "Sleep Wrapped"),
    ("settings", "Notifikace", "Ozveme se, jen když chceš"),
]
for (n, l, t) in scenes { frame("frame_\(n)", label: l, title: t) }
func card(_ name: String, kicker: String, big: String, sub: String) {
    png(name) {
        bg.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
        draw(kicker.uppercased(), font(30, .semibold), accent, x: 80, yTop: 700, width: W - 160, kern: 4)
        draw(big, font(190, .black, condensed: true), text1, x: 40, yTop: 760, width: W - 80)
        draw(sub, font(46, .semibold), text2, x: 80, yTop: 1010, width: W - 160)
    }
}
card("intro", kicker: "Spánek jako sport", big: "BEDRIVAL", sub: "Spíš líp než kámoši?\nDokaž to.")
card("outro", kicker: "Jen na pozvánku", big: "BEDRIVAL", sub: "Brzy na iPhonu.")
print("px=\(Int(px)) pyTop=\(Int(pyTop)) pw=\(Int(pw)) ph=\(Int(ph))")
