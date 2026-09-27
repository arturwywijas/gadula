import Foundation
import VoiceAgentCore

@MainActor
final class LokalnaTranskrypcja: Transcribing {
    private let magazyn: MagazynUstawien
    private let kit = WhisperKitTranscriber()
    private let przygotowanie = WspoldzielonePrzygotowanieModelu()

    init(magazyn: MagazynUstawien) {
        self.magazyn = magazyn
    }

    func modelGotowy() async -> Bool {
        let wariant = wybranyWariant
        guard WagiModeluNaDysku.saKompletne(dla: wariant) else { return false }
        // Uszkodzone wagi wykrywamy przed przejęciem mikrofonu, nie po wypowiedzi.
        let gotowy = await przygotowanie.poczekajNaModel(
            modelID: wariant.whisperKitID, wagiNaDysku: true,
            wykonaj: { [weak self] modelID in
                guard let self else { return false }
                return await self.wczytaj(modelID: modelID)
            })
        return gotowy && wybranyWariant == wariant
    }

    var stanPrzygotowaniaModelu: StanPrzygotowaniaModelu { przygotowanie.stan }
    var poZmianiePrzygotowaniaModelu: (() -> Void)? {
        get { przygotowanie.poZmianie }
        set { przygotowanie.poZmianie = newValue }
    }

    func uruchomPrzygotowanieModeluWBiezacymModelu() {
        let wariant = wybranyWariant
        przygotowanie.uruchomWBtle(
            modelID: wariant.whisperKitID,
            wagiNaDysku: WagiModeluNaDysku.saKompletne(dla: wariant),
            wykonaj: { [weak self] modelID in
                guard let self else { return false }
                return await self.wczytaj(modelID: modelID)
            }
        )
    }

    func transcribe(nagranie: Nagranie, jezyk _: String) async throws -> Transkrypt {
        var wariant = wybranyWariant
        while true {
            guard WagiModeluNaDysku.saKompletne(dla: wariant) else {
                throw BladTranskrypcji.modelNiegotowy
            }
            let gotowy = await przygotowanie.poczekajNaModel(
                modelID: wariant.whisperKitID,
                wagiNaDysku: true,
                wykonaj: { [weak self] modelID in
                    guard let self else { return false }
                    return await self.wczytaj(modelID: modelID)
                }
            )

            let aktualnieWybrany = wybranyWariant
            guard aktualnieWybrany.whisperKitID == wariant.whisperKitID else {
                // Sesja transkrybuje model wybrany po zakończeniu oczekiwania, nie cofa ustawienia.
                wariant = aktualnieWybrany
                continue
            }
            guard gotowy else {
                throw BladTranskrypcji.modelNiegotowy
            }
            break
        }
        do {
            // Jezyk przypiety na pl, bez auto-detekcji (spec D5).
            let tekst = try await kit.transcribe(
                samples: nagranie.pcm,
                language: "pl",
                fallbackCount: ParametryRozpoznawania.liczbaPonowien
            )
            return Transkrypt(tekst: tekst ?? "")
        } catch TranscriberError.modelNotLoaded {
            throw BladTranskrypcji.modelNiegotowy
        } catch {
            throw BladTranskrypcji.nieudana
        }
    }

    private var wybranyWariant: WariantModelu {
        let wybrany = magazyn.string(klucz: KluczModelu.id, domyslna: KluczModelu.domyslny)
        return WariantModelu(rawValue: wybrany) ?? .largeTurbo
    }

    private func wczytaj(modelID: String) async -> Bool {
        do {
            try await kit.prepare(modelID: modelID) { _ in }
            return true
        } catch {
            return false
        }
    }
}
