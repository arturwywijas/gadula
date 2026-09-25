import AppKit
import CoreGraphics

public enum StanIkonyGaduly: String, CaseIterable, Sendable {
    case bezczynna
    case nagrywanie
    case przetwarzanie
    case blad
    case zajetosc
    case przygotowanieModelu
}

/// Wspólna geometria ikony aplikacji i monochromatycznego glifu paska menu.
@MainActor
public enum IkonaGaduly {
    private static let rozmiarGeometrii: CGFloat = 1024
    private static let tloIkony = CGColor(srgbRed: 0.039, green: 0.039, blue: 0.043, alpha: 1)
    private static let jasnyPas = CGColor(srgbRed: 0.957, green: 0.953, blue: 0.937, alpha: 1)
    private static let koloryIryzacji = [
        CGColor(srgbRed: 0.45, green: 0.82, blue: 0.98, alpha: 1),
        CGColor(srgbRed: 0.74, green: 0.58, blue: 0.98, alpha: 1),
        CGColor(srgbRed: 1.00, green: 0.66, blue: 0.64, alpha: 1),
        CGColor(srgbRed: 0.68, green: 0.95, blue: 0.66, alpha: 1),
    ]

    public static func ikonaAplikacji(piksele: Int) -> CGImage? {
        guard piksele > 0, let kontekst = utworzKontekst(szerokosc: piksele, wysokosc: piksele) else { return nil }
        rysujIkoneAplikacji(w: kontekst, piksele: CGFloat(piksele))
        return kontekst.makeImage()
    }

    /// Zwraca szablon z reprezentacją 1x i 2x, gotowy dla NSStatusItem.
    public static func obrazPaska(stan: StanIkonyGaduly) -> NSImage? {
        let rozmiarPunktow = NSSize(width: 18, height: 18)
        let obraz = NSImage(size: rozmiarPunktow)
        for piksele in [18, 36] {
            guard let cgImage = glifPaska(stan: stan, piksele: piksele, tusz: CGColor(gray: 1, alpha: 1)) else { return nil }
            let reprezentacja = NSBitmapImageRep(cgImage: cgImage)
            reprezentacja.size = rozmiarPunktow
            obraz.addRepresentation(reprezentacja)
        }
        obraz.isTemplate = true
        return obraz
    }

    public static func glifPaska(stan: StanIkonyGaduly, piksele: Int, tusz: CGColor) -> CGImage? {
        guard piksele > 0, let kontekst = utworzKontekst(szerokosc: piksele, wysokosc: piksele) else { return nil }
        kontekst.scaleBy(x: CGFloat(piksele) / rozmiarGeometrii, y: CGFloat(piksele) / rozmiarGeometrii)
        kontekst.addPath(glifG(rozmiar: rozmiarGeometrii))
        kontekst.setFillColor(tusz)
        kontekst.fillPath()
        rysujZnacznik(stan: stan, w: kontekst, tusz: tusz)
        return kontekst.makeImage()
    }

    private static func rysujIkoneAplikacji(w kontekst: CGContext, piksele: CGFloat) {
        let s = rozmiarGeometrii
        kontekst.scaleBy(x: piksele / s, y: piksele / s)
        let pole = CGRect(x: 100, y: 100, width: 824, height: 824)
        kontekst.addPath(CGPath(roundedRect: pole, cornerWidth: 185, cornerHeight: 185, transform: nil))
        kontekst.setFillColor(tloIkony)
        kontekst.fillPath()
        kontekst.translateBy(x: pole.minX, y: pole.minY)
        kontekst.scaleBy(x: pole.width / s, y: pole.height / s)
        kontekst.addPath(lukZOgonkiem(s))
        kontekst.setFillColor(jasnyPas)
        kontekst.fillPath()
        rysujIryzacje(w: kontekst, ksztalt: poprzeczka(s))
    }

    private static func glifG(rozmiar s: CGFloat) -> CGPath {
        lukZOgonkiem(s).union(poprzeczka(s))
    }

    // Geometria łuku, ogonka i poprzeczki odpowiada zaakceptowanemu wzorowi Artura.
    private static func lukZOgonkiem(_ s: CGFloat) -> CGPath {
        let c = CGPoint(x: s * 0.5, y: s * 0.5)
        let promien = s * 0.28
        let grubosc = s * 0.105
        let luk = CGMutablePath()
        luk.addArc(center: c, radius: promien, startAngle: .pi * 0.17, endAngle: .pi * 1.83, clockwise: false)
        let pas = luk.copy(strokingWithWidth: grubosc, lineCap: .round, lineJoin: .round, miterLimit: 4)

        func biegun(_ r: CGFloat, _ kat: CGFloat) -> CGPoint {
            CGPoint(x: c.x + cos(kat) * r, y: c.y + sin(kat) * r)
        }

        let kat = CGFloat.pi * 1.25
        let ogonek = CGMutablePath()
        ogonek.move(to: biegun(promien, kat + 0.13))
        ogonek.addLine(to: biegun(promien + s * 0.17, kat - 0.02))
        ogonek.addLine(to: biegun(promien, kat - 0.15))
        ogonek.closeSubpath()
        return pas.union(ogonek)
    }

