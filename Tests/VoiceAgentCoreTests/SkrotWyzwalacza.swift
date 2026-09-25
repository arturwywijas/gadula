import Foundation
import VoiceAgentCore

/// T07 nie dopisuje do `main.swift` (granica z ticketem 05). Harness dokleja
/// `TestySkrotuWyzwalacza.przypadki()` do listy uruchamianej przez `runTests`.
enum TestySkrotuWyzwalacza {
    static func przypadki() -> [(String, @MainActor () async throws -> Void)] {
        [
            ("FN10: limit i odlaczenie powiadamiaja o mozliwosci zastosowania ustawien", {
                let k = KoordynatorDyktowania(audio: AtrapaAudioCapturing(),
                    transcribing: AtrapaTranscribing(tekst: "test"), inserting: AtrapaTextInserting(),
                    permissions: AtrapaPermissionChecking(mikrofon: true))
                var zakonczenia = 0
                k.poZakonczeniuSesji = { zakonczenia += 1 }
                await k.handleWyzwalacz()
                try expectEqual(zakonczenia, 0)
                await k.zakonczNagrywanie() // ta sama droga, ktora wywoluje limit audio
                try expectEqual(k.stan, .bezczynny)
                try expectEqual(zakonczenia, 1)
                await k.handleWyzwalacz()
                await k.przerwij(komunikat: "Mikrofon został odłączony.")
                try expectEqual(k.stan, .bezczynny)
                try expectEqual(zakonczenia, 2)
                await k.przerwij(komunikat: "ponowne powiadomienie")
                try expectEqual(zakonczenia, 2)
            }),
            ("FN10: stare zapisy zachowuja klawisz i wynikajacy tryb", {
                let magazyn = MagazynUstawien(zrodlo: PamiecMagazynKluczy())
                let stare: [(String, UstawienieSkrotu)] = [
                    (#"{"kind":"keyCombo","keyCode":49,"modifierFlags":524288}"#, .optionSpace),
                    (#"{"kind":"modifierOnly","solo":"fn","modifierFlags":0}"#, .fnHotkey),
                    (#"{"kind":"keyCombo","keyCode":36,"modifierFlags":1048576}"#,
                     UstawienieSkrotu(kind: .keyCombo, solo: nil, keyCode: 36, modifierFlags: 1_048_576)),
                ]
                for (json, oczekiwany) in stare {
                    magazyn.ustaw(json, klucz: "skrot")
                    try expectEqual(UstawienieSkrotu.wczytaj(z: magazyn), oczekiwany)
                    try expectEqual(magazyn.string(klucz: "skrot", domyslna: ""), json)
                }
            }),
            ("FN10: kazda kombinacja dziala w obu trybach i zachowuje zapis", {
                let magazyn = MagazynUstawien(zrodlo: PamiecMagazynKluczy())
                let kombinacje: [UstawienieSkrotu] = [.optionSpace, .controlOptionSpace, .controlOptionCommandSpace,
                    UstawienieSkrotu(kind: .keyCombo, solo: nil, keyCode: 36, modifierFlags: 1_048_576)]
                for kombinacja in kombinacje {
                    for tryb in TrybSkrotu.allCases {
                        var wybor = UstawienieSkrotu.optionSpace
                        try expectEqual(wybor.wybierzTryb(tryb), .przyjeta)
                        try expectEqual(wybor.wybierzKlawisz(kombinacja, accessibility: false), .przyjeta)
                        try expectEqual(wybor.tryb, tryb)
                        try expectEqual(wybor.tenSamKlawisz(co: kombinacja), true)
                        wybor.zapisz(w: magazyn)
                        try expectEqual(UstawienieSkrotu.wczytaj(z: magazyn), wybor)
                    }
                }
            }),
            ("FN10: Fn i przelacznik odrzucone bez zmiany obu osi", {
                var wybor = UstawienieSkrotu.optionSpace
                try expectEqual(wybor.wybierzKlawisz(.fnHotkey, accessibility: true), .modyfikatorWymagaPrzytrzymania)
                try expectEqual(wybor, .optionSpace)
                try expectEqual(wybor.wybierzTryb(.przytrzymanie), .przyjeta)
                try expectEqual(wybor.wybierzKlawisz(.fnHotkey, accessibility: true), .przyjeta)
                try expectEqual(wybor.wybierzTryb(.przelacznik), .modyfikatorWymagaPrzytrzymania)
                try expectEqual(wybor, .fnHotkey)
                let magazyn = MagazynUstawien(zrodlo: PamiecMagazynKluczy())
                wybor.zapisz(w: magazyn)
                try expectEqual(UstawienieSkrotu.wczytaj(z: magazyn), .fnHotkey)
            }),
            ("FN10: odmowa Dostepnosci zachowuje kombinacje i tryb", {
                var wybor = UstawienieSkrotu.optionSpace
                _ = wybor.wybierzTryb(.przytrzymanie)
                let przed = wybor
                try expectEqual(wybor.wybierzKlawisz(.fnHotkey, accessibility: false), .brakUprawnieniaModyfikatora)
                try expectEqual(wybor, przed)
            }),
            ("przechwyt: klawisz glowny albo timeout usuwa oczekujace solo", {
                var chwyt = PrzechwytModyfikatora<String>()
                _ = chwyt.zmiana("option")
                chwyt.anuluj()
                try expectEqual(chwyt.zmiana(nil), nil)
            }),
            ("FN10: pusty magazyn daje Option Space przelacznik", {
                let magazyn = MagazynUstawien(zrodlo: PamiecMagazynKluczy())
                let skrot = UstawienieSkrotu.wczytaj(z: magazyn)
                try expectEqual(skrot.keyCode, 49)
                try expectEqual(skrot.modifierFlags, 524_288)
                try expectEqual(skrot.tryb, .przelacznik)
            }),
            ("przechwyt: przytrzymanie Option czeka na klawisz albo puszczenie", {
                var chwyt = PrzechwytModyfikatora<String>()
                try expectEqual(chwyt.zmiana("option"), nil)
                // Kolejne zdarzenia i dowolnie długie trzymanie nie zatwierdzają solo.
                try expectEqual(chwyt.zmiana("option"), nil)
                try expectEqual(chwyt.zmiana(nil), "option")
                try expectEqual(chwyt.zmiana(nil), nil)
            }),
            ("skrot: Fn z Dostepnoscia jest przyjmowany", {
                try expectEqual(
                    OcenaSkrotu.ocen(tylkoModyfikator: true, soloPraweOption: false, accessibility: true),
                    .przyjeta
                )
            }),
            ("skrot: Option+Space bez Dostepnosci jest przyjmowany", {
                try expectEqual(
                    OcenaSkrotu.ocen(tylkoModyfikator: false, soloPraweOption: false, accessibility: false),
                    .przyjeta
                )
            }),
            ("skrot: samotny prawy Option jest odrzucany", {
                try expectEqual(
                    OcenaSkrotu.ocen(tylkoModyfikator: true, soloPraweOption: true, accessibility: true),
                    .odrzucPraweOption
                )
            }),
            ("skrot: modyfikator bez Dostepnosci konczy sie odmowa", {
                try expectEqual(
                    OcenaSkrotu.ocen(tylkoModyfikator: true, soloPraweOption: false, accessibility: false),
                    .brakUprawnieniaModyfikatora
                )
            }),
        ]
    }
}
