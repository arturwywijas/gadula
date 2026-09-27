// autor: Codex, gadula-dzwiek-aktualizacje-20260927
import CoreAudio
import Foundation
import VoiceAgentCore

@MainActor
final class GlosnoscSystemowa: SterowanieGlosnoscia {
    private struct Wyjscie: Codable { let uid: String; let kanaly: [UInt32] }
    var domyslneWyjscie: String? {
        var address = adres(kAudioHardwarePropertyDefaultOutputDevice, zakres: kAudioObjectPropertyScopeGlobal)
        var id: AudioDeviceID = 0; var size: UInt32 = 4
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              let uid = AudioDeviceManager.uid(for: id) else { return nil }
        let kanaly: [UInt32]
        if zapisywalny(id, kanal: 0) { kanaly = [0] }
        else { kanaly = (1...32).compactMap { zapisywalny(id, kanal: UInt32($0)) ? UInt32($0) : nil } }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard !kanaly.isEmpty, let data = try? encoder.encode(Wyjscie(uid: uid, kanaly: kanaly)) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    func odczytaj(_ id: String) -> [Float]? {
        guard let (device, kanaly) = znajdz(id) else { return nil }
        var wynik: [Float] = []
        for kanal in kanaly {
            var address = adres(kAudioDevicePropertyVolumeScalar, kanal: kanal)
            var value: Float = 0; var size: UInt32 = 4
            guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr,
                  value.isFinite, (0...1).contains(value) else { return nil }
            wynik.append(value)
        }
        return wynik
    }
    // HAL zaokrągla do najbliższego wspieranego poziomu. Konwersje kontrolki
    // dają wartość oczekiwaną w readback, bez ignorowania ręcznych zmian o 1 pp.
    func dopasuj(_ id: String, poziomy: [Float]) -> [Float]? {
        guard let (device, kanaly) = znajdz(id), kanaly.count == poziomy.count else { return nil }
        var wynik: [Float] = []
        for (kanal, poziom) in zip(kanaly, poziomy) {
            var value = poziom
            for selector in [kAudioDevicePropertyVolumeScalarToDecibels, kAudioDevicePropertyVolumeDecibelsToScalar] {
                var address = adres(selector, kanal: kanal); var size: UInt32 = 4
                guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
            }
            guard value.isFinite, (0...1).contains(value) else { return nil }
            wynik.append(value)
        }
        return wynik
    }
    func ustaw(_ id: String, poziomy: [Float]) -> Bool {
        guard let (device, kanaly) = znajdz(id), poziomy.count == kanaly.count,
              poziomy.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return false }
        var sukces = true
        for (kanal, poziom) in zip(kanaly, poziomy) {
            var address = adres(kAudioDevicePropertyVolumeScalar, kanal: kanal)
            var value = poziom
            if AudioObjectSetPropertyData(device, &address, 0, nil, 4, &value) != noErr { sukces = false }
        }
        return sukces
    }
    private func znajdz(_ zapis: String) -> (AudioDeviceID, [UInt32])? {
        guard let data = zapis.data(using: .utf8), let opis = try? JSONDecoder().decode(Wyjscie.self, from: data) else { return nil }
        var address = adres(kAudioHardwarePropertyDevices, zakres: kAudioObjectPropertyScopeGlobal)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return nil }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / 4)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr,
              let id = ids.first(where: { AudioDeviceManager.uid(for: $0) == opis.uid }),
              opis.kanaly.allSatisfy({ zapisywalny(id, kanal: $0) }) else { return nil }
        return (id, opis.kanaly)
    }
    private func zapisywalny(_ id: AudioDeviceID, kanal: UInt32) -> Bool {
        var address = adres(kAudioDevicePropertyVolumeScalar, kanal: kanal)
        var writable: DarwinBoolean = false
        return AudioObjectHasProperty(id, &address) && AudioObjectIsPropertySettable(id, &address, &writable) == noErr && writable.boolValue
    }
    private func adres(_ selector: AudioObjectPropertySelector, zakres: AudioObjectPropertyScope = kAudioObjectPropertyScopeOutput, kanal: UInt32 = 0) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: zakres, mElement: kanal)
    }
}
