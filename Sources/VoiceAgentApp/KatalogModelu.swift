import Foundation
import WhisperKit

enum KluczModelu {
    static let id = "model"
    static let domyslny = WariantModelu.largeTurbo.rawValue
}

enum WariantModelu: String, CaseIterable {
    case largeTurbo = "large-v3-turbo"
    case small = "small"

    var whisperKitID: String {
        switch self {
        case .largeTurbo:
            return WhisperKitTranscriber.defaultModelID
        case .small:
            return "small"
        }
    }

    var etykieta: String {
        switch self {
        case .largeTurbo:
            return "large-v3-turbo (zalecany)"
        case .small:
            return "small (szybszy, gorszy polski)"
        }
    }
}

enum StanPobieraniaModelu: Equatable {
    case niepobrany
    case pobieranie(postep: Double)
    case gotowy
    case przerwane
}

@MainActor
final class KatalogModelu {
    static let wspolny = KatalogModelu()

    private(set) var stan: StanPobieraniaModelu = .niepobrany
    var odswiez: (() -> Void)?
    private var zadanie: Task<Void, Never>?

    func jestNaDysku(_ wariant: WariantModelu) -> Bool {
        WagiModeluNaDysku.saKompletne(dla: wariant)
    }

    func tytulSekcji() -> String {
        switch stan {
        case .gotowy:
            return "Model"
        case .pobieranie(let postep):
            let procent = max(0, min(100, Int((postep * 100).rounded())))
            return "Model (pobieranie \(procent)%)"
        case .przerwane:
            return "Model (pobieranie przerwane)"
        case .niepobrany:
            return "Model (niegotowy)"
        }
    }

    func uruchomDla(id: String) {
        let wariant = WariantModelu(rawValue: id) ?? .largeTurbo
        if jestNaDysku(wariant) {
            zadanie?.cancel()
            zadanie = nil
            stan = .gotowy
            odswiez?()
            return
        }
        pobierz(wariant)
    }

    func ponow(id: String) {
        pobierz(WariantModelu(rawValue: id) ?? .largeTurbo)
    }

    private func pobierz(_ wariant: WariantModelu) {
        zadanie?.cancel()
        stan = .pobieranie(postep: 0)
        odswiez?()
        let id = wariant.whisperKitID
        zadanie = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await WhisperKit.download(variant: id) { progress in
                    let wartosc = progress.fractionCompleted
                    Task { @MainActor [weak self] in
                        guard let self, !Task.isCancelled else { return }
                        if case .pobieranie = self.stan {
                            self.stan = .pobieranie(postep: wartosc)
                            self.odswiez?()
                        }
                    }
                }
                guard !Task.isCancelled else { return }
                self.stan = self.jestNaDysku(wariant) ? .gotowy : .przerwane
                self.odswiez?()
            } catch {
                guard !Task.isCancelled else { return }
                self.stan = .przerwane
                self.odswiez?()
            }
        }
    }
}

enum WagiModeluNaDysku {
    static func saKompletne(dla wariant: WariantModelu) -> Bool {
        guard let folder = WhisperKitTranscriber.folderNaDysku(dla: wariant.whisperKitID) else {
            return false
        }
        guard let elementy = try? FileManager.default.contentsOfDirectory(atPath: folder) else {
            return false
        }
        return elementy.contains { $0.hasSuffix(".mlmodelc") }
    }
}
