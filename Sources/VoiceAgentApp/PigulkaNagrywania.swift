import AppKit
import SwiftUI
import VoiceAgentCore

/// Jedyny odbiorca poziomu; wywolania korzystaja z istniejacego MainActora audio.
@MainActor
protocol WskaznikNagrywania: AnyObject {
    func rozpocznij()
    func przyjmij(szczyt: Float, czas: Double)
    func zakoncz()
}

@MainActor
final class PanelPigulki: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 76, height: 28),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
    }
}

@MainActor
final class PigulkaNagrywania: NSObject, WskaznikNagrywania {
    private let obraz = ObrazPigulki()
    private let magazyn: MagazynUstawien
    private var stan = StanPigulkiNagrywania()
    private var panel: PanelPigulki?
    private var ukrywanie: Task<Void, Never>?
    private var odswiezanie: Timer?
    private var wygaszenieBledu: Task<Void, Never>?

    init(magazyn: MagazynUstawien) {
        self.magazyn = magazyn
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(wygas),
            name: NSApplication.willTerminateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(zmienEkran),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wygas),
            name: NSWorkspace.willSleepNotification, object: nil)
    }

    func ustawGotowosc(_ gotowosc: GotowoscDyktowania) {
        wygaszenieBledu?.cancel()
        obraz.gotowosc = gotowosc
        guard gotowosc != .ukryta else { zakoncz(); return }
        if !stan.nagrywa { rozpocznij() }
        if gotowosc == .blad {
            wygaszenieBledu = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(4)) } catch { return }
                self?.zakoncz()
            }
        }
    }

    func rozpocznij() {
        ukrywanie?.cancel()
        let czas = ProcessInfo.processInfo.systemUptime
        stan.rozpocznij(czas: czas)
        obraz.przygotuj(styl: StylWskaznikaNagrywania.wczytaj(z: magazyn), czas: czas)
        let panel = panel ?? utworzPanel()
        ustawPozycje()
        let poprzedniPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
        panel.orderFrontRegardless()
        obraz.widoczna = true
        AppLogger(category: "Pigulka").notice("show frontmostBefore=\(poprzedniPID) frontmostAfter=\(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1) appActive=\(NSApp.isActive) key=\(panel.isKeyWindow) main=\(panel.isMainWindow)")
        odswiezanie?.invalidate()
        let timer = Timer(timeInterval: 0.05, target: self, selector: #selector(odswiez),
                          userInfo: nil, repeats: true)
        odswiezanie = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func przyjmij(szczyt: Float, czas: Double) {
        stan.przyjmij(szczyt: szczyt, czas: czas)
    }

    @objc private func odswiez(_ timer: Timer) {
        let czas = ProcessInfo.processInfo.systemUptime
        guard stan.odswiez(czas: czas) else { return }
        obraz.odswiez(poziom: stan.poziom, czas: czas)
    }

    func zakoncz() {
        odswiezanie?.invalidate()
        odswiezanie = nil
        let rewizja = stan.zakoncz()
        obraz.widoczna = false
        ukrywanie?.cancel()
        ukrywanie = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(160)) } catch { return }
            guard let self, self.stan.moznaUkryc(rewizja: rewizja) else { return }
            self.panel?.orderOut(nil)
            self.obraz.poziom = 0
        }
    }

    @objc private func wygas(_ notification: Notification) {
        odswiezanie?.invalidate()
        odswiezanie = nil
        ukrywanie?.cancel()
        stan.zakoncz()
        obraz.widoczna = false
        obraz.poziom = 0
        panel?.orderOut(nil)
    }

    @objc private func zmienEkran(_ notification: Notification) {
        if stan.nagrywa { ustawPozycje() }
    }

    private func ustawPozycje() {
        guard let panel else { return }
        let mysz = NSEvent.mouseLocation
        guard let ekran = NSScreen.screens.first(where: { NSMouseInRect(mysz, $0.frame, false) })
            ?? NSScreen.screens.first else { return }
        if obraz.styl == .nicSwiatla {
            panel.setFrame(NSRect(x: ekran.frame.minX, y: ekran.frame.minY,
                                  width: ekran.frame.width, height: 70), display: true)
            return
        }
        panel.setContentSize(obraz.styl == .slupki
                             ? NSSize(width: 270, height: 76)
                             : NSSize(width: 270, height: 96))
        let obszar = ekran.visibleFrame
        let x = max(obszar.minX, min(ekran.frame.midX - panel.frame.width / 2,
                                   obszar.maxX - panel.frame.width))
        let y = max(obszar.minY, min(obszar.minY + 12, obszar.maxY - panel.frame.height))
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func utworzPanel() -> PanelPigulki {
        let nowy = PanelPigulki()
        let widok = NSHostingView(rootView: RysunekWskaznika(obraz: obraz))
        // Rozmiar ustala styl panelu, nie poprzedni intrinsicContentSize slupkow.
        widok.sizingOptions = []
        nowy.contentView = widok
        panel = nowy
        return nowy
    }
}
