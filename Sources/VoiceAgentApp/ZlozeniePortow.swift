import AppKit
import ApplicationServices
import AVFoundation
import VoiceAgentCore

final class MacPermissionChecking: PermissionChecking {
    private static let log = AppLogger(category: "Permissions")

    var mikrofon: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        Self.log.notice("mikrofon przed sesja authorizationStatus=\(Self.nazwa(status))")
        return status == .authorized
    }

    private static func nazwa(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorized: return "authorized"
        @unknown default: return "unknown"
        }
    }

    func poprosOMikrofon() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        Self.log.notice("poprosOMikrofon wywolano authorizationStatus=\(Self.nazwa(status))")
        let granted: Bool
        switch status {
        case .authorized:
            granted = true
        case .notDetermined:
            Self.log.notice("poprosOMikrofon requestAccess audio")
            granted = await AVCaptureDevice.requestAccess(for: .audio)
        default:
            granted = false
        }
        Self.log.notice("poprosOMikrofon wynik granted=\(granted)")
        return granted
    }

    func otworzPanelMikrofonu() {
        DispatchQueue.main.async {
            PermissionsChecker.openMicrophoneSettings()
        }
    }
}

@MainActor
final class TranskrypcjaZDziennikiem: Transcribing {
    private let wewnetrzna: LokalnaTranskrypcja

    init(magazyn: MagazynUstawien) {
        wewnetrzna = LokalnaTranskrypcja(magazyn: magazyn)
    }

    func modelGotowy() async -> Bool {
        await wewnetrzna.modelGotowy()
    }

    var stanPrzygotowaniaModelu: StanPrzygotowaniaModelu { wewnetrzna.stanPrzygotowaniaModelu }
    var poZmianiePrzygotowaniaModelu: (() -> Void)? {
        get { wewnetrzna.poZmianiePrzygotowaniaModelu }
        set { wewnetrzna.poZmianiePrzygotowaniaModelu = newValue }
    }

    func uruchomPrzygotowanieModeluWBiezacymModelu() {
        wewnetrzna.uruchomPrzygotowanieModeluWBiezacymModelu()
    }

    func transcribe(nagranie: Nagranie, jezyk: String) async throws -> Transkrypt {
        do {
            let transkrypt = try await wewnetrzna.transcribe(nagranie: nagranie, jezyk: jezyk)
            let tekst = przygotujTekstDoWstawienia(transkrypt.tekst)
            AppLogger(category: "Sesja").notice(
                "wynik STT znaki=\(tekst.count) pusty=\(ProgiSesji.transkryptJestPusty(tekst))"
            )
            return transkrypt
        } catch {
            // Nie logujemy opisu bledu: moze zawierac dane uzytkownika.
            AppLogger(category: "Sesja").error("wynik STT blad=true")
            throw error
        }
    }
}

enum ZlozeniePortow {
    @MainActor
    static func koordynator(magazyn: MagazynUstawien, transkrypcja: TranskrypcjaZDziennikiem) -> KoordynatorDyktowania {
        let audio = MikrofonAudioCapturing(magazyn: magazyn, wskaznik: PigulkaNagrywania(magazyn: magazyn))
        let id = magazyn.string(klucz: KluczModelu.id, domyslna: KluczModelu.domyslny)
        KatalogModelu.wspolny.uruchomDla(id: id)
        let k = KoordynatorDyktowania(
            audio: audio,
            transcribing: transkrypcja,
            inserting: SchowekTextInserting(),
            permissions: MacPermissionChecking()
        )
        audio.podlacz(koordynator: k)
        return k
    }
}
