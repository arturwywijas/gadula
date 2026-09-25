/// Limit ścienny niezależny od dostarczenia próbek PCM.
@MainActor
public final class LimitCzasuNagrania {
    private var zadanie: Task<Void, Never>?
    private var generacja: UInt64 = 0

    public init() {}
    deinit { zadanie?.cancel() }

    public func rozpocznij(po czas: Duration, wykonaj: @escaping @MainActor () -> Void) {
        anuluj()
        let id = generacja
        zadanie = Task { [weak self] in
            do { try await Task.sleep(for: czas) }
            catch { return }
            guard let self, self.generacja == id else { return }
            self.zadanie = nil
            wykonaj()
        }
    }

    public func anuluj() {
        generacja &+= 1
        zadanie?.cancel()
        zadanie = nil
    }
}
