import Foundation
import VoiceAgentCore

@MainActor
private final class AtrapaLadowaniaModelu {
    private struct OczekujacaProba {
        let token: UUID
        let modelID: String
        let kontynuacja: CheckedContinuation<Bool, Never>
        let limit: Task<Void, Never>
    }

    private(set) var wywolane: [String] = []
    private(set) var aktywne = 0
    private(set) var maksimumAktywnych = 0
    private var kontynuacje: [OczekujacaProba] = []

    func laduje(_ modelID: String) async -> Bool {
        wywolane.append(modelID)
        aktywne += 1
        maksimumAktywnych = max(maksimumAktywnych, aktywne)
        let wynik = await withCheckedContinuation { kontynuacja in
            let token = UUID()
            let limit = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 750_000_000)
                guard !Task.isCancelled else { return }
                self?.zakoncz(token: token, sukces: false)
            }
            kontynuacje.append(OczekujacaProba(
                token: token,
                modelID: modelID,
                kontynuacja: kontynuacja,
                limit: limit
            ))
        }
        aktywne -= 1
        return wynik
    }

    func czekajNaStart(_ modelID: String, liczbaWywolan: Int = 1) async {
        for _ in 0..<10_000 {
            if wywolane.filter({ $0 == modelID }).count >= liczbaWywolan { return }
            await Task.yield()
        }
    }

    func zakoncz(_ modelID: String, sukces: Bool = true) {
        let tokeny = kontynuacje.filter { $0.modelID == modelID }.map(\.token)
        for token in tokeny {
            zakoncz(token: token, sukces: sukces)
        }
    }

    private func zakoncz(token: UUID, sukces: Bool) {
        guard let indeks = kontynuacje.firstIndex(where: { $0.token == token }) else { return }
        let proba = kontynuacje.remove(at: indeks)
        proba.limit.cancel()
        proba.kontynuacja.resume(returning: sukces)
    }
}

@MainActor
private final class SekwencyjnaAtrapaLadowania {
    private var wyniki: [Bool]
    private(set) var wywolane: [String] = []

    init(wyniki: [Bool]) {
        self.wyniki = wyniki
    }

    func laduje(_ modelID: String) async -> Bool {
        wywolane.append(modelID)
        await Task.yield()
        return wyniki.isEmpty ? false : wyniki.removeFirst()
    }
}

