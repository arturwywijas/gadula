import AppKit
import Carbon.HIToolbox
import GadulaArtwork
import VoiceAgentCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let log = AppLogger(category: "Skrot")
    private var statusItem: NSStatusItem?
    private let hotkeys = HotkeyManager()
    private let koordynator: KoordynatorDyktowania
    private let magazyn: MagazynUstawien
    private let transkrypcja: TranskrypcjaZDziennikiem
    private let celAkcji = CelAkcjiMenu()
    private var busy = false
    private var oczekujePuszczenia = false
    private var zadanieBledu: Task<Void, Never>?
    private var zadanieKomunikatuBusy: Task<Void, Never>?
    private var komunikatBusy: String?
    private var escGlobal: Any?
    private var escLokalny: Any?

    override init() {
        let magazyn = MagazynUstawien(zrodlo: UserDefaults.standard)
        let transkrypcja = TranskrypcjaZDziennikiem(magazyn: magazyn)
        self.magazyn = magazyn
        self.transkrypcja = transkrypcja
        koordynator = ZlozeniePortow.koordynator(magazyn: magazyn, transkrypcja: transkrypcja)
        super.init()
        transkrypcja.poZmianiePrzygotowaniaModelu = { [weak self] in
            Task { @MainActor in self?.refreshStatus() }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        koordynator.poZakonczeniuSesji = { [weak self] in
            Task { @MainActor in self?.refreshStatus() }
        }
        installStatusItem()
        podlaczWyzwalacz()
        podlaczEscape()
        refreshStatus()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeys.stop()
        zadanieKomunikatuBusy?.cancel()
        if let escGlobal { NSEvent.removeMonitor(escGlobal) }
        if let escLokalny { NSEvent.removeMonitor(escLokalny) }
    }

    private func toggleSesji() {
        Self.log.notice("FN09 coordinator trigger busy=\(self.busy) state=\(String(describing: self.koordynator.stan)) decision=\(self.busy ? "rejectBusy" : (self.koordynator.stan == .transkrypcja || self.koordynator.stan == .wstawianie ? "ignoreState" : "accept"))")
        guard !busy else {
            pokazKomunikatZajetosci()
            return
        }
        busy = true
        Task { @MainActor in
            await koordynator.handleWyzwalacz()
            Self.log.notice("FN09 coordinator result state=\(String(describing: self.koordynator.stan))")
            if oczekujePuszczenia, koordynator.stan == .nagrywanie {
                oczekujePuszczenia = false
                await koordynator.handleWyzwalacz()
            }
            oczekujePuszczenia = false
            busy = false
            refreshStatus()
        }
    }

    private func pokazKomunikatZajetosci() {
        komunikatBusy = "Aplikacja zajęta. Spróbuj za chwilę."
        zadanieKomunikatuBusy?.cancel()
        refreshStatus()
        zadanieKomunikatuBusy = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.komunikatBusy = nil
            self.refreshStatus()
        }
    }

    private func wcisniecieWyzwalacza(pushToTalk: Bool) {
        let wymagaSygnaluZajetosci = SygnalZajetosciPTT.wymagany(gdy: koordynator.stan)
        Self.log.notice("FN09 onPress pushToTalk=\(pushToTalk) state=\(String(describing: self.koordynator.stan)) decision=\(pushToTalk && wymagaSygnaluZajetosci ? "busySignal" : "forward")")
        if pushToTalk {
            if koordynator.stan == .bezczynny {
                toggleSesji()
            } else if wymagaSygnaluZajetosci {
                pokazKomunikatZajetosci()
            }
            return
        }
        toggleSesji()
    }

    private func puszczenieWyzwalacza(pushToTalk: Bool) {
        Self.log.notice("FN09 onRelease pushToTalk=\(pushToTalk) busy=\(self.busy) state=\(String(describing: self.koordynator.stan)) decision=\(!pushToTalk ? "ignoreToggleRelease" : (self.busy ? "defer" : (self.koordynator.stan == .nagrywanie ? "forward" : "ignoreState")))")
        guard pushToTalk else { return }
        if busy {
            oczekujePuszczenia = true
            return
        }
        if koordynator.stan == .nagrywanie {
            toggleSesji()
            return
        }
    }

    private func podlaczWyzwalacz() {
        // Zapis w menu obowiązuje od następnej sesji, bez zmiany callbacku puszczenia.
        guard !busy, koordynator.stan == .bezczynny else { return }
        let combo = KeyCombo.wczytaj(z: magazyn)
        let ptt = combo.isPushToTalk
        hotkeys.onPress = { [weak self] in self?.wcisniecieWyzwalacza(pushToTalk: ptt) }
        hotkeys.onRelease = { [weak self] in self?.puszczenieWyzwalacza(pushToTalk: ptt) }
        hotkeys.update(combo: combo)
        if !hotkeys.isRunning {
            hotkeys.start()
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = IkonaGaduly.obrazPaska(stan: .bezczynna)
        item.button?.setAccessibilityLabel("Dyktowanie")
        statusItem = item
        refreshStatus()
    }

    private func refreshStatus() {
        podlaczWyzwalacz()
        transkrypcja.uruchomPrzygotowanieModeluWBiezacymModelu()
        let przygotowujeModel: Bool
        if case .przygotowuje = transkrypcja.stanPrzygotowaniaModelu {
            przygotowujeModel = true
        } else {
            przygotowujeModel = false
        }
        let stan: String
        if let komunikatBusy {
            stan = komunikatBusy
        } else if koordynator.stan == .bezczynny, przygotowujeModel {
            stan = "Przygotowywanie modelu"
        } else {
            stan = stanKoordynatora
        }
        let kontekst = KontekstMenu(
            etykietaStanu: stan,
            stanPrzygotowaniaModelu: transkrypcja.stanPrzygotowaniaModelu,
            poziomWejsciaMikrofonuDb: koordynator.poziomWejsciaMikrofonuDb,
            bladSkrotu: hotkeys.bladRejestracji,
            cel: celAkcji,
            magazyn: magazyn,
            odswiez: { [weak self] in self?.refreshStatus() },
            dyktuj: { [weak self] in self?.toggleSesji() },
            zakoncz: { NSApp.terminate(nil) }
        )
        statusItem?.menu = MenuPaska.zbuduj(kontekst: kontekst)
        odswiezIkone()
        zaplanujPowrotZBledu()
    }

    private var stanKoordynatora: String {
        switch koordynator.stan {
        case .bezczynny:
            return koordynator.ostatniKomunikat ?? "Bezczynny"
        case .nagrywanie:
            return "Nagrywanie"
        case .transkrypcja:
            return "Transkrypcja"
        case .wstawianie:
            return "Wstawianie"
        }
    }

    private func odswiezIkone() {
        let stanIkony: StanIkonyGaduly
        let opis: String
        if komunikatBusy != nil {
            stanIkony = .zajetosc
            opis = "Aplikacja zajęta"
        } else if koordynator.stan == .bezczynny, case .przygotowuje = transkrypcja.stanPrzygotowaniaModelu {
            stanIkony = .przygotowanieModelu
            opis = "Przygotowywanie modelu"
        } else {
            switch koordynator.stanIkony {
            case .bezczynny:
                stanIkony = .bezczynna
                opis = "Bezczynny"
            case .nagrywa:
                stanIkony = .nagrywanie
                opis = "Nagrywa"
            case .przetwarza:
                stanIkony = .przetwarzanie
                opis = "Przetwarza"
            case .blad:
                stanIkony = .blad
                opis = "Błąd"
            }
        }
        statusItem?.button?.image = IkonaGaduly.obrazPaska(stan: stanIkony)
        statusItem?.button?.setAccessibilityLabel(opis)
        statusItem?.button?.toolTip = opis
        statusItem?.button?.title = komunikatBusy == nil ? "" : " Zajęta"
        statusItem?.button?.appearsDisabled = koordynator.stanIkony == .przetwarza
    }

    private func zaplanujPowrotZBledu() {
        zadanieBledu?.cancel()
        guard koordynator.stanIkony == .blad else { return }
        zadanieBledu = Task { @MainActor in
            let ns = UInt64(ProgiSesji.czasIkonyBledu * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
            guard !Task.isCancelled else { return }
            koordynator.wyczyscIkoneBledu()
            refreshStatus()
        }
    }

    private func podlaczEscape() {
        let naEsc: (NSEvent) -> Void = { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else { return }
            Task { @MainActor in
                if self?.koordynator.stan == .nagrywanie {
                    AppLogger(category: "Audio").notice("FN15 audio cancel reason=escape")
                }
                await self?.koordynator.anuluj()
                self?.refreshStatus()
            }
        }
        escGlobal = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            naEsc(event)
        }
        escLokalny = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            naEsc(event)
            return event
        }
    }
}

@main
enum VoiceAgentMain {
    static func main() {
        let katalog = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Gadula")
        guard let blokada = try? BlokadaInstancji(url: katalog.appendingPathComponent("instance.lock")),
              blokada.przejmij() else { return }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(blokada) { app.run() }
    }
}
