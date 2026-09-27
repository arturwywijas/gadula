// Pochodzi ze snapshotu vlr-code/dictly (MIT).
import Foundation
@preconcurrency import AVFoundation
import CoreAudio
import VoiceAgentCore
import AudioTapGuard

/// Captures microphone audio and produces a Whisper-ready buffer:
/// 16 kHz, mono, Float32 PCM.
///
/// **Cold-start design.** The audio engine boots in `start()` and is fully torn down in
/// `stop()`. As a result, macOS only shows the orange "mic in use" indicator while a
/// recording is actively in progress — which is what the user expects from a privacy
/// standpoint.
///
/// Silnik istnieje tylko podczas sesji. Samo stop/removeTap pozostawia AUHAL
/// i profil rozmowy Bluetooth, dlatego po stop zwalniamy także silnik i obserwator.
/// Podczas zmiany formatu wewnątrz nagrania zachowujemy silnik oraz zebrane PCM.
@MainActor
final class AudioRecorder {

    private static let log = AppLogger(category: "Audio")

    nonisolated static let targetSampleRate: Double = 16_000

    /// Spec D9: on the 120 s cap, stop capture and transcribe what was already said.
    var onLimitCzasu: (([Float]) -> Void)?
    var onPoziom: ((Float, Double) -> Void)?
    var onZatrzymanie: (() -> Void)?
    var onProbki: (([Float]) -> Void)?
    var onPierwszeProbki: (() -> Void)?
    var onBrakDzwieku: (() -> Void)?
    var onZmianaKonfiguracji: ((Double) -> Void)?
    nonisolated(unsafe) private var obserwatorKonfiguracji: NSObjectProtocol?
    private var formatTapu: AVAudioFormat?
    private var formatPoStarcie: AVAudioFormat?
    private var ochronaRekonfiguracji = OchronaRekonfiguracjiAudio()
    private let stabilizacja = LimitCzasuNagrania()
    private let kontrolaDzwieku = LimitCzasuNagrania()
    private var nadzorDzwieku = NadzorDzwieku()
    private var pokazanoOdbiorDzwieku = false
    private var generacjaTapu: UInt64 = 0

    enum BladKonfiguracji: Error { case niezgodnyFormat, instalacjaTapu }

    var uzywaneUrzadzenieIstnieje: Bool {
        guard let uid = lastConfiguredInputUID else { return false }
        return AudioDeviceManager.deviceExists(lastConfiguredInputID, expectedUID: uid)
    }

    private var wymagaPrzeladowania: Bool {
        let node = engine.inputNode
        let wyjscie = node.outputFormat(forBus: 0)
        let sprzet = node.inputFormat(forBus: 0)
        let zmianaFormatu = !Self.tenSamPCM(formatPoStarcie, wyjscie)
        let rozjazdSprzetu = !OcenaKonfiguracjiAudio.zgodnyFormat(tapHz: wyjscie.sampleRate, tapKanaly: wyjscie.channelCount,
            sprzetHz: sprzet.sampleRate, sprzetKanaly: sprzet.channelCount)
        let zmianaUrzadzenia = AudioDeviceManager.defaultInputDeviceID() != lastConfiguredInputID
        Self.log.notice("FN18 configuration compare installedTap=\(Self.opisz(formatTapu)) baselineAfterStart=\(Self.opisz(formatPoStarcie)) nodeOutput=\(Self.opisz(wyjscie)) hardwareInput=\(Self.opisz(sprzet)) running=\(self.engine.isRunning) outputChanged=\(zmianaFormatu) hardwareMismatch=\(rozjazdSprzetu) deviceChanged=\(zmianaUrzadzenia)")
        return !engine.isRunning || zmianaUrzadzenia || zmianaFormatu || rozjazdSprzetu
    }

