import AppKit
import CoreText
import Foundation
import GadulaArtwork

private struct RozmiarIkony {
    let punktow: Int
    let skala: Int
    let nazwa: String
}

@main
@MainActor
private enum GeneratorIkon {
    static func main() throws {
        let katalogRepo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let katalogIkon = katalogRepo.appendingPathComponent("packaging/ikona", isDirectory: true)
        let katalogPodgladu = katalogRepo.appendingPathComponent("dist/ikona-podglad", isDirectory: true)
        try FileManager.default.createDirectory(at: katalogIkon, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: katalogPodgladu, withIntermediateDirectories: true)

        let tymczasowyIconset = FileManager.default.temporaryDirectory
            .appendingPathComponent("Gadula-\(UUID().uuidString).iconset", isDirectory: true)
        try FileManager.default.createDirectory(at: tymczasowyIconset, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tymczasowyIconset) }

        let rozmiary = [
            RozmiarIkony(punktow: 16, skala: 1, nazwa: "icon_16x16.png"),
            RozmiarIkony(punktow: 16, skala: 2, nazwa: "icon_16x16@2x.png"),
            RozmiarIkony(punktow: 32, skala: 1, nazwa: "icon_32x32.png"),
            RozmiarIkony(punktow: 32, skala: 2, nazwa: "icon_32x32@2x.png"),
            RozmiarIkony(punktow: 128, skala: 1, nazwa: "icon_128x128.png"),
            RozmiarIkony(punktow: 128, skala: 2, nazwa: "icon_128x128@2x.png"),
            RozmiarIkony(punktow: 256, skala: 1, nazwa: "icon_256x256.png"),
            RozmiarIkony(punktow: 256, skala: 2, nazwa: "icon_256x256@2x.png"),
            RozmiarIkony(punktow: 512, skala: 1, nazwa: "icon_512x512.png"),
            RozmiarIkony(punktow: 512, skala: 2, nazwa: "icon_512x512@2x.png"),
        ]
        for rozmiar in rozmiary {
            let piksele = rozmiar.punktow * rozmiar.skala
            guard let obraz = IkonaGaduly.ikonaAplikacji(piksele: piksele) else {
                throw BladGeneratora.brakObrazu(rozmiar.nazwa)
            }
            try zapiszPNG(obraz, do: tymczasowyIconset.appendingPathComponent(rozmiar.nazwa))
        }

        let ikonaICNS = katalogIkon.appendingPathComponent("Gadula.icns")
        try? FileManager.default.removeItem(at: ikonaICNS)
        let iconutil = Process()
        iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        iconutil.arguments = ["-c", "icns", "-o", ikonaICNS.path, tymczasowyIconset.path]
        try iconutil.run()
        iconutil.waitUntilExit()
        guard iconutil.terminationStatus == 0 else { throw BladGeneratora.iconutil(iconutil.terminationStatus) }

        guard let duzaIkona = IkonaGaduly.ikonaAplikacji(piksele: 1024) else {
            throw BladGeneratora.brakObrazu("Gadula-ikona-1024.png")
        }
        try zapiszPNG(duzaIkona, do: katalogPodgladu.appendingPathComponent("Gadula-ikona-1024.png"))
        try zapiszArkuszStanow(do: katalogPodgladu.appendingPathComponent("Gadula-stany-paska-2x.png"))
        print("Wygenerowano \(ikonaICNS.path) oraz podglądy w \(katalogPodgladu.path)")
    }

    private static func zapiszPNG(_ obraz: CGImage, do url: URL) throws {
        let reprezentacja = NSBitmapImageRep(cgImage: obraz)
        guard let dane = reprezentacja.representation(using: .png, properties: [:]) else {
            throw BladGeneratora.nieMoznaZapisac(url.lastPathComponent)
        }
        try dane.write(to: url)
    }

    private static func zapiszArkuszStanow(do url: URL) throws {
        let szerokoscPunktow = 720
        let wysokoscPunktow = 228
        guard let kontekst = CGContext(
            data: nil,
            width: szerokoscPunktow * 2,
            height: wysokoscPunktow * 2,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw BladGeneratora.nieMoznaZapisac(url.lastPathComponent) }

        kontekst.scaleBy(x: 2, y: 2)
        let ciemny = CGColor(srgbRed: 0.039, green: 0.039, blue: 0.043, alpha: 1)
        let jasny = CGColor(srgbRed: 0.957, green: 0.953, blue: 0.937, alpha: 1)
        kontekst.setFillColor(ciemny)
        kontekst.fill(CGRect(x: 0, y: 0, width: 360, height: wysokoscPunktow))
        kontekst.setFillColor(jasny)
        kontekst.fill(CGRect(x: 360, y: 0, width: 360, height: wysokoscPunktow))

        let nazwy: [(StanIkonyGaduly, String)] = [
            (.bezczynna, "Bezczynność"),
            (.nagrywanie, "Nagrywanie"),
            (.przetwarzanie, "Przetwarzanie"),
            (.blad, "Błąd"),
            (.zajetosc, "Zajętość"),
            (.przygotowanieModelu, "Przygotowanie modelu"),
        ]
        for (indeks, (stan, etykieta)) in nazwy.enumerated() {
            let y = CGFloat(wysokoscPunktow - 32 - indeks * 32)
            for (poczatek, tusz) in [(CGFloat(0), CGColor(gray: 1, alpha: 1)), (CGFloat(360), CGColor(gray: 0, alpha: 1))] {
                if let glif = IkonaGaduly.glifPaska(stan: stan, piksele: 36, tusz: tusz) {
                    kontekst.draw(glif, in: CGRect(x: poczatek + 18, y: y - 9, width: 18, height: 18))
                }
            }
            rysujTekst(etykieta, w: kontekst, x: 52, y: y - 5, kolor: CGColor(gray: 1, alpha: 1))
            rysujTekst(etykieta, w: kontekst, x: 412, y: y - 5, kolor: CGColor(gray: 0, alpha: 1))
        }
        guard let obraz = kontekst.makeImage() else { throw BladGeneratora.nieMoznaZapisac(url.lastPathComponent) }
        try zapiszPNG(obraz, do: url)
    }

    private static func rysujTekst(_ tekst: String, w kontekst: CGContext, x: CGFloat, y: CGFloat, kolor: CGColor) {
        let font = CTFontCreateWithName("Helvetica" as CFString, 14, nil)
        let atrybuty: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): kolor,
        ]
        let wiersz = CTLineCreateWithAttributedString(NSAttributedString(string: tekst, attributes: atrybuty))
        kontekst.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(wiersz, kontekst)
    }

}

private enum BladGeneratora: Error {
    case brakObrazu(String)
    case nieMoznaZapisac(String)
    case iconutil(Int32)
}
