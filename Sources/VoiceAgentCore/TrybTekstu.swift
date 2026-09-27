// autor: Codex, gadula-dyktowanie-20260927
import Foundation

public enum TrybTekstu: String, CaseIterable, Sendable {
    case wierny, uporzadkowany
    public static let klucz = "tekst.tryb"
    public var etykieta: String { self == .wierny ? "Wierny zapis" : "Uporządkowany tekst" }
    public static func wczytaj(z magazynu: MagazynUstawien) -> Self {
        Self(rawValue: magazynu.string(klucz: klucz, domyslna: Self.wierny.rawValue)) ?? .wierny
    }
}

public func formatujTekst(_ tekst: String, tryb: TrybTekstu) -> String {
    guard tryb == .uporzadkowany else { return przygotujTekstDoWstawienia(tekst) }
    let tekst = przygotujTekstDoWstawienia(tekst)
    // Komenda musi być osobnym zdaniem. Frazy w zdaniu i cytaty są treścią.
    let wzor = #"(?i)(^|(?<=[.!?])\s+)(nowy akapit|nowy wiersz|nowy punkt)\s*(?:[.!?](?=\s|$)|$)"#
    let regex = try! NSRegularExpression(pattern: wzor)
    var wynik = tekst
    let ns = tekst as NSString
    let cytaty = try! NSRegularExpression(pattern: #""[^"]*(?:"|$)|„[^”]*(?:”|$)|“[^”]*(?:”|$)|«[^»]*(?:»|$)|`[^`]*(?:`|$)"#)
    let chronione = cytaty.matches(in: tekst, range: NSRange(location: 0, length: ns.length)).map(\.range)
    for m in regex.matches(in: tekst, range: NSRange(location: 0, length: ns.length)).reversed() {
        guard !chronione.contains(where: { NSLocationInRange(m.range(at: 2).location, $0) }) else { continue }
        let komenda = ns.substring(with: m.range(at: 2)).lowercased()
        let zamiana: String
        switch komenda {
        case "nowy akapit": zamiana = "\n\n"
        case "nowy wiersz": zamiana = "\n"
        default:
            let reszta = (wynik as NSString).substring(from: m.range.location + m.range.length)
            let oryginalnaReszta = ns.substring(from: m.range.location + m.range.length)
            let kolejnaKomenda = oryginalnaReszta.range(of: #"(?i)^\s*nowy (akapit|wiersz|punkt)\s*(?:[.!?]|$)"#, options: .regularExpression) != nil
            zamiana = kolejnaKomenda || reszta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n- "
        }
        if let zakres = Range(m.range, in: wynik) { wynik.replaceSubrange(zakres, with: zamiana) }
    }
    wynik = wynik.replacingOccurrences(of: #"[\t ]+([,;!?]|\.(?![\p{L}\p{N}]))"#, with: "$1", options: .regularExpression)
    wynik = wynik.components(separatedBy: .newlines).map {
        $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: #"[\t ]{2,}"#, with: " ", options: .regularExpression)
    }.joined(separator: "\n")
    wynik = wynik.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
    wynik = przygotujTekstDoWstawienia(wynik)
    guard wynik.count >= 400, !wynik.contains("\n"), chronione.isEmpty else { return wynik }
    var zdania: [String] = []
    wynik.enumerateSubstrings(in: wynik.startIndex..<wynik.endIndex, options: .bySentences) { zdanie, _, _, _ in
        if let zdanie { zdania.append(zdanie.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
    guard zdania.count >= 5 else { return wynik }
    return stride(from: 0, to: zdania.count, by: 3).map {
        zdania[$0..<min($0 + 3, zdania.count)].joined(separator: " ")
    }.joined(separator: "\n\n")
}
