/// Samo trzymanie nie zatwierdza skrótu. Kandydat wraca dopiero po puszczeniu.
public struct PrzechwytModyfikatora<Modyfikator> {
    private var oczekujacy: Modyfikator?

    public init() {}

    public mutating func zmiana(_ wcisniety: Modyfikator?) -> Modyfikator? {
        if let wcisniety {
            oczekujacy = wcisniety
            return nil
        }
        let wynik = oczekujacy
        oczekujacy = nil
        return wynik
    }

    /// Klawisz główny, anulowanie albo timeout kończą oczekiwanie bez wyboru solo.
    public mutating func anuluj() {
        oczekujacy = nil
    }
}
