import Foundation

public enum TrybSkrotu: String, Codable, CaseIterable, Sendable {
    case przelacznik
    case przytrzymanie

    public var etykieta: String {
        self == .przelacznik ? "Przełącznik" : "Przytrzymanie"
    }
}

/// Dane skrótu i reguły wyboru; kody i maski interpretuje adapter platformy.
public struct UstawienieSkrotu: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case modifierOnly, keyCombo
    }
    public enum SoloModifier: String, Codable, Sendable, CaseIterable {
        case fn, rightOption, leftOption, rightControl, leftControl, rightCommand, rightShift
    }
    public private(set) var kind: Kind
    public private(set) var solo: SoloModifier?
    public private(set) var keyCode: UInt16?
    public private(set) var modifierFlags: UInt
    public private(set) var tryb: TrybSkrotu

    public init(kind: Kind, solo: SoloModifier?, keyCode: UInt16?, modifierFlags: UInt,
                tryb: TrybSkrotu? = nil) {
        self.kind = kind
        self.solo = solo
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.tryb = kind == .modifierOnly ? .przytrzymanie : (tryb ?? .przelacznik)
    }

    public static let kluczMagazynu = "skrot"
    public static let fnHotkey = Self(kind: .modifierOnly, solo: .fn, keyCode: nil, modifierFlags: 0)
    public static let optionSpace = Self(kind: .keyCombo, solo: nil, keyCode: 49, modifierFlags: 524_288)
    public static let controlOptionSpace = Self(kind: .keyCombo, solo: nil, keyCode: 49, modifierFlags: 786_432)
    public static let controlOptionCommandSpace = Self(kind: .keyCombo, solo: nil, keyCode: 49, modifierFlags: 1_835_008)
    public static let defaultHotkey = optionSpace
    public var isPushToTalk: Bool { tryb == .przytrzymanie }

    public func tenSamKlawisz(co inny: Self) -> Bool {
        kind == inny.kind && solo == inny.solo && keyCode == inny.keyCode && modifierFlags == inny.modifierFlags
    }

    /// Zmiana jednej osi nie zmienia drugiej. Niedozwolony wybór pozostawia stan.
    public mutating func wybierzKlawisz(_ nowy: Self, accessibility: Bool) -> WerdyktSkrotu {
        if nowy.kind == .modifierOnly && tryb == .przelacznik {
            return .modyfikatorWymagaPrzytrzymania
        }
        let werdykt = OcenaSkrotu.ocen(tylkoModyfikator: nowy.kind == .modifierOnly,
                                     soloPraweOption: nowy.solo == .rightOption,
                                     accessibility: accessibility)
        guard werdykt == .przyjeta else { return werdykt }
        kind = nowy.kind
        solo = nowy.solo
        keyCode = nowy.keyCode
        modifierFlags = nowy.modifierFlags
        return .przyjeta
    }

    public mutating func wybierzTryb(_ nowy: TrybSkrotu) -> WerdyktSkrotu {
        guard kind != .modifierOnly || nowy == .przytrzymanie else {
            return .modyfikatorWymagaPrzytrzymania
        }
        tryb = nowy
        return .przyjeta
    }

    private enum CodingKeys: String, CodingKey { case kind, solo, keyCode, modifierFlags, tryb }

    /// Starszy zapis nie zawierał trybu: kombinacja była przełącznikiem, solo przytrzymaniem.
    public init(from decoder: Decoder) throws {
        let dane = try decoder.container(keyedBy: CodingKeys.self)
        self.init(kind: try dane.decode(Kind.self, forKey: .kind),
                  solo: try dane.decodeIfPresent(SoloModifier.self, forKey: .solo),
                  keyCode: try dane.decodeIfPresent(UInt16.self, forKey: .keyCode),
                  modifierFlags: try dane.decode(UInt.self, forKey: .modifierFlags),
                  tryb: try dane.decodeIfPresent(TrybSkrotu.self, forKey: .tryb))
    }

    public static func wczytaj(z magazyn: MagazynUstawien) -> Self {
        let raw = magazyn.string(klucz: kluczMagazynu, domyslna: "")
        guard let data = raw.data(using: .utf8),
              let zapis = try? JSONDecoder().decode(Self.self, from: data) else { return .defaultHotkey }
        return zapis
    }

    public func zapisz(w magazyn: MagazynUstawien) {
        guard let data = try? JSONEncoder().encode(self),
              let raw = String(data: data, encoding: .utf8) else { return }
        magazyn.ustaw(raw, klucz: Self.kluczMagazynu)
    }
}
