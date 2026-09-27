// autor: Codex, gadula-dyktowanie-20260927
public enum GotowoscDyktowania: Sendable, Equatable {
    case ukryta, model, mikrofon, gotowa, przetwarzanie, blad
    public var komunikat: String {
        switch self {
        case .ukryta: ""
        case .model: "Przygotowuję model"
        case .mikrofon: "Przygotowuję mikrofon"
        case .gotowa: "Możesz mówić"
        case .przetwarzanie: "Przetwarzam tekst"
        case .blad: "Nie udało się. Sprawdź menu."
        }
    }
}
