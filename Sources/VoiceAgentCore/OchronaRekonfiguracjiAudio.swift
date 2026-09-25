/// Stan jednej sesji. Czas zdarzenia pochodzi z chwili odbioru, nie z opróżnienia kolejki.
public struct OchronaRekonfiguracjiAudio {
    public enum Decyzja: Equatable { case bezZmiany, ignorujWlasna, przeladuj, odlaczone, limitProb }
    public static let czasStabilizacji: Double = 1
    public static let maksymalnaLiczbaProb = 2
    public private(set) var liczbaProb = 0
    private var przebudowuje = false
    private var stabilizacjaDo: Double = -.infinity

    public init() {}
    public mutating func rozpocznijPrzebudowe() { przebudowuje = true }
    public mutating func zakonczPrzebudowe(czas: Double) {
        przebudowuje = false
        stabilizacjaDo = czas + Self.czasStabilizacji
    }

    public mutating func ocen(czasZdarzenia: Double, nagrywa: Bool, istnieje: Bool,
                               wymaga: @autoclosure () -> Bool) -> Decyzja {
        guard nagrywa else { return .bezZmiany }
        // Prawdziwe odłączenie ma pierwszeństwo przed tłumieniem własnych zdarzeń.
        guard istnieje else { return .odlaczone }
        guard !przebudowuje, czasZdarzenia >= stabilizacjaDo else { return .ignorujWlasna }
        guard wymaga() else { return .bezZmiany }
        guard liczbaProb < Self.maksymalnaLiczbaProb else { return .limitProb }
        liczbaProb += 1
        return .przeladuj
    }
}
