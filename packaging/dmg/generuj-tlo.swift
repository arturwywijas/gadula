// Uruchom: swift packaging/dmg/generuj-tlo.swift packaging/dmg
import AppKit

// Tło instalatora Gaduły bez napisów: tylko iryzacyjne poświaty pod ikonami i strzałka.
// Okno 680×380 pt; ikony w pozycjach Findera (165, 180) i (515, 180). Render 1x i 2x.
let katalogWyjscia = CommandLine.arguments[1]
let W: CGFloat = 680, H: CGFloat = 380, yIkon: CGFloat = 180
let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
let tlo = CGColor(srgbRed: 0.039, green: 0.039, blue: 0.043, alpha: 1)
let iryzacja: [CGColor] = [
    CGColor(srgbRed: 0.45, green: 0.82, blue: 0.98, alpha: 1),
    CGColor(srgbRed: 0.74, green: 0.58, blue: 0.98, alpha: 1),
    CGColor(srgbRed: 1.00, green: 0.66, blue: 0.64, alpha: 1),
    CGColor(srgbRed: 0.68, green: 0.95, blue: 0.66, alpha: 1)]

func rysuj(_ skala: CGFloat, _ nazwa: String) {
    let ctx = CGContext(data: nil, width: Int(W * skala), height: Int(H * skala), bitsPerComponent: 8, bytesPerRow: 0,
                        space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: skala, y: skala)
    ctx.setFillColor(tlo); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    // Poświaty pod ikonami: niebieska za Gadułą, fioletowo-różowa za folderem Aplikacje.
    for (x, kolory) in [(CGFloat(165), [iryzacja[0], iryzacja[1]]), (CGFloat(515), [iryzacja[1], iryzacja[2]])] {
        for (i, k) in kolory.enumerated() {
            let g = CGGradient(colorsSpace: rgb, colors: [k.copy(alpha: 0.13)!, k.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
            let c = CGPoint(x: x + (i == 0 ? -18 : 18), y: H - yIkon + (i == 0 ? 10 : -10))
            ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: 150, options: [])
        }
    }
    // Strzałka w kolorach iryzacji z miękką poświatą, na wysokości środka ikon.
    let y = H - yIkon + 8
    let luk = CGMutablePath()
    luk.move(to: CGPoint(x: 262, y: y))
    luk.addQuadCurve(to: CGPoint(x: 414, y: y), control: CGPoint(x: 338, y: y + 16))
    let grot = CGMutablePath()
    grot.move(to: CGPoint(x: 402, y: y + 10)); grot.addLine(to: CGPoint(x: 416, y: y)); grot.addLine(to: CGPoint(x: 402, y: y - 10))
    let ksztalt = luk.copy(strokingWithWidth: 3.5, lineCap: .round, lineJoin: .round, miterLimit: 4)
        .union(grot.copy(strokingWithWidth: 3.5, lineCap: .round, lineJoin: .round, miterLimit: 4))
    let g = CGGradient(colorsSpace: rgb, colors: iryzacja as CFArray, locations: nil)!
    for (blur, alfa) in [(CGFloat(12), CGFloat(0.55)), (0, 1)] {
        ctx.saveGState()
        if blur > 0 { ctx.setShadow(offset: .zero, blur: blur, color: iryzacja[1].copy(alpha: alfa)) }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.addPath(ksztalt); ctx.clip()
        ctx.drawLinearGradient(g, start: CGPoint(x: 262, y: y), end: CGPoint(x: 416, y: y), options: [])
        ctx.endTransparencyLayer(); ctx.restoreGState()
    }
    try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: "\(katalogWyjscia)/\(nazwa)"))
}
rysuj(1, "tlo-instalatora.png")
rysuj(2, "tlo-instalatora@2x.png")
print("gotowe")
