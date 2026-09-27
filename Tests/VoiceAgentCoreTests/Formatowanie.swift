// autor: Codex, gadula-dyktowanie-20260927
import VoiceAgentCore

enum TestyFormatowania {
    @MainActor static func przypadki() -> [(String, @MainActor () async throws -> Void)] {
        let pary = [
            ("Pierwszy akapit. Nowy akapit. Drugi akapit.", "Pierwszy akapit.\n\nDrugi akapit."),
            ("Nowy punkt. Mleko. Nowy punkt. Chleb.", "- Mleko.\n- Chleb."),
            ("Dzień dobry. Nowy wiersz. Dziękuję.", "Dzień dobry.\nDziękuję."),
            ("Tekst. Nowy punkt.", "Tekst."),
            ("Akapit. Nowy akapit. Nowy akapit. Drugi.", "Akapit.\n\nDrugi."),
            ("Tak , dobrze .", "Tak, dobrze."),
            ("Dodaj nowy akapit w umowie.", "Dodaj nowy akapit w umowie."),
            ("Powiedział „nowy akapit”, a potem wyszedł.", "Powiedział „nowy akapit”, a potem wyszedł."),
            ("Nie, nie wyłączaj mikrofonu.", "Nie, nie wyłączaj mikrofonu."),
            ("Tak, tak ma zostać.", "Tak, tak ma zostać."),
            ("Zamów 2,5 kg, nie 25 kg. Kod 00123, godzina 12:05.", "Zamów 2,5 kg, nie 25 kg. Kod 00123, godzina 12:05."),
            ("iOS, eBay, C++, C#, .NET i Node.js.", "iOS, eBay, C++, C#, .NET i Node.js."),
            ("test@example.com https://example.com/a?x=1.2 src/App.swift", "test@example.com https://example.com/a?x=1.2 src/App.swift"),
            ("Nowy akapit.", ""),
            ("Nowy akapit", ""),
            ("  Nowy punkt. Mleko.", "- Mleko."),
            ("Powiedział: „Pierwsze zdanie. Nowy akapit. Drugie zdanie”.", "Powiedział: „Pierwsze zdanie. Nowy akapit. Drugie zdanie”."),
            ("Nowy punkt. Nowy punkt. Chleb.", "- Chleb.")
        ]
        let dlugieZdanie = "To jest dłuższe zdanie o planowanym spotkaniu zespołu i zapisaniu wszystkich ustaleń po rozmowie."
        let dlugiTekst = Array(repeating: dlugieZdanie, count: 6).joined(separator: " ")
        let akapity = Array(repeating: Array(repeating: dlugieZdanie, count: 3).joined(separator: " "), count: 2).joined(separator: "\n\n")
        let akapitTests: [(String, @MainActor () async throws -> Void)] = [("tekst: automatyczne akapity w dłuższej wypowiedzi", {
            try expectEqual(formatujTekst(dlugiTekst, tryb: .uporzadkowany), akapity)
            try expectEqual(formatujTekst(akapity, tryb: .uporzadkowany), akapity)
        })]
        return akapitTests + pary.enumerated().map { i, para in
            ("tekst: formatowanie i zachowanie sensu \(i)", {
                let wynik = formatujTekst(para.0, tryb: .uporzadkowany)
                try expectEqual(wynik, para.1)
                try expectEqual(formatujTekst(wynik, tryb: .uporzadkowany), wynik)
                try expectEqual(formatujTekst(para.0, tryb: .wierny), przygotujTekstDoWstawienia(para.0))
            })
        }
    }
}