    private static func poprzeczka(_ s: CGFloat) -> CGPath {
        let c = CGPoint(x: s * 0.5, y: s * 0.5)
        let promien = s * 0.28
        let sciezka = CGMutablePath()
        sciezka.move(to: CGPoint(x: c.x + promien * 0.12, y: c.y - promien * 0.04))
        sciezka.addLine(to: CGPoint(x: c.x + promien, y: c.y - promien * 0.04))
        return sciezka.copy(strokingWithWidth: s * 0.105, lineCap: .round, lineJoin: .round, miterLimit: 4)
    }

    private static func rysujIryzacje(w kontekst: CGContext, ksztalt: CGPath) {
        let kolory = koloryIryzacji as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: kolory, locations: nil) else { return }
        let granice = ksztalt.boundingBox
        kontekst.saveGState()
        kontekst.addPath(ksztalt)
        kontekst.clip()
        kontekst.drawLinearGradient(
            gradient,
            start: CGPoint(x: granice.minX, y: granice.midY),
            end: CGPoint(x: granice.maxX, y: granice.midY),
            options: []
        )
        kontekst.restoreGState()
    }

    private static func rysujZnacznik(stan: StanIkonyGaduly, w kontekst: CGContext, tusz: CGColor) {
        kontekst.saveGState()
        kontekst.setFillColor(tusz)
        kontekst.setStrokeColor(tusz)
        kontekst.setLineCap(.round)
        kontekst.setLineJoin(.round)

        switch stan {
        case .bezczynna:
            break
        case .nagrywanie:
            kontekst.fillEllipse(in: CGRect(x: 0.765 * 1024, y: 0.765 * 1024, width: 0.17 * 1024, height: 0.17 * 1024))
        case .przetwarzanie:
            for x in [0.70, 0.82, 0.94] {
                kontekst.fillEllipse(in: CGRect(x: x * 1024 - 0.055 * 1024, y: 0.88 * 1024 - 0.055 * 1024, width: 0.11 * 1024, height: 0.11 * 1024))
            }
        case .blad:
            kontekst.setLineWidth(0.052 * 1024)
            kontekst.move(to: CGPoint(x: 0.85 * 1024, y: 0.78 * 1024))
            kontekst.addLine(to: CGPoint(x: 0.85 * 1024, y: 0.91 * 1024))
            kontekst.strokePath()
            kontekst.fillEllipse(in: CGRect(x: 0.85 * 1024 - 0.026 * 1024, y: 0.70 * 1024 - 0.026 * 1024, width: 0.052 * 1024, height: 0.052 * 1024))
        case .zajetosc:
            let klepsydra = CGMutablePath()
            klepsydra.move(to: CGPoint(x: 0.76 * 1024, y: 0.93 * 1024))
            klepsydra.addLine(to: CGPoint(x: 0.94 * 1024, y: 0.93 * 1024))
            klepsydra.addLine(to: CGPoint(x: 0.85 * 1024, y: 0.85 * 1024))
            klepsydra.closeSubpath()
            klepsydra.move(to: CGPoint(x: 0.76 * 1024, y: 0.75 * 1024))
            klepsydra.addLine(to: CGPoint(x: 0.94 * 1024, y: 0.75 * 1024))
            klepsydra.addLine(to: CGPoint(x: 0.85 * 1024, y: 0.83 * 1024))
            klepsydra.closeSubpath()
            kontekst.addPath(klepsydra)
            kontekst.fillPath()
        case .przygotowanieModelu:
            let blysk = CGMutablePath()
            let srodek = CGPoint(x: 0.85 * 1024, y: 0.84 * 1024)
            let punkty: [(CGFloat, CGFloat)] = [
                (0, 0.11), (0.035, 0.035), (0.11, 0), (0.035, -0.035),
                (0, -0.11), (-0.035, -0.035), (-0.11, 0), (-0.035, 0.035),
            ]
            for (index, (dx, dy)) in punkty.enumerated() {
                let punkt = CGPoint(x: srodek.x + dx * 1024, y: srodek.y + dy * 1024)
                if index == 0 { blysk.move(to: punkt) } else { blysk.addLine(to: punkt) }
            }
            blysk.closeSubpath()
            kontekst.addPath(blysk)
            kontekst.fillPath()
        }

        kontekst.restoreGState()
    }

    private static func utworzKontekst(szerokosc: Int, wysokosc: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: szerokosc,
            height: wysokosc,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}
