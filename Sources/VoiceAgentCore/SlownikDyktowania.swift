// autor: Codex, gadula-dyktowanie-20260927
import Foundation

public struct SlownikDyktowania: Sendable, Equatable {
    public static let klucz = "tekst.slownik"
    public static let limitNazw = 40
    public static let limitZnakow = 1000
    public let nazwy: [String]
    public init(_ tekst: String) {
        var widziane = Set<String>()
        var wynik: [String] = []
        var znaki = 0
        for linia in tekst.components(separatedBy: .newlines) {
            let nazwa = linia.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !nazwa.isEmpty, nazwa.count <= 80,
                  !nazwa.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  widziane.insert(nazwa.lowercased()).inserted else { continue }
            guard wynik.count < Self.limitNazw, znaki + nazwa.count + (wynik.isEmpty ? 0 : 1) <= Self.limitZnakow else { break }
            znaki += nazwa.count + (wynik.isEmpty ? 0 : 1)
            wynik.append(nazwa)
        }
        nazwy = wynik
    }
    public static func wczytaj(z magazynu: MagazynUstawien) -> Self {
        Self(magazynu.string(klucz: klucz, domyslna: "Gaduła"))
    }
    /// Podpowiedź kończy się na granicy nazwy, nigdy w jej połowie.
    public func podpowiedz(limit: Int, koszt: (String) -> Int) -> String {
        var wybrane: [String] = []
        for nazwa in nazwy {
            let propozycja = (wybrane + [nazwa]).joined(separator: ", ") + "."
            guard koszt(propozycja) <= limit else { break }
            wybrane.append(nazwa)
        }
        return wybrane.isEmpty ? "" : wybrane.joined(separator: ", ") + "."
    }
    public var tekst: String { nazwy.joined(separator: "\n") }
    public var podpowiedz: String { nazwy.joined(separator: ", ") }
}
