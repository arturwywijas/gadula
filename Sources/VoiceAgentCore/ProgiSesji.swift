import Foundation

public enum ProgiSesji {
    public static let minimalnyCzasTrwania: TimeInterval = 0.3
    public static let maksymalnyCzasTrwania: TimeInterval = 120
    public static let minimalnaSzczytowaGlosnosc: Float = 0.005
    public static let czasIkonyBledu: TimeInterval = 3

    /// Zachowujemy progi: zgłoszone 2,30 s i peak 0,2336 przechodzą oba z zapasem.
    public static func dopuszczaNagranie(czas: Double, szczyt: Float) -> Bool {
        czas.isFinite && szczyt.isFinite
            && czas >= minimalnyCzasTrwania && szczyt >= minimalnaSzczytowaGlosnosc
    }

    public static func transkryptJestPusty(_ tekst: String) -> Bool {
        let przyciety = tekst.trimmingCharacters(in: .whitespacesAndNewlines)
        if przyciety.isEmpty { return true }
        return przyciety.unicodeScalars.allSatisfy {
            CharacterSet.punctuationCharacters.contains($0)
                || CharacterSet.symbols.contains($0)
                || CharacterSet.whitespacesAndNewlines.contains($0)
        }
    }
}
