import VoiceAgentCore

enum TestyKonfiguracjiAudio {
    static func przypadki() -> [(String, @MainActor () async throws -> Void)] {
        [
            ("FN18: opoznione zdarzenie z okresu ochronnego pozostaje ignorowane", {
                var ochrona = OchronaRekonfiguracjiAudio()
                ochrona.rozpocznijPrzebudowe()
                ochrona.zakonczPrzebudowe(czas: 10)
                try expectEqual(ochrona.ocen(czasZdarzenia: 12, nagrywa: true, istnieje: true, wymaga: false), .bezZmiany)
                try expectEqual(ochrona.ocen(czasZdarzenia: 10.6, nagrywa: true, istnieje: true, wymaga: true), .ignorujWlasna)
                try expectEqual(ochrona.liczbaProb, 0)
            }),
            ("FN18: rzeczywista zmiana po stabilizacji moze przeladowac silnik", {
                var ochrona = OchronaRekonfiguracjiAudio()
                ochrona.rozpocznijPrzebudowe()
                ochrona.zakonczPrzebudowe(czas: 10)
                try expectEqual(ochrona.ocen(czasZdarzenia: 11, nagrywa: true, istnieje: true, wymaga: true), .przeladuj)
                try expectEqual(ochrona.liczbaProb, 1)
            }),
            ("FN18: ochrona wlasnych zdarzen nie ukrywa odlaczenia", {
                var ochrona = OchronaRekonfiguracjiAudio()
                ochrona.rozpocznijPrzebudowe()
                try expectEqual(ochrona.ocen(czasZdarzenia: 10, nagrywa: true, istnieje: false, wymaga: true), .odlaczone)
            }),
            ("FN18: brak zmiany i brak sesji nie zuzywaja budzetu", {
                var ochrona = OchronaRekonfiguracjiAudio()
                for czas in 1...10 {
                    try expectEqual(ochrona.ocen(czasZdarzenia: Double(czas), nagrywa: true, istnieje: true, wymaga: false), .bezZmiany)
                    try expectEqual(ochrona.ocen(czasZdarzenia: Double(czas), nagrywa: false, istnieje: true, wymaga: true), .bezZmiany)
                }
                try expectEqual(ochrona.liczbaProb, 0)
            }),
            ("FN18: nowa sesja dostaje nowy budzet", {
                var ochrona = OchronaRekonfiguracjiAudio()
                for czas in 1...2 { _ = ochrona.ocen(czasZdarzenia: Double(czas), nagrywa: true, istnieje: true, wymaga: true) }
                try expectEqual(ochrona.ocen(czasZdarzenia: 3, nagrywa: true, istnieje: true, wymaga: true), .limitProb)
                ochrona = OchronaRekonfiguracjiAudio()
                try expectEqual(ochrona.ocen(czasZdarzenia: 4, nagrywa: true, istnieje: true, wymaga: true), .przeladuj)
            }),
            ("FN18: wlasna przebudowa i jej powiadomienie nie wywoluja nastepnej", {
                var ochrona = OchronaRekonfiguracjiAudio()
                ochrona.rozpocznijPrzebudowe()
                try expectEqual(ochrona.ocen(czasZdarzenia: 10, nagrywa: true, istnieje: true, wymaga: true), .ignorujWlasna)
                ochrona.zakonczPrzebudowe(czas: 10)
                try expectEqual(ochrona.ocen(czasZdarzenia: 10.6, nagrywa: true, istnieje: true, wymaga: true), .ignorujWlasna)
            }),
            ("FN18: trzecia rekonfiguracja konczy sesje zamiast petli", {
                var ochrona = OchronaRekonfiguracjiAudio()
                try expectEqual(ochrona.ocen(czasZdarzenia: 1, nagrywa: true, istnieje: true, wymaga: true), .przeladuj)
                try expectEqual(ochrona.ocen(czasZdarzenia: 3, nagrywa: true, istnieje: true, wymaga: true), .przeladuj)
                try expectEqual(ochrona.ocen(czasZdarzenia: 5, nagrywa: true, istnieje: true, wymaga: true), .limitProb)
            }),
            ("audio HAL: listener starego wejscia czeka a nowego potwierdza", {
                try expectEqual(PotwierdzenieZmianyAudio.ocen(zadane: 8, biezace: 7, zdarzenie: .listener), .czekaj)
                try expectEqual(PotwierdzenieZmianyAudio.ocen(zadane: 8, biezace: 8, zdarzenie: .listener), .kontynuuj(urzadzenie: 8, powod: .hal))
            }),
            ("audio HAL: timeout kontynuuje na faktycznym innym wejsciu", {
                try expectEqual(PotwierdzenieZmianyAudio.ocen(zadane: 8, biezace: 7, zdarzenie: .limit), .kontynuuj(urzadzenie: 7, powod: .timeout))
            }),
            ("audio HAL: timeout bez listenera nie udaje potwierdzenia", {
                try expectEqual(PotwierdzenieZmianyAudio.ocen(zadane: 8, biezace: 8, zdarzenie: .limit), .kontynuuj(urzadzenie: 8, powod: .timeout))
            }),
            ("audio HAL: odrzucone zadanie kontynuuje na aktualnym wejsciu", {
                try expectEqual(PotwierdzenieZmianyAudio.ocen(zadane: 8, biezace: 7, zdarzenie: .odrzucono), .kontynuuj(urzadzenie: 7, powod: .requestRejected))
            }),
            ("audio HAL: blad instalacji listenera nie blokuje startu", {
                try expectEqual(PotwierdzenieZmianyAudio.ocen(zadane: 8, biezace: 7, zdarzenie: .brakListenera), .kontynuuj(urzadzenie: 7, powod: .listenerUnavailable))
            }),
            ("audio HAL: timeout bez wejscia nie wymysla urzadzenia", {
                try expectEqual(PotwierdzenieZmianyAudio.ocen(zadane: 8, biezace: nil, zdarzenie: .limit), .kontynuuj(urzadzenie: nil, powod: .timeout))
            }),
            ("audio HAL: przyjecie zadania nie potwierdza zmiany", {
                try expectEqual(PotwierdzenieZmianyAudio.ocen(zadane: 8, biezace: 7, zdarzenie: .przyjeto), .czekaj)
            }),
            ("audio: wybrane urzadzenie juz domyslne nie wymaga ustawienia", {
                try expectEqual(OcenaKonfiguracjiAudio.wybor(zapisanyUID: true, wybrane: 7, domyslne: 7), .bezZmiany)
            }),
            ("audio: inne wybrane urzadzenie wymaga ustawienia", {
                try expectEqual(OcenaKonfiguracjiAudio.wybor(zapisanyUID: true, wybrane: 8, domyslne: 7), .ustawWybrane)
            }),
            ("audio: nieobecny zapisany UID wraca do systemowego", {
                try expectEqual(OcenaKonfiguracjiAudio.wybor(zapisanyUID: true, wybrane: nil, domyslne: 7), .powrotDoSystemowego)
            }),
            ("audio: pusty wybor pozostawia systemowe wejscie", {
                try expectEqual(OcenaKonfiguracjiAudio.wybor(zapisanyUID: false, wybrane: nil, domyslne: 7), .bezZmiany)
            }),
            ("audio: rozjazd 44100 i 16000 oraz zero kanalow blokuje tap", {
                try expectEqual(OcenaKonfiguracjiAudio.zgodnyFormat(tapHz: 44_100, tapKanaly: 1, sprzetHz: 16_000, sprzetKanaly: 1), false)
                try expectEqual(OcenaKonfiguracjiAudio.zgodnyFormat(tapHz: 16_000, tapKanaly: 1, sprzetHz: 16_000, sprzetKanaly: 1), true)
                try expectEqual(OcenaKonfiguracjiAudio.zgodnyFormat(tapHz: 0, tapKanaly: 0, sprzetHz: 0, sprzetKanaly: 0), false)
            }),
        ]
    }
}
