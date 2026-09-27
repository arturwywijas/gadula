// autor: Codex, gadula-dzwiek-aktualizacje-20260927
// Osobny proces testowy. Automatyczne odpowiedzi dotyczą wyłącznie kopii w .build.
import AppKit
import Sparkle

@MainActor
final class ProbaAktualizacji: NSObject, NSApplicationDelegate, SPUUserDriver, SPUUpdaterDelegate {
    var updater: SPUUpdater!
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard CommandLine.arguments.count == 3, let host = Bundle(path: CommandLine.arguments[1]), CommandLine.arguments[1].contains("/.build/update-test/") else { exit(2) }
        updater = SPUUpdater(hostBundle: host, applicationBundle: Bundle.main, userDriver: self, delegate: self)
        do { try updater.start(); updater.checkForUpdates() }
        catch { print("FAIL start: \(error)"); exit(1) }
        // Przy aktualizacji zewnętrznego bundla host już nie działa. Installer
        // może zakończyć instalację bez callbacku UI; weryfikujemy plik z dysku.
        let plist = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("Contents/Info.plist")
        Task {
            for _ in 0..<250 {
                try? await Task.sleep(for: .milliseconds(200))
                if let data = try? Data(contentsOf: plist),
                   let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                   info["CFBundleVersion"] as? String == "4" {
                    try? await Task.sleep(for: .seconds(1))
                    print("Zainstalowana wersja4 na dysku; skrypt sprawdzi podpis i identyczność binarki")
                    exit(0)
                }
            }
            print("FAIL timeout aktualizacji"); exit(1)
        }
    }
    func feedURLString(for updater: SPUUpdater) -> String? { CommandLine.arguments[2] }
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) { reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false)) }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) { print("Znaleziono: \(appcastItem.displayVersionString)"); reply(.install) }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) { print("BRAK AKTUALIZACJI: \(error)"); acknowledgement(); exit(3) }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) { let ns = error as NSError
        let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError
        print("ODRZUCONO domain=\(ns.domain) code=\(ns.code) underlying=\(underlying?.code ?? 0)")
        acknowledgement(); exit(4) }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {}
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() { print("Rozpakowanie zweryfikowanej aktualizacji") }
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { reply(.install) }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { print("PASS: Sparkle pobrał, zweryfikował i zainstalował aktualizację"); acknowledgement(); exit(0) }
    func dismissUpdateInstallation() {}
}

@main enum Main {
    @MainActor static func main() {
        let app = NSApplication.shared; let delegate = ProbaAktualizacji()
        app.delegate = delegate; app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