    func ocenZmianeKonfiguracji(czasZdarzenia: Double) -> OchronaRekonfiguracjiAudio.Decyzja {
        guard state == .recording, silnik != nil else { return .bezZmiany }
        let decyzja = ochronaRekonfiguracji.ocen(czasZdarzenia: czasZdarzenia,
            nagrywa: state == .recording, istnieje: uzywaneUrzadzenieIstnieje,
            wymaga: wymagaPrzeladowania)
        Self.log.notice("FN18 configuration decision=\(String(describing: decyzja)) attempts=\(self.ochronaRekonfiguracji.liczbaProb) maxAttempts=\(OchronaRekonfiguracjiAudio.maksymalnaLiczbaProb)")
        return decyzja
    }

    private static func tenSamPCM(_ a: AVAudioFormat?, _ b: AVAudioFormat) -> Bool {
        guard let a else { return false }
        return OcenaKonfiguracjiAudio.zgodnyFormat(tapHz: a.sampleRate, tapKanaly: a.channelCount,
            sprzetHz: b.sampleRate, sprzetKanaly: b.channelCount)
            && a.commonFormat == b.commonFormat && a.isInterleaved == b.isInterleaved
    }

    private static func opisz(_ format: AVAudioFormat?) -> String {
        guard let format else { return "none" }
        return "hz=\(format.sampleRate),ch=\(format.channelCount),type=\(format.commonFormat.rawValue),interleaved=\(format.isInterleaved)"
    }

    func przeladujPoZmianieKonfiguracji() throws {
        guard state == .recording else { return }
        Self.log.notice("FN15 audio reconfigure reason=configurationChange preserveSession=true")
        do {
            try bringUpEngine(zachowajSesje: true)
        } catch {
            engineNeedsRebuild = true
            throw error
        }
    }

    deinit {
        if let obserwatorKonfiguracji { NotificationCenter.default.removeObserver(obserwatorKonfiguracji) }
    }

