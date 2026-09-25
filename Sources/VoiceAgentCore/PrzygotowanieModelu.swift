import Foundation

public enum StanPrzygotowaniaModelu: Equatable, Sendable {
    case niegotowy
    case przygotowuje(modelID: String)
    case gotowy(modelID: String)
    case blad(modelID: String)
}

/// Serializuje przygotowanie modeli i pozwala wszystkim wywolujacym czekac na ten sam przebieg.
@MainActor
public final class WspoldzielonePrzygotowanieModelu {
    public typealias Ladowanie = @MainActor (String) async -> Bool

    public private(set) var stan: StanPrzygotowaniaModelu = .niegotowy
    public var poZmianie: (() -> Void)?

    private var zaladowanyModelID: String?
    private var zadanyModelID: String?
    private var ladowanie: Ladowanie?
    private var zadanie: Task<Void, Never>?

    public init() {}

    /// Rozpoczyna lub aktualizuje przygotowanie. Kolejny model czeka na koniec biezacego ladowania.
    public func uruchomWBtle(
        modelID: String,
        wagiNaDysku: Bool,
        wykonaj: @escaping Ladowanie
    ) {
        guard wagiNaDysku else { return }
        if zadanie == nil, stan == .blad(modelID: modelID) { return }
        zaplanuj(modelID: modelID, wykonaj: wykonaj)
    }

    private func zaplanuj(modelID: String, wykonaj: @escaping Ladowanie) {
        if zaladowanyModelID == modelID, zadanie == nil {
            zadanyModelID = nil
            ladowanie = nil
            ustawStan(.gotowy(modelID: modelID))
            return
        }

        zadanyModelID = modelID
        ladowanie = wykonaj
        if stan != .przygotowuje(modelID: modelID) {
            ustawStan(.przygotowuje(modelID: modelID))
        }
        uruchomKolejkeJesliTrzeba()
    }

    /// Czeka na przygotowanie wskazanego modelu, dolaczajac do biezacego zadania, jesli pasuje.
    public func poczekajNaModel(
        modelID: String,
        wagiNaDysku: Bool,
        wykonaj: @escaping Ladowanie
    ) async -> Bool {
        guard wagiNaDysku else { return false }
        var ponowionoPoBledzie = false
        if zadanie == nil, stan == .blad(modelID: modelID) {
            // Odświeżenie menu nie ponawia błędu, ale sesja może spróbować raz jeszcze.
            ponowionoPoBledzie = true
        }
        zaplanuj(modelID: modelID, wykonaj: wykonaj)

        while true {
            if let zadanyModelID, zadanyModelID != modelID {
                // Wybór w menu zmienił się. Sesja ma odczytać nowy wybór, a nie cofać kolejkę.
                return false
            }
            if zaladowanyModelID == modelID, zadanyModelID == nil, zadanie == nil {
                return true
            }

            guard let aktualneZadanie = zadanie else {
                guard stan == .blad(modelID: modelID), !ponowionoPoBledzie else {
                    return zaladowanyModelID == modelID
                }
                ponowionoPoBledzie = true
                zaplanuj(modelID: modelID, wykonaj: wykonaj)
                continue
            }

            await aktualneZadanie.value
            if zaladowanyModelID == modelID, zadanyModelID == nil, zadanie == nil {
                return true
            }
            if let zadanyModelID, zadanyModelID != modelID {
                return false
            }
        }
    }

    private func uruchomKolejkeJesliTrzeba() {
        guard zadanie == nil else { return }
        zadanie = Task(priority: .utility) { @MainActor [weak self] in
            await self?.wykonajKolejke()
        }
    }

    private func wykonajKolejke() async {
        while let modelID = zadanyModelID, let ladowanie {
            if zaladowanyModelID == modelID {
                zadanyModelID = nil
                self.ladowanie = nil
                ustawStan(.gotowy(modelID: modelID))
                continue
            }

            let sukces = await ladowanie(modelID)
            if sukces {
                zaladowanyModelID = modelID
            }
            guard zadanyModelID == modelID else { continue }
            zadanyModelID = nil
            self.ladowanie = nil
            ustawStan(sukces ? .gotowy(modelID: modelID) : .blad(modelID: modelID))
        }
        zadanie = nil
    }

    private func ustawStan(_ stan: StanPrzygotowaniaModelu) {
        guard self.stan != stan else { return }
        self.stan = stan
        poZmianie?()
    }
}
