// autor: Codex, gadula-dzwiek-aktualizacje-20260927
import VoiceAgentCore

@MainActor
private final class GlosnikiTestowe: SterowanieGlosnoscia {
    var liczbaZapisow = 0
    var konwersja = true
    var kwantyzuje = false
    func dopasuj(_ id: String, poziomy: [Float]) -> [Float]? { guard konwersja else { return nil }; return kwantyzuje ? poziomy.map { ($0 * 127).rounded() / 127 } : poziomy }
    var odrzuca = false
    var opoznia = false
    var oczekujace: (String, [Float])?
    func potwierdz() { if let (id, wartosc) = oczekujace { poziomy[id] = wartosc; oczekujace = nil } }
    var domyslne: String? = "sluchawki"
    var poziomy: [String: [Float]] = ["sluchawki": [0.8]]
    var domyslneWyjscie: String? { domyslne }
    func odczytaj(_ id: String) -> [Float]? { poziomy[id] }
    func ustaw(_ id: String, poziomy: [Float]) -> Bool { liczbaZapisow += 1; if odrzuca { return false }; if opoznia { oczekujace = (id, poziomy) } else { self.poziomy[id] = poziomy }; return true }
}

@MainActor
enum TestySciszania {
    static func przypadki() -> [(String, @MainActor () async throws -> Void)] {
        [("dźwięk: stały poziom nie powoduje dalszych zapisów", {
            let g = GlosnikiTestowe(); g.kwantyzuje = true; let s = SciszanieDzwieku(wyjscie: g)
            s.rozpocznij(czas: 0); s.krok(czas: 0.5); s.krok(czas: 0.6)
            let przed = g.liczbaZapisow
            for i in 1...100 { s.krok(czas: 0.6 + Double(i) * 0.04) }
            try expectEqual(g.liczbaZapisow, przed)
        }),
        ("dźwięk: odtworzenie oryginału bez ponownej konwersji", {
            let g = GlosnikiTestowe(); let s = SciszanieDzwieku(wyjscie: g)
            s.rozpocznij(czas: 0); s.krok(czas: 0.5); s.krok(czas: 0.6)
            g.konwersja = false; s.zakoncz(czas: 1); s.krok(czas: 2); s.krok(czas: 3)
            try expectEqual(g.poziomy["sluchawki"], [Float(0.8)])
        }),
        ("dźwięk: nowa sesja nie gubi wcześniejszego oczekującego ściszenia", {
            let g = GlosnikiTestowe(); g.opoznia = true; let s = SciszanieDzwieku(wyjscie: g)
            s.rozpocznij(czas: 0); s.krok(czas: 0.5)
            g.odrzuca = true; s.zakoncz(czas: 0.6); s.krok(czas: 1.3)
            g.odrzuca = false; s.rozpocznij(czas: 1.31); s.krok(czas: 1.31)
            g.potwierdz(); s.krok(czas: 1.35); g.opoznia = false
            s.zakoncz(czas: 2); s.krok(czas: 3); s.przywrocNatychmiast()
            try expectEqual(g.poziomy["sluchawki"], [Float(0.8)])
        }),
        ("dźwięk: zaokrąglenie HAL nie jest ręczną zmianą", {
            let g = GlosnikiTestowe(); g.kwantyzuje = true
            g.poziomy["sluchawki"] = [Float(102) / 127]
            let s = SciszanieDzwieku(wyjscie: g)
            s.rozpocznij(czas: 0); s.krok(czas: 0.5); s.krok(czas: 0.6)
            try expectEqual(g.poziomy["sluchawki"], [Float(36) / 127])
            s.zakoncz(czas: 1); s.krok(czas: 2); s.krok(czas: 3)
            try expectEqual(g.poziomy["sluchawki"], [Float(102) / 127])
        }),
        ("dźwięk: odrzucony restore zachowuje wcześniejszy pending w dzienniku", {
            let g = GlosnikiTestowe(); g.opoznia = true; var zapis = [SladGlosnosci]()
            let s = SciszanieDzwieku(wyjscie: g, zapisz: { zapis = $0; return true })
            s.rozpocznij(czas: 0); s.krok(czas: 0.5)
            g.odrzuca = true; s.przywrocNatychmiast(); g.potwierdz(); g.odrzuca = false; g.opoznia = false
            let restart = SciszanieDzwieku(wyjscie: g, zapisane: zapis)
            restart.przywrocNatychmiast()
            try expectEqual(g.poziomy["sluchawki"], [Float(0.8)])
        }),
        ("dźwięk: odrzucony zapis w połowie fade nie blokuje przywrócenia", {
            let g = GlosnikiTestowe(); let s = SciszanieDzwieku(wyjscie: g)
            s.rozpocznij(czas: 0); s.krok(czas: 0.2)
            g.odrzuca = true; s.krok(czas: 0.3); g.odrzuca = false
            s.zakoncz(czas: 1); s.krok(czas: 2); s.krok(czas: 3)
            try expectEqual(g.poziomy["sluchawki"], [Float(0.8)])
        }),
        ("dźwięk: dziennik znika w połowie fade, głośność wraca", {
            let g = GlosnikiTestowe(); var zapisuje = true
            let s = SciszanieDzwieku(wyjscie: g, zapisz: { _ in zapisuje })
            s.rozpocznij(czas: 0); s.krok(czas: 0.2)
            zapisuje = false; s.krok(czas: 0.3)
            s.zakoncz(czas: 1); s.krok(czas: 2); s.krok(czas: 3)
            try expectEqual(g.poziomy["sluchawki"], [Float(0.8)])
        }),
        ("dźwięk: asynchroniczny HAL nie zostawia ściszonego wyjścia", {
            let g = GlosnikiTestowe(); g.opoznia = true
            let s = SciszanieDzwieku(wyjscie: g)
            s.rozpocznij(czas: 0); s.krok(czas: 0.5); s.krok(czas: 0.6)
            g.potwierdz(); s.krok(czas: 0.7)
            s.zakoncz(czas: 1); s.krok(czas: 2); g.potwierdz(); s.krok(czas: 2.1)
            try expectEqual(g.poziomy["sluchawki"], [Float(0.8)])
        }),
        ("dźwięk: nawet ręczna zmiana o jeden punkt procentowy wygrywa", {
            let g = GlosnikiTestowe(); let s = SciszanieDzwieku(wyjscie: g)
            s.rozpocznij(czas: 0); s.krok(czas: 0.5); s.krok(czas: 0.6)
            g.poziomy["sluchawki"] = [0.29]; s.krok(czas: 0.7)
            s.zakoncz(czas: 1); s.krok(czas: 2)
            try expectEqual(g.poziomy["sluchawki"], [Float(0.29)])
        }),
        ("dźwięk: brak zapisu dziennika nie zmienia głośności", {
            let g = GlosnikiTestowe(); let s = SciszanieDzwieku(wyjscie: g, zapisz: { _ in false })
            s.rozpocznij(czas: 0); s.krok(czas: 1)
            try expectEqual(g.poziomy["sluchawki"], [Float(0.8)])
        }),
        ("dźwięk: płynne ściszenie i powrót do poprzedniej głośności", {
            let glosniki = GlosnikiTestowe()
            let s = SciszanieDzwieku(wyjscie: glosniki)
            s.rozpocznij(czas: 0)
            s.krok(czas: 0.2)
            guard let polowa = glosniki.poziomy["sluchawki"]?.first, polowa > 0.28, polowa < 0.8 else {
                throw TestFailure.failed("Brak płynnego przejścia")
            }
            s.krok(czas: 0.4)
            try expectEqual(glosniki.poziomy["sluchawki"], [Float(0.28)])
            s.zakoncz(czas: 1)
            s.krok(czas: 1.7)
            try expectEqual(glosniki.poziomy["sluchawki"], [Float(0.8)])
        }),
        ("dźwięk: ręczna głośność wygrywa przy końcu dyktowania", {
            let g = GlosnikiTestowe(); let s = SciszanieDzwieku(wyjscie: g)
            s.rozpocznij(czas: 0); s.krok(czas: 0.5)
            g.poziomy["sluchawki"] = [0.55]
            s.zakoncz(czas: 1); s.krok(czas: 2)
            s.przywrocNatychmiast()
            try expectEqual(g.poziomy["sluchawki"], [Float(0.55)])
        }),
        ("dźwięk: wyciszone wyjście nigdy nie staje się głośniejsze", {
            let g = GlosnikiTestowe(); g.poziomy["sluchawki"] = [0]
            let s = SciszanieDzwieku(wyjscie: g)
            s.rozpocznij(czas: 0); s.krok(czas: 0.5); s.zakoncz(czas: 1); s.krok(czas: 2)
            try expectEqual(g.poziomy["sluchawki"], [Float(0)])
        }),
        ("dźwięk: restart podczas powrotu zachowuje pierwotny poziom", {
            let g = GlosnikiTestowe(); let s = SciszanieDzwieku(wyjscie: g)
            s.rozpocznij(czas: 0); s.krok(czas: 0.5); s.zakoncz(czas: 1); s.krok(czas: 1.2)
            s.rozpocznij(czas: 1.3); s.krok(czas: 2); s.zakoncz(czas: 3); s.krok(czas: 4)
            try expectEqual(g.poziomy["sluchawki"], [Float(0.8)])
        }),
        ("dźwięk: przełączenie wyjścia odtwarza oba niezależne poziomy", {
            let g = GlosnikiTestowe(); g.poziomy["glosnik"] = [0.4, 0.6]
            let s = SciszanieDzwieku(wyjscie: g)
            s.rozpocznij(czas: 0); s.krok(czas: 0.5)
            g.domyslne = "glosnik"; s.krok(czas: 1); s.krok(czas: 2)
            try expectEqual(g.poziomy["sluchawki"], [Float(0.8)])
            s.przywrocNatychmiast()
            try expectEqual(g.poziomy["glosnik"], [Float(0.4), Float(0.6)])
        }),
        ("dźwięk: odłączenie i powrót wyjścia po sesji", {
            let g = GlosnikiTestowe(); let s = SciszanieDzwieku(wyjscie: g)
            s.rozpocznij(czas: 0); s.krok(czas: 0.5)
            let sciszone = g.poziomy["sluchawki"]
            g.poziomy["sluchawki"] = nil; g.domyslne = nil; s.krok(czas: 1); s.zakoncz(czas: 2)
            g.poziomy["sluchawki"] = sciszone; s.krok(czas: 3)
            try expectEqual(g.poziomy["sluchawki"], [Float(0.8)])
        }),
        ("dźwięk: odzyskiwanie po przerwaniu procesu", {
            let g = GlosnikiTestowe(); var zapis = [SladGlosnosci]()
            let s = SciszanieDzwieku(wyjscie: g, zapisz: { zapis = $0; return true })
            s.rozpocznij(czas: 0); s.krok(czas: 0.3)
            let poRestarcie = SciszanieDzwieku(wyjscie: g, zapisane: zapis)
            poRestarcie.przywrocNatychmiast()
            try expectEqual(g.poziomy["sluchawki"], [Float(0.8)])
        }),
        ("dźwięk: błąd sesji i anulowanie odtwarzają poziom", {
            for przerwij in [false, true] {
                let g = GlosnikiTestowe(); let s = SciszanieDzwieku(wyjscie: g)
                let k = KoordynatorDyktowania(audio: AtrapaAudioZNagraniem(czasTrwania: 2, szczytowaGlosnosc: 0.5), transcribing: AtrapaTranscribing(tekst: "test"), inserting: AtrapaTextInserting(), permissions: AtrapaPermissionChecking(mikrofon: true))
                k.poZmianieGotowosci = { stan in
                    if stan == .mikrofon || stan == .gotowa { s.rozpocznij(czas: 0) }
                    else { s.zakoncz(czas: 1) }
                }
                await k.handleWyzwalacz(); s.krok(czas: 0.5)
                if przerwij { await k.przerwij(komunikat: "Odłączono") } else { await k.anuluj() }
                s.krok(czas: 2)
                try expectEqual(g.poziomy["sluchawki"], [Float(0.8)])
            }
        })]
    }
}
