/// Wynik setter oznacza przyjęcie zlecenia; dopiero listener HAL potwierdza zmianę.
public enum PotwierdzenieZmianyAudio {
    public enum Zdarzenie: Equatable, Sendable { case przyjeto, odrzucono, listener, limit, brakListenera }
    public enum Powod: String, Sendable { case hal, timeout, requestRejected, listenerUnavailable }
    public enum Wynik: Equatable, Sendable {
        case czekaj
        case kontynuuj(urzadzenie: UInt32?, powod: Powod)
    }

    public static func ocen(zadane: UInt32, biezace: UInt32?, zdarzenie: Zdarzenie) -> Wynik {
        switch zdarzenie {
        case .przyjeto: return .czekaj
        case .listener:
            return biezace == zadane ? .kontynuuj(urzadzenie: biezace, powod: .hal) : .czekaj
        case .limit: return .kontynuuj(urzadzenie: biezace, powod: .timeout)
        case .odrzucono: return .kontynuuj(urzadzenie: biezace, powod: .requestRejected)
        case .brakListenera: return .kontynuuj(urzadzenie: biezace, powod: .listenerUnavailable)
        }
    }
}
