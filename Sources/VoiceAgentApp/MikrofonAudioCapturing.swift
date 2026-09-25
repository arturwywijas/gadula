import AVFoundation
import Foundation
import VoiceAgentCore

enum KluczMikrofonu {
    static let uid = "mikrofon.uid"
}

final class MikrofonAudioCapturing: AudioCapturing {
    private let recorder: AudioRecorder
    private let wskaznik: any WskaznikNagrywania
    private let magazyn: MagazynUstawien
    private var autoStopNagranie: Nagranie?
    private var generacjaStartu: UInt64 = 0
    private weak var koordynator: KoordynatorDyktowania?

    @MainActor
    init(magazyn: MagazynUstawien, wskaznik: any WskaznikNagrywania) {
        self.wskaznik = wskaznik
        self.magazyn = magazyn
        let recorder = AudioRecorder()
        self.recorder = recorder
        recorder.onPoziom = { [weak wskaznik] szczyt, czas in
            wskaznik?.przyjmij(szczyt: szczyt, czas: czas)
        }
        recorder.onZatrzymanie = { [weak wskaznik] in wskaznik?.zakoncz() }
        recorder.onLimitCzasu = { [weak self] samples in
            guard let self else { return }
            self.autoStopNagranie = Self.nagranie(z: samples)
            let k = self.koordynator
            Task { await k?.zakonczNagrywanie() }
        }
        recorder.onZmianaKonfiguracji = { [weak self] czas in
            self?.obsluzZmianeKonfiguracji(czasZdarzenia: czas)
        }
    }

    func podlacz(koordynator: KoordynatorDyktowania) {
        self.koordynator = koordynator
    }

    func start() async throws {
        autoStopNagranie = nil
        generacjaStartu &+= 1
        let id = generacjaStartu
        await zastosujWybraneUrzadzenie()
        guard generacjaStartu == id else {
            AppLogger(category: "Audio").notice("FN17 audio start ignored reason=sessionInvalidated")
            throw CancellationError()
        }
        do {
            let uid = self.magazyn.string(klucz: KluczMikrofonu.uid, domyslna: "")
            let biezace = AudioDeviceManager.defaultInputDeviceID()
            let nazwa = biezace.flatMap { AudioDeviceManager.name(for: $0) } ?? "-"
            AppLogger(category: "Audio").info(
                "start mic storedUID=\(uid.isEmpty ? "-" : uid) defaultInput=\(biezace.map(String.init) ?? "-") name=\(nazwa)"
            )
            do {
                try self.recorder.start()
                let poziom = AudioDeviceManager.inputVolumeDecibels(for: recorder.uzywaneUrzadzenieID)
                koordynator?.odnotujPoziomWejscia(db: poziom)
                self.wskaznik.rozpocznij()
            } catch {
                self.wskaznik.zakoncz()
                throw error
            }
        }
    }

    func stop() async -> Nagranie {
        generacjaStartu &+= 1
        if let autoStopNagranie {
            self.autoStopNagranie = nil
            return autoStopNagranie
        }
        let samples = recorder.stop()
        return Self.nagranie(z: samples)
    }

    @MainActor
    private func zastosujWybraneUrzadzenie() async {
        let uid = magazyn.string(klucz: KluczMikrofonu.uid, domyslna: "")
        let wybrane = uid.isEmpty ? nil : AudioDeviceManager.deviceID(forUID: uid)
        let domyslne = AudioDeviceManager.defaultInputDeviceID()
        switch OcenaKonfiguracjiAudio.wybor(zapisanyUID: !uid.isEmpty, wybrane: wybrane, domyslne: domyslne) {
        case .bezZmiany:
            AppLogger(category: "Audio").notice("FN15 input selection action=unchanged")
        case .powrotDoSystemowego:
            AppLogger(category: "Audio").notice("FN15 input selection action=fallbackSystemDefault reason=savedDeviceMissing")
        case .ustawWybrane:
            guard let wybrane else { return }
            let wynik = await PotwierdzenieWejsciaAudio.ustaw(wybrane)
            let potwierdzone: Bool
            if case .kontynuuj(_, .hal) = wynik { potwierdzone = true } else { potwierdzone = false }
            AppLogger(category: "Audio").notice("FN15 input selection action=setDefault confirmed=\(potwierdzone)")
        }
    }

    @MainActor
    private func obsluzZmianeKonfiguracji(czasZdarzenia: Double) {
        switch recorder.ocenZmianeKonfiguracji(czasZdarzenia: czasZdarzenia) {
        case .bezZmiany:
            AppLogger(category: "Audio").notice("FN15 configuration action=ignore reason=noActiveChange")
        case .ignorujWlasna:
            AppLogger(category: "Audio").notice("FN18 configuration action=ignore reason=ownRebuildOrSettling")
        case .limitProb:
            AppLogger(category: "Audio").error("FN18 audio stop reason=reconfigurationLimit")
            _ = recorder.stop()
            autoStopNagranie = nil
            let k = koordynator
            Task { await k?.przerwij(komunikat: "Mikrofon nie ustabilizował się po dwóch próbach. Wybierz inne wejście i spróbuj ponownie.") }
        case .przeladuj:
            do {
                try recorder.przeladujPoZmianieKonfiguracji()
            } catch {
                AppLogger(category: "Audio").error("FN15 audio stop reason=reconfigurationFailed")
                _ = recorder.stop()
                autoStopNagranie = nil
                let k = koordynator
                Task { await k?.przerwij(komunikat: "Nie udało się wznowić mikrofonu po zmianie formatu.") }
            }
        case .odlaczone:
            AppLogger(category: "Audio").notice("FN15 audio stop reason=usedDeviceDisconnected")
            _ = recorder.stop()
            autoStopNagranie = nil
            let k = koordynator
            Task { await k?.przerwij(komunikat: "Mikrofon został odłączony.") }
        }
    }

    private static func nagranie(z samples: [Float]) -> Nagranie {
        var peak: Float = 0
        for v in samples {
            let a = v < 0 ? -v : v
            if a > peak { peak = a }
        }
        let czas = Double(samples.count) / AudioRecorder.targetSampleRate
        return Nagranie(pcm: samples, czasTrwania: czas, szczytowaGlosnosc: peak)
    }
}
