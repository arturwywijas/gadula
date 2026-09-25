import CoreAudio
import Foundation
import VoiceAgentCore

/// Jedno żądanie, listener założony przed setterem i jedno ograniczone oczekiwanie.
@MainActor
final class PotwierdzenieWejsciaAudio {
    private let zadane: AudioDeviceID
    private var kontynuacja: CheckedContinuation<PotwierdzenieZmianyAudio.Wynik, Never>?
    private var listener: AudioObjectPropertyListenerBlock?
    private var limit: Task<Void, Never>?
    private static let log = AppLogger(category: "Audio")
    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    private init(zadane: AudioDeviceID) { self.zadane = zadane }

    static func ustaw(_ id: AudioDeviceID) async -> PotwierdzenieZmianyAudio.Wynik {
        let oczekiwanie = PotwierdzenieWejsciaAudio(zadane: id)
        let wynik = await oczekiwanie.wykonaj()
        withExtendedLifetime(oczekiwanie) {}
        return wynik
    }

    private func wykonaj() async -> PotwierdzenieZmianyAudio.Wynik {
        await withCheckedContinuation { kontynuacja in
            self.kontynuacja = kontynuacja
            let blok = Self.blokListenera(self)
            let status = AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, blok)
            guard status == noErr else {
                Self.log.error("FN16 input listener install failed status=\(status)")
                rozstrzygnij(.brakListenera)
                return
            }
            listener = blok
            let przyjeto = AudioDeviceManager.setDefaultInputDevice(zadane)
            Self.log.notice("FN16 input request accepted=\(przyjeto) waitLimitMs=1500")
            guard przyjeto else {
                rozstrzygnij(.odrzucono)
                return
            }
            // Celowo bez Get bezpośrednio po Set: noErr nie jest potwierdzeniem HAL.
            rozstrzygnij(.przyjeto)
            limit = Task { [self] in
                do { try await Task.sleep(nanoseconds: 1_500_000_000) }
                catch { return }
                rozstrzygnij(.limit)
            }
        }
    }

    private nonisolated static func blokListenera(_ odbiorca: PotwierdzenieWejsciaAudio) -> AudioObjectPropertyListenerBlock {
        { [weak odbiorca] _, _ in
            Task { @MainActor [weak odbiorca] in odbiorca?.rozstrzygnij(.listener) }
        }
    }

    private func rozstrzygnij(_ zdarzenie: PotwierdzenieZmianyAudio.Zdarzenie) {
        guard let kontynuacja else { return }
        let biezace = zdarzenie == .przyjeto ? nil : AudioDeviceManager.defaultInputDeviceID()
        let wynik = PotwierdzenieZmianyAudio.ocen(zadane: zadane, biezace: biezace, zdarzenie: zdarzenie)
        guard case .kontynuuj(_, let powod) = wynik else { return }
        self.kontynuacja = nil
        limit?.cancel()
        limit = nil
        if let listener {
            let status = AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener)
            if status != noErr { Self.log.error("FN16 input listener remove failed status=\(status)") }
            self.listener = nil
        }
        Self.log.notice("FN16 input continue reason=\(powod.rawValue) requested=\(self.zadane) actual=\(String(describing: biezace)) targetMatches=\(biezace == self.zadane)")
        kontynuacja.resume(returning: wynik)
    }
}
