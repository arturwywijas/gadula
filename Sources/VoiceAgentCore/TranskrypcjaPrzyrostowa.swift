// autor: Codex, gadula-dyktowanie-20260927
import Foundation

/// Kolejka jednego dekodera. Zachowuje granice sesji także przez await.
@MainActor
public final class TranskrypcjaPrzyrostowa {
    public typealias Rozpoznaj = @MainActor ([Float]) async throws -> String
    private let rozpoznaj: Rozpoznaj
    private var podzial = PodzialNagrania()
    private var generacja: UInt64 = 0
    private var aktywna = false
    private var odebrane = 0
    private var ogon: Task<String, Error>?
    private var poprzednia: Task<String, Error>?
    private var zadania: [Task<String, Error>] = []
    public init(rozpoznaj: @escaping Rozpoznaj) { self.rozpoznaj = rozpoznaj }

    public func rozpocznij() {
        anuluj()
        podzial = PodzialNagrania()
        odebrane = 0
        aktywna = true
    }
    public func przyjmij(_ pcm: [Float]) {
        guard aktywna else { return }
        odebrane += pcm.count
        for fragment in podzial.przyjmij(pcm) { zlec(fragment) }
    }
    public func anuluj() {
        generacja &+= 1
        aktywna = false
        if let ogon { poprzednia = ogon }
        zadania.forEach { $0.cancel() }
        zadania.removeAll()
        ogon = nil
        podzial = PodzialNagrania()
    }
    private func zlec(_ pcm: [Float]) {
        guard !pcm.isEmpty else { return }
        let id = generacja
        let poprzedniFragment = ogon
        let bariera = poprzednia
        ogon = Task { [weak self] in
            let wczesniejszy: String
            if let poprzedniFragment { wczesniejszy = try await poprzedniFragment.value }
            else { _ = await bariera?.result; wczesniejszy = "" }
            guard let self, self.generacja == id, !Task.isCancelled else { throw CancellationError() }
            let tekst = try await self.rozpoznaj(pcm)
            guard self.generacja == id, !Task.isCancelled else { throw CancellationError() }
            return [wczesniejszy, tekst].filter { !$0.isEmpty }.joined(separator: " ")
        }
        if let ogon { zadania.append(ogon) }
    }
    public func zakoncz(caleNagranie pcm: [Float]) async throws -> String {
        let id = generacja
        defer {
            if generacja == id {
                ogon = nil; poprzednia = nil; zadania.removeAll(); podzial = PodzialNagrania()
            }
        }
        aktywna = false
        if odebrane == pcm.count { zlec(podzial.zakoncz()) }
        do {
            guard odebrane == pcm.count, let ogon else { throw BrakFragmentow() }
            let wynik = try await ogon.value
            guard generacja == id else { throw CancellationError() }
            return wynik
        } catch {
            guard generacja == id, !Task.isCancelled else { throw CancellationError() }
            // Błąd fragmentu lub niespójny strumień: całość zastępuje fragmenty.
            _ = await ogon?.result
            _ = await poprzednia?.result
            guard generacja == id, !Task.isCancelled else { throw CancellationError() }
            let pelne = Task { [weak self] in
                guard let self, self.generacja == id, !Task.isCancelled else { throw CancellationError() }
                let wynik = try await self.rozpoznaj(pcm)
                guard self.generacja == id, !Task.isCancelled else { throw CancellationError() }
                return wynik
            }
            ogon = pelne
            zadania.append(pelne)
            return try await pelne.value
        }
    }
    private struct BrakFragmentow: Error {}
}
