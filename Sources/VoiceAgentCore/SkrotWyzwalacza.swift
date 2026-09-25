public enum WerdyktSkrotu: Equatable, Sendable {
    case modyfikatorWymagaPrzytrzymania
    case przyjeta
    case odrzucPraweOption
    case brakUprawnieniaModyfikatora
}

public enum OcenaSkrotu {
    public static let wyjasnieniePraweOption =
        "Prawy Option z literą wpisuje polskie ogonki (ą, ę, ś). Samotny prawy Option jako przytrzymanie wywoływałby dyktowanie przy każdym takim znaku."

    public static func ocen(
        tylkoModyfikator: Bool,
        soloPraweOption: Bool,
        accessibility: Bool
    ) -> WerdyktSkrotu {
        if soloPraweOption {
            return .odrzucPraweOption
        }
        if tylkoModyfikator && !accessibility {
            return .brakUprawnieniaModyfikatora
        }
        return .przyjeta
    }
}
