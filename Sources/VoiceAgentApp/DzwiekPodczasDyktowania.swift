// autor: Codex, gadula-dzwiek-aktualizacje-20260927
import AppKit
import VoiceAgentCore

@MainActor
final class DzwiekPodczasDyktowania {
    static let klucz = "dzwiek.sciszaj"
    private let ustawienia: UserDefaults
    private let sciszanie: SciszanieDzwieku
    private var zadanie: Task<Void, Never>?
    private var gotowosc: GotowoscDyktowania = .ukryta
    private var obserwatorSnu: NSObjectProtocol?
    private var obserwatorPobudki: NSObjectProtocol?
    var wlaczone: Bool { ustawienia.object(forKey: Self.klucz) as? Bool ?? true }

    init(ustawienia: UserDefaults = .standard) {
        self.ustawienia = ustawienia
        let dziennik = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Gadula/glosnosc.json")
        let zapisane = (try? Data(contentsOf: dziennik)).flatMap { try? JSONDecoder().decode([SladGlosnosci].self, from: $0) } ?? []
        sciszanie = SciszanieDzwieku(wyjscie: GlosnoscSystemowa(), zapisane: zapisane) { slady in
            do {
                try FileManager.default.createDirectory(at: dziennik.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(slady).write(to: dziennik, options: .atomic)
                return true
            } catch {
                AppLogger(category: "Audio").error("Nie udało się zachować poziomu głośności do odzyskania po restarcie")
                return false
            }
        }
        sciszanie.przywrocNatychmiast()
        obserwatorSnu = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.zakoncz() }
        }
        obserwatorPobudki = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.uruchomZegar() }
        }
        uruchomZegar()
    }
    func przelacz() {
        ustawienia.set(!wlaczone, forKey: Self.klucz)
        ustawGotowosc(gotowosc)
    }
    func ustawGotowosc(_ stan: GotowoscDyktowania) {
        gotowosc = stan
        if wlaczone && (stan == .mikrofon || stan == .gotowa) {
            sciszanie.rozpocznij(czas: ProcessInfo.processInfo.systemUptime)
        } else {
            sciszanie.zakoncz(czas: ProcessInfo.processInfo.systemUptime)
        }
        uruchomZegar()
    }
    func zakoncz() {
        zadanie?.cancel(); zadanie = nil
        sciszanie.przywrocNatychmiast()
    }
    private func uruchomZegar() {
        guard zadanie == nil, sciszanie.wymagaKrokow else { return }
        zadanie = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.sciszanie.krok(czas: ProcessInfo.processInfo.systemUptime)
                if !self.sciszanie.wymagaKrokow { self.zadanie = nil; return }
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
    }
}