enum TestyPrzygotowaniaModelu {
    static func przypadki() -> [(String, @MainActor () async throws -> Void)] {
        [
            ("FN21: start z wagami na dysku uruchamia jedno przygotowanie", {
                let loader = AtrapaLadowaniaModelu()
                let przygotowanie = WspoldzielonePrzygotowanieModelu()

                przygotowanie.uruchomWBtle(modelID: "large", wagiNaDysku: true) { id in
                    await loader.laduje(id)
                }
                await loader.czekajNaStart("large")
                try expectEqual(loader.wywolane, ["large"])
                try expectEqual(przygotowanie.stan, .przygotowuje(modelID: "large"))

                loader.zakoncz("large")
                let gotowy = await przygotowanie.poczekajNaModel(modelID: "large", wagiNaDysku: true) { id in
                    await loader.laduje(id)
                }
                try expectEqual(gotowy, true)
                try expectEqual(przygotowanie.stan, .gotowy(modelID: "large"))
                try expectEqual(loader.wywolane, ["large"])
            }),
            ("FN21: sesja podczas przygotowania czeka na to samo zadanie", {
                let loader = AtrapaLadowaniaModelu()
                let przygotowanie = WspoldzielonePrzygotowanieModelu()
                przygotowanie.uruchomWBtle(modelID: "large", wagiNaDysku: true) { id in
                    await loader.laduje(id)
                }
                await loader.czekajNaStart("large")

                var sesjaZakonczona = false
                let sesja = Task { @MainActor in
                    let gotowy = await przygotowanie.poczekajNaModel(modelID: "large", wagiNaDysku: true) { id in
                        await loader.laduje(id)
                    }
                    sesjaZakonczona = true
                    return gotowy
                }
                await Task.yield()
                try expectEqual(loader.wywolane, ["large"])
                try expectEqual(sesjaZakonczona, false)

                loader.zakoncz("large")
                try expectEqual(await sesja.value, true)
                try expectEqual(loader.wywolane, ["large"])
            }),
            ("FN21: równoległe prepare dla tego samego modelu uruchamia jedno ładowanie", {
                let loader = AtrapaLadowaniaModelu()
                let przygotowanie = WspoldzielonePrzygotowanieModelu()
                let pierwszy = Task { @MainActor in
                    await przygotowanie.poczekajNaModel(modelID: "large", wagiNaDysku: true) { id in
                        await loader.laduje(id)
                    }
                }
                await loader.czekajNaStart("large")
                let drugi = Task { @MainActor in
                    await przygotowanie.poczekajNaModel(modelID: "large", wagiNaDysku: true) { id in
                        await loader.laduje(id)
                    }
                }
                await Task.yield()
                try expectEqual(loader.wywolane, ["large"])
                loader.zakoncz("large")
                try expectEqual(await pierwszy.value, true)
                try expectEqual(await drugi.value, true)
                try expectEqual(loader.maksimumAktywnych, 1)
            }),
            ("FN21: zmiana modelu podczas przygotowania pozostawia tylko wybrany model", {
                let loader = AtrapaLadowaniaModelu()
                let przygotowanie = WspoldzielonePrzygotowanieModelu()
                przygotowanie.uruchomWBtle(modelID: "small", wagiNaDysku: true) { id in
                    await loader.laduje(id)
                }
                await loader.czekajNaStart("small")
                przygotowanie.uruchomWBtle(modelID: "large", wagiNaDysku: true) { id in
                    await loader.laduje(id)
                }
                await Task.yield()
                try expectEqual(loader.wywolane, ["small"])
                try expectEqual(loader.maksimumAktywnych, 1)

                loader.zakoncz("small")
                await loader.czekajNaStart("large")
                try expectEqual(loader.maksimumAktywnych, 1)
                loader.zakoncz("large")
                let gotowy = await przygotowanie.poczekajNaModel(modelID: "large", wagiNaDysku: true) { id in
                    await loader.laduje(id)
                }
                try expectEqual(gotowy, true)
                try expectEqual(loader.wywolane, ["small", "large"])
                try expectEqual(idModeluPrzygotowania(przygotowanie.stan), "large")
                try expectEqual(loader.maksimumAktywnych, 1)
            }),
            ("FN21: brak wag na dysku nie uruchamia przygotowania", {
                let loader = AtrapaLadowaniaModelu()
                let przygotowanie = WspoldzielonePrzygotowanieModelu()

                przygotowanie.uruchomWBtle(modelID: "large", wagiNaDysku: false) { id in
                    await loader.laduje(id)
                }
                try expectEqual(loader.wywolane, [])
                try expectEqual(przygotowanie.stan, .niegotowy)

                przygotowanie.uruchomWBtle(modelID: "large", wagiNaDysku: true) { id in
                    await loader.laduje(id)
                }
                await loader.czekajNaStart("large")
                try expectEqual(loader.wywolane, ["large"])
                loader.zakoncz("large")
                let gotowy = await przygotowanie.poczekajNaModel(modelID: "large", wagiNaDysku: true) { id in
                    await loader.laduje(id)
                }
                try expectEqual(gotowy, true)
            }),
            ("FN21B: sesja ponawia nieudane przygotowanie tylko raz, bez ponawiania z menu", {
                let loader = SekwencyjnaAtrapaLadowania(wyniki: [false, true, false])
                let przygotowanie = WspoldzielonePrzygotowanieModelu()
                przygotowanie.uruchomWBtle(modelID: "large", wagiNaDysku: true) { id in
                    await loader.laduje(id)
                }

                for _ in 0..<10_000 {
                    if przygotowanie.stan == .blad(modelID: "large") { break }
                    await Task.yield()
                }
                try expectEqual(przygotowanie.stan, .blad(modelID: "large"))

                // Odpowiednik kolejnych odświeżeń menu nie może sam wywołać następnej próby.
                przygotowanie.uruchomWBtle(modelID: "large", wagiNaDysku: true) { id in
                    await loader.laduje(id)
                }
                for _ in 0..<20 { await Task.yield() }
                try expectEqual(loader.wywolane, ["large"])

                let gotowy = await przygotowanie.poczekajNaModel(modelID: "large", wagiNaDysku: true) { id in
                    await loader.laduje(id)
                }
                try expectEqual(gotowy, true)
                try expectEqual(loader.wywolane, ["large", "large"])
            }),
            ("FN21B: oczekująca sesja podąża za nowym wyborem bez kolejki small large small", {
                let loader = AtrapaLadowaniaModelu()
                let przygotowanie = WspoldzielonePrzygotowanieModelu()
                przygotowanie.uruchomWBtle(modelID: "small", wagiNaDysku: true) { id in
                    await loader.laduje(id)
                }
                await loader.czekajNaStart("small")

                let sesja = Task { @MainActor in
                    await przygotowanie.poczekajNaModel(modelID: "small", wagiNaDysku: true) { id in
                        await loader.laduje(id)
                    }
                }
                await Task.yield()
                przygotowanie.uruchomWBtle(modelID: "large", wagiNaDysku: true) { id in
                    await loader.laduje(id)
                }
                loader.zakoncz("small")
                await loader.czekajNaStart("large")
                loader.zakoncz("large")

                try expectEqual(await sesja.value, false)
                try expectEqual(loader.wywolane, ["small", "large"])
                try expectEqual(loader.maksimumAktywnych, 1)
            }),
            ("FN21B: przytrzymanie podczas aktywnej sesji wymaga sygnału zajętości", {
                try expectEqual(SygnalZajetosciPTT.wymagany(gdy: .bezczynny), false)
                try expectEqual(SygnalZajetosciPTT.wymagany(gdy: .transkrypcja), true)
                try expectEqual(SygnalZajetosciPTT.wymagany(gdy: .nagrywanie), true)
            }),
        ]
    }

    private static func idModeluPrzygotowania(_ stan: StanPrzygotowaniaModelu) -> String? {
        switch stan {
        case .niegotowy:
            return nil
        case .przygotowuje(let modelID), .gotowy(let modelID), .blad(let modelID):
            return modelID
        }
    }
}