    private func obserwujSilnik() {
        if let obserwatorKonfiguracji { NotificationCenter.default.removeObserver(obserwatorKonfiguracji) }
        let id = ObjectIdentifier(engine)
        obserwatorKonfiguracji = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            let czasZdarzenia = ProcessInfo.processInfo.systemUptime
            Task { @MainActor [weak self] in
                guard let self, let silnik = self.silnik, ObjectIdentifier(silnik) == id else { return }
                self.onZmianaKonfiguracji?(czasZdarzenia)
            }
        }
    }

    private func zwolnijSilnik() {
        if let obserwatorKonfiguracji {
            NotificationCenter.default.removeObserver(obserwatorKonfiguracji)
            self.obserwatorKonfiguracji = nil
        }
        if let silnik {
            if formatTapu != nil { silnik.inputNode.removeTap(onBus: 0) }
            silnik.stop()
            silnik.reset()
        }
        silnik = nil
        converter = nil
        sourceFormat = nil
        formatTapu = nil
        formatPoStarcie = nil
    }

    private func odbudujSilnik() {
        zwolnijSilnik()
        silnik = AVAudioEngine()
        formatTapu = nil
        formatPoStarcie = nil
        obserwujSilnik()
    }

    private func zgodnyZeSprzetem(_ format: AVAudioFormat, node: AVAudioInputNode) -> Bool {
        let sprzet = node.inputFormat(forBus: 0)
        let zgodny = OcenaKonfiguracjiAudio.zgodnyFormat(
            tapHz: format.sampleRate, tapKanaly: format.channelCount,
            sprzetHz: sprzet.sampleRate, sprzetKanaly: sprzet.channelCount)
        Self.log.notice("FN18 hardware check tapCandidate=\(Self.opisz(format)) hardwareInput=\(Self.opisz(sprzet)) matches=\(zgodny)")
        return zgodny
    }

    /// Two-minute recording cap to bound memory; recognition handles shorter windows.
    static let maxDurationSeconds: TimeInterval = ProgiSesji.maksymalnyCzasTrwania

    enum State { case idle, recording }
    private(set) var state: State = .idle

    private var silnik: AVAudioEngine?
    // Odczyt nie może tworzyć silnika: po stop nic nie może ponownie otworzyć AUHAL.
    private var engine: AVAudioEngine {
        precondition(silnik != nil, "Silnik dostępny tylko podczas sesji")
        return silnik!
    }
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    private var samples: [Float] = []
    private let limitCzasu = LimitCzasuNagrania()
    private var tapCallbacks: Int = 0

    /// Tożsamość wejścia aktywnego silnika (HAL może ponownie użyć numeru ID).
    private var lastConfiguredInputID: AudioDeviceID = 0
    private var lastConfiguredInputUID: String?
    /// ID zapamiętany dla silnika używanego do bieżącego nagrania, tylko do odczytu.
    var uzywaneUrzadzenieID: AudioDeviceID? {
        guard lastConfiguredInputID != 0 else { return nil }
        return lastConfiguredInputID
    }
    /// Set when a start attempt failed — the engine may be half-configured, so the
    /// next attempt rebuilds it instead of trusting `lastConfiguredInput*`.
    private var engineNeedsRebuild = false
    /// Tap AVAudioEngine biegnie na RealtimeMessenger, nie na main.
    /// Closure z bringUpEngine (@MainActor) dostawalaby assert libdispatch.
    /// Relay raz w init: onBuffer jest let, zero zapisu z main przy kazdej sesji.
    private let tapRelay: TapRelay

    init() {
        let wlasciciel = WlascicielTapRelay()
        tapRelay = TapRelay { buffer, generacja in
            wlasciciel.recorder?.processTap(buffer: buffer, generacja: generacja)
        }
        wlasciciel.recorder = self
    }

    private let targetFormat: AVAudioFormat = {
        AVAudioFormat(commonFormat: .pcmFormatFloat32,
                      sampleRate: AudioRecorder.targetSampleRate,
                      channels: 1,
                      interleaved: false)!
    }()

    func start() throws {
        guard state == .idle else { return }
        ochronaRekonfiguracji = OchronaRekonfiguracjiAudio()

        do {
            do {
                try bringUpEngine()
            } catch let error as NSError where error.code == -10868 {
                // kAudioFormatUnsupportedFormatError. Almost always transient — the
                // audio route is mid-transition (BT handshake, default input changed).
                // This handles a thrown NSError from start, not an Objective-C exception.
                // As a last resort, recreate the engine from scratch and retry once.
                Self.log.notice("AVAudio start failed with -10868; recreating engine and retrying after 250ms")
                usleep(250_000)
                zwolnijSilnik()
                odbudujSilnik()
                try bringUpEngine()
            }
        } catch {
            limitCzasu.anuluj()
            stabilizacja.anuluj()
            Self.log.error("FN15 audio start failed reason=startFailure")
            zwolnijSilnik()
            engineNeedsRebuild = true
            throw error
        }

        state = .recording
        pokazanoOdbiorDzwieku = false
        nadzorDzwieku.rozpocznij(czas: ProcessInfo.processInfo.systemUptime)
        sprawdzDostarczanieDzwieku()
        limitCzasu.rozpocznij(po: .seconds(Self.maxDurationSeconds)) { [weak self] in
            guard let self, self.state == .recording else { return }
            Self.log.notice("FN15 audio stop reason=timeLimit")
            let samples = self.stop()
            self.onLimitCzasu?(samples)
        }
        let inputFmt = engine.inputNode.outputFormat(forBus: 0)
        Self.log.info("Recording started; engine.isRunning=\(self.engine.isRunning) inputFormat=\(String(format: "%.0f", inputFmt.sampleRate))Hz/\(inputFmt.channelCount)ch")
    }

    /// Prepare the engine and start capture.
    ///
    /// Nowy silnik powstaje dopiero przy starcie kolejnej sesji, po zwolnieniu
    /// poprzedniego. Rekonfiguracja w trakcie nagrania nie odtwarza go bez potrzeby.
    /// Wybór mikrofonu stosuje systemowe wejście, bez ręcznego rebindingu AUHAL.
    private func bringUpEngine(zachowajSesje: Bool = false) throws {
        stabilizacja.anuluj()
        ochronaRekonfiguracji.rozpocznijPrzebudowe()
        var uruchomiony = false
        defer {
            ochronaRekonfiguracji.zakonczPrzebudowe(czas: ProcessInfo.processInfo.systemUptime)
            if uruchomiony {
                // Jedna kontrola po okresie ochronnym: nie gubimy rzeczywistej zmiany w tym czasie.
                stabilizacja.rozpocznij(po: .seconds(OchronaRekonfiguracjiAudio.czasStabilizacji)) { [weak self] in
                    guard let self, self.state == .recording else { return }
                    self.onZmianaKonfiguracji?(ProcessInfo.processInfo.systemUptime)
                }
            }
        }
        generacjaTapu &+= 1
        if let silnik {
            if silnik.isRunning { silnik.stop() }
            if formatTapu != nil { silnik.inputNode.removeTap(onBus: 0) }
        }

        let currentInput = AudioDeviceManager.defaultInputDeviceID() ?? 0
        let currentUID = currentInput != 0 ? AudioDeviceManager.uid(for: currentInput) : nil
        let currentName = currentInput != 0 ? AudioDeviceManager.name(for: currentInput) : nil
        if silnik == nil || engineNeedsRebuild || currentInput != lastConfiguredInputID
            || currentUID != lastConfiguredInputUID {
            odbudujSilnik()
            engineNeedsRebuild = false
            lastConfiguredInputID = currentInput
            lastConfiguredInputUID = currentUID
            Self.log.info(
                "Engine (re)created for input device id=\(currentInput) name=\(currentName ?? "-") uid=\(currentUID ?? "-")"
            )
        }

        converter = nil
        sourceFormat = nil
        if !zachowajSesje {
            samples.removeAll(keepingCapacity: true)
            tapCallbacks = 0
        }

        // Po zmianie profilu Bluetooth silnik zatrzymuje się, ale wyjście węzła
        // zachowuje stary format. Przeformatowujemy tap do bieżącego wejścia.
        // Odbudowa całego silnika w tym miejscu ponawiała negocjację 44,1 -> 16 kHz.
        Self.log.notice("FN18 tap preflight installedTap=\(Self.opisz(formatTapu)) nodeOutput=\(Self.opisz(engine.inputNode.outputFormat(forBus: 0))) hardwareInput=\(Self.opisz(engine.inputNode.inputFormat(forBus: 0)))")
        let node = engine.inputNode
        let kandydat = node.inputFormat(forBus: 0)
        guard zgodnyZeSprzetem(kandydat, node: node) else {
            engineNeedsRebuild = true
            Self.log.error("FN15 tap not installed reason=unstableOrInvalidFormat")
            throw BladKonfiguracji.niezgodnyFormat
        }
        formatTapu = kandydat
        do {
            try Self.zainstalujTap(node: node, format: kandydat, relay: tapRelay, generacja: generacjaTapu)
        } catch {
            engineNeedsRebuild = true
            // Po NSException nie używamy ponownie częściowo skonfigurowanego silnika.
            zwolnijSilnik()
            Self.log.error("FN16 audio stop reason=tapInstallationException")
            throw error
        }
        engine.prepare()
        try engine.start()

        let tapFormat = engine.inputNode.outputFormat(forBus: 0)
        formatPoStarcie = tapFormat
        uruchomiony = true
        Self.log.notice("FN18 engine started installedTap=\(Self.opisz(formatTapu)) nodeOutput=\(Self.opisz(tapFormat)) hardwareInput=\(Self.opisz(engine.inputNode.inputFormat(forBus: 0))) preserveSession=\(zachowajSesje)")
        Self.log.info(
            "format po starcie sr=\(String(format: "%.0f", tapFormat.sampleRate))Hz ch=\(tapFormat.channelCount) id=\(currentInput) name=\(currentName ?? "-") uid=\(currentUID ?? "-") running=\(self.engine.isRunning)"
        )
        // Wzorzec pochodzi z uruchomionego silnika; kolejną ocenę wykonujemy po stabilizacji.
        // Brak PCM przy stop jest obslugiwany przez koordynator jako awaria.

    }

    func stop() -> [Float] {
        limitCzasu.anuluj()
        stabilizacja.anuluj()
        kontrolaDzwieku.anuluj()
        nadzorDzwieku.zakoncz()
        ochronaRekonfiguracji = OchronaRekonfiguracjiAudio()
        guard state == .recording else { zwolnijSilnik(); return [] }
        state = .idle
        generacjaTapu &+= 1
        onZatrzymanie?()

        zwolnijSilnik()

        let result = samples
        samples.removeAll(keepingCapacity: false)

        var peak: Float = 0
        for v in result { let a = v < 0 ? -v : v; if a > peak { peak = a } }
        let durationSec = Double(result.count) / Self.targetSampleRate
        let deviceID = lastConfiguredInputID
        let deviceName = AudioDeviceManager.name(for: deviceID) ?? "-"
        Self.log.info(
            "Recording stopped; id=\(deviceID) name=\(deviceName) samples=\(result.count) (\(String(format: "%.2f", durationSec))s) peak=\(String(format: "%.4f", peak)) tapCallbacks=\(self.tapCallbacks)"
        )
        if result.isEmpty {
            Self.log.error("Recording stopped; zero PCM samples")
        }
        if self.tapCallbacks == 0 {
            Self.log.notice("No tap callbacks fired - engine never delivered audio")
        } else if peak < 0.005 {
            Self.log.notice("Mic captured near-silence (peak \(String(format: "%.4f", peak)))")
        }
        return result
    }

    // MARK: - Tap

    /// nonisolated: nie dziedziczy @MainActor z bringUpEngine, wiec tap nie asertuje main-thread.
    private nonisolated static func zainstalujTap(
        node: AVAudioInputNode,
        format: AVAudioFormat?,
        relay: TapRelay,
        generacja: UInt64
    ) throws {
        let blok: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { buffer, _ in
            relay.handle(buffer, generacja: generacja)
        }
        guard VTInstallAudioTap(node, 0, 4096, format, blok) else {
            throw BladKonfiguracji.instalacjaTapu
        }
    }

    private nonisolated func processTap(buffer: AVAudioPCMBuffer, generacja: UInt64) {
        let czasBufora = ProcessInfo.processInfo.systemUptime
        guard let kopia = skopiujBuforAudio(buffer) else { return }
        Task { @MainActor [weak self] in
            guard let self, self.generacjaTapu == generacja else { return }
            self.consume(buffer: kopia, czasBufora: czasBufora)
        }
    }

    private func consume(buffer: AVAudioPCMBuffer, czasBufora: Double) {
        guard state == .recording else { return }
        tapCallbacks += 1

        if sourceFormat?.isEqual(buffer.format) != true {
            converter = nil
            sourceFormat = buffer.format
            Self.log.info(
                "First buffer: sampleRate=\(String(format: "%.0f", buffer.format.sampleRate))Hz channels=\(buffer.format.channelCount) commonFormat=\(buffer.format.commonFormat.rawValue) interleaved=\(buffer.format.isInterleaved) frames=\(buffer.frameLength)"
            )
        }

        let prePeak = peakOf(buffer: buffer)
        onPoziom?(prePeak, czasBufora)
        if tapCallbacks <= 3 {
            Self.log.info("tap #\(self.tapCallbacks): frames=\(buffer.frameLength) prePeak=\(String(format: "%.4f", prePeak))")
        }

        // Fast path: already 16 kHz mono Float32. AVAudioConverter on some channel
        // layouts emits empty output buffers, so skip it when the format already matches.
        if buffer.format.sampleRate == targetFormat.sampleRate,
           buffer.format.channelCount == 1,
           buffer.format.commonFormat == .pcmFormatFloat32,
           let raw = buffer.floatChannelData?[0] {
            ingest(raw, count: Int(buffer.frameLength))
            return
        }

        // Keep one converter for the whole take. Recreating it on every tap yields
        // zero frames after the first buffer.
        if converter == nil {
            converter = AVAudioConverter(from: buffer.format, to: targetFormat)
            if converter == nil {
                Self.log.error("Failed to create AVAudioConverter from \(buffer.format) to \(self.targetFormat)")
                return
            }
        }
        guard let converter else { return }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        let pending = BuforWejscia(buffer)
        var error: NSError?
        let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if let buf = pending.wez() {
                outStatus.pointee = .haveData
                return buf
            }
            // .endOfStream latches the converter; later taps then emit zero frames.
            // Caught on AirPods at 24 kHz -> 16 kHz. .noDataNow keeps it reusable.
            outStatus.pointee = .noDataNow
            return nil
        }
        if status == .error {
            Self.log.error("Converter error: \(error?.localizedDescription ?? "unknown")")
            return
        }
        if tapCallbacks <= 3 {
            Self.log.info("tap #\(self.tapCallbacks): converter outFrames=\(outBuffer.frameLength)")
        }

        guard outBuffer.frameLength > 0,
              let channel = outBuffer.floatChannelData?[0] else { return }

        ingest(channel, count: Int(outBuffer.frameLength))
    }

    private func sprawdzDostarczanieDzwieku() {
        kontrolaDzwieku.rozpocznij(po: .seconds(1)) { [weak self] in
            guard let self, self.state == .recording else { return }
            if self.nadzorDzwieku.brakDanych(czas: ProcessInfo.processInfo.systemUptime) {
                Self.log.error("audio stop reason=noPCM timeoutSeconds=\(NadzorDzwieku.limitBezDanych)")
                _ = self.stop()
                self.onBrakDzwieku?()
            } else {
                self.sprawdzDostarczanieDzwieku()
            }
        }
    }

    private func ingest(_ data: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        nadzorDzwieku.otrzymano(liczbaProbek: count, czas: ProcessInfo.processInfo.systemUptime)
        if !pokazanoOdbiorDzwieku {
            pokazanoOdbiorDzwieku = true
            onPierwszeProbki?()
        }
        let fragment = Array(UnsafeBufferPointer(start: data, count: count))
        samples.append(contentsOf: fragment)
        onProbki?(fragment)
    }

    // MARK: - Helpers

    private func peakOf(buffer: AVAudioPCMBuffer) -> Float {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var peak: Float = 0
        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            if let raw = buffer.floatChannelData?[0] {
                for i in 0..<frames {
                    let a = raw[i] < 0 ? -raw[i] : raw[i]
                    if a > peak { peak = a }
                }
            }
        case .pcmFormatInt16:
            if let raw = buffer.int16ChannelData?[0] {
                var p16: Int16 = 0
                for i in 0..<frames {
                    let v = raw[i] == .min ? .max : (raw[i] < 0 ? -raw[i] : raw[i])
                    if v > p16 { p16 = v }
                }
                peak = Float(p16) / Float(Int16.max)
            }
        case .pcmFormatInt32:
            if let raw = buffer.int32ChannelData?[0] {
                var p32: Int32 = 0
                for i in 0..<frames {
                    let v = raw[i] == .min ? .max : (raw[i] < 0 ? -raw[i] : raw[i])
                    if v > p32 { p32 = v }
                }
                peak = Float(p32) / Float(Int32.max)
            }
        default:
            break
        }
        return peak
    }


}

/// One-shot box so AVAudioConverter's callback does not mutate a captured local (Swift 6).
private final class BuforWejscia: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func wez() -> AVAudioPCMBuffer? {
        defer { buffer = nil }
        return buffer
    }
}

/// Przekaznik tapu: wywolywany z RealtimeMessenger, nie z main.
/// onBuffer jest let, ustawiany raz, bez zamka na watku audio.
private final class TapRelay: @unchecked Sendable {
    let onBuffer: @Sendable (AVAudioPCMBuffer, UInt64) -> Void

    init(_ onBuffer: @escaping @Sendable (AVAudioPCMBuffer, UInt64) -> Void) {
        self.onBuffer = onBuffer
    }

    func handle(_ buffer: AVAudioPCMBuffer, generacja: UInt64) {
        onBuffer(buffer, generacja)
    }
}

/// Wypelniany w init po TapRelay, zanim ruszy silnik. Nie nadpisywany przy sesji.
private final class WlascicielTapRelay: @unchecked Sendable {
    weak var recorder: AudioRecorder?
}
