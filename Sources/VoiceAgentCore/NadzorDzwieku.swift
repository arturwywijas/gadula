// autor: Codex, gadula-stabilnosc-20260927
/// Brak próbek oznacza awarię wejścia. Próbki ciszy nadal są poprawnymi danymi.
public struct NadzorDzwieku {
    public static let limitBezDanych: Double = 4
    private var ostatnieDane: Double?

    public init() {}
    public mutating func rozpocznij(czas: Double) { ostatnieDane = czas }
    public mutating func zakoncz() { ostatnieDane = nil }
    public mutating func otrzymano(liczbaProbek: Int, czas: Double) {
        guard liczbaProbek > 0, ostatnieDane != nil else { return }
        ostatnieDane = czas
    }
    public func brakDanych(czas: Double) -> Bool {
        guard let ostatnieDane else { return false }
        return czas - ostatnieDane >= Self.limitBezDanych
    }
}
