import Foundation
import VoiceAgentCore

@MainActor
final class LokalnaTranskrypcja: Transcribing {
    private let magazyn: MagazynUstawien
    private let kit = WhisperKitTranscriber()
    private let przygotowanie = WspoldzielonePrzygotowanieModelu()
    private var sesja: UInt64 = 0
    private var ustawieniaSesji: (slownik: [String], tryb: TrybTekstu)?
    private var przyrostowa: TranskrypcjaPrzyrostowa!

    func rozpocznijSesje() {
        sesja &+= 1
        ustawieniaSesji = (SlownikDyktowania.wczytaj(z: magazyn).nazwy, TrybTekstu.wczytaj(z: magazyn))
        przyrostowa.rozpocznij()
    }
    func przyjmijProbki(_ pcm: [Float]) { przyrostowa.przyjmij(pcm) }
    func anulujSesje() {
        sesja &+= 1
        przyrostowa.anuluj()
        ustawieniaSesji = nil
    }

    init(magazyn: MagazynUstawien) {
        self.magazyn = magazyn
        self.przyrostowa = TranskrypcjaPrzyrostowa { [weak self] pcm in
            guard let self else { throw CancellationError() }
            // Cisza z pauzy nie może wymuszać wypisywania podpowiedzi słownika.
            guard pcm.contains(where: { $0 != 0 }) else { return "" }
            return try await self.kit.transcribe(samples: pcm, language: "pl",
                fallbackCount: ParametryRozpoznawania.liczbaPonowien,
                slownik: self.ustawieniaSesji?.slownik ?? []) ?? ""
        }
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
        guard ustawieniaSesji == nil else { return }
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
        if ustawieniaSesji == nil {
            guard await modelGotowy() else { throw BladTranskrypcji.modelNiegotowy }
            rozpocznijSesje()
        }
        let id = sesja
        let tryb = ustawieniaSesji?.tryb ?? .wierny
        defer { if sesja == id { ustawieniaSesji = nil } }
        do {
            let surowy = try await przyrostowa.zakoncz(caleNagranie: nagranie.pcm)
            guard sesja == id else { throw CancellationError() }
            return Transkrypt(tekst: formatujTekst(surowy, tryb: tryb), surowyTekst: surowy)
        } catch is CancellationError {
            throw CancellationError()
        } catch TranscriberError.contextLimit {
            throw BladTranskrypcji.zaDlugaWypowiedz
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
