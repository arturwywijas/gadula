// autor: Codex, gadula-stabilnosc-20260927
import AVFoundation

/// Callback oddaje pamięć silnikowi. Do kolejki aktora przekazujemy własne próbki.
nonisolated func skopiujBuforAudio(_ zrodlo: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    guard zrodlo.frameLength > 0,
          let kopia = AVAudioPCMBuffer(pcmFormat: zrodlo.format, frameCapacity: zrodlo.frameLength) else { return nil }
    kopia.frameLength = zrodlo.frameLength
    let wejscie = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: zrodlo.audioBufferList))
    let wyjscie = UnsafeMutableAudioBufferListPointer(kopia.mutableAudioBufferList)
    guard wejscie.count == wyjscie.count else { return nil }
    for (a, b) in zip(wejscie, wyjscie) {
        guard let dane = a.mData, let cel = b.mData, a.mDataByteSize >= b.mDataByteSize else { return nil }
        memcpy(cel, dane, Int(b.mDataByteSize))
    }
    return kopia
}
