// autor: Codex, gadula-stabilnosc-20260927
import Foundation

/// Kontrola struktury przed nagraniem. Faktyczne wczytanie sprawdza zawartość wag.
enum WagiModeluNaDysku {
    static func saKompletne(folder: URL) -> Bool {
        ["MelSpectrogram", "AudioEncoder", "TextDecoder"].allSatisfy { nazwa in
            var katalog: ObjCBool = false
            return FileManager.default.fileExists(
                atPath: folder.appendingPathComponent(nazwa + ".mlmodelc").path,
                isDirectory: &katalog) && katalog.boolValue
        }
    }
}
