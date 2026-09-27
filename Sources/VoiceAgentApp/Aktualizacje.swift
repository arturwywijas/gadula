// autor: Codex, gadula-dzwiek-aktualizacje-20260927
import AppKit
import Sparkle

@MainActor
final class Aktualizacje: NSObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    private var kontroler: SPUStandardUpdaterController!
    private var obserwacja: NSKeyValueObservation?
    private var czekaNaKoniecSesji: Task<Void, Never>?
    var trwaDyktowanie: () -> Bool = { false }
    var poZmianie: () -> Void = {}
    private(set) var dostepnaWersja: String?
    private var pobranaWersja: String?
    var pobrana: Bool { pobranaWersja != nil && pobranaWersja == dostepnaWersja }
    private(set) var bladUruchomienia = false

    override init() {
        super.init()
        kontroler = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
    }
    func uruchom() {
        do { try kontroler.updater.start() }
        catch { bladUruchomienia = true; AppLogger(category: "Aktualizacje").error("Nie udało się uruchomić aktualizatora") }
        obserwacja = kontroler.updater.observe(\.canCheckForUpdates) { [weak self] _, _ in
            Task { @MainActor in self?.poZmianie() }
        }
    }
    var automatyczne: Bool { kontroler.updater.automaticallyChecksForUpdates && kontroler.updater.automaticallyDownloadsUpdates }
    var moznaSprawdzic: Bool { !trwaDyktowanie() && kontroler.updater.canCheckForUpdates }
    func przelaczAutomatyczne() {
        let nowa = !automatyczne
        kontroler.updater.automaticallyDownloadsUpdates = nowa
        kontroler.updater.automaticallyChecksForUpdates = nowa
        poZmianie()
    }
    func sprawdz() {
        guard moznaSprawdzic else { return }
        kontroler.checkForUpdates(nil)
    }
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if trwaDyktowanie() {
            throw NSError(domain: "GadulaAktualizacje", code: 1, userInfo: [NSLocalizedDescriptionKey: "Aktualizację można sprawdzić po zakończeniu dyktowania."])
        }
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        if dostepnaWersja != item.displayVersionString { pobranaWersja = nil }
        dostepnaWersja = item.displayVersionString
        poZmianie()
    }
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        pobranaWersja = item.displayVersionString; dostepnaWersja = item.displayVersionString; poZmianie()
        // Sparkle instaluje przy zamknięciu; użytkownik może również wybrać instalację teraz.
        return false
    }
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard trwaDyktowanie() else { return false }
        czekaNaKoniecSesji?.cancel()
        czekaNaKoniecSesji = Task { @MainActor [weak self] in
            while let self, self.trwaDyktowanie() {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
            }
            guard self != nil, !Task.isCancelled else { return }
            installHandler()
        }
        return true
    }
    func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if choice == .skip { pobranaWersja = nil; dostepnaWersja = nil; poZmianie() }
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        pobranaWersja = nil; dostepnaWersja = nil; poZmianie()
    }
    // Gaduła nie ma okna: przypomnienie w menu nie wyrywa fokusu z dyktowanego tekstu.
    var supportsGentleScheduledUpdateReminders: Bool { true }
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool { false }
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        dostepnaWersja = update.displayVersionString; poZmianie()
    }
    func standardUserDriverWillFinishUpdateSession() {
        if !pobrana { dostepnaWersja = nil }
        poZmianie()
    }
}
