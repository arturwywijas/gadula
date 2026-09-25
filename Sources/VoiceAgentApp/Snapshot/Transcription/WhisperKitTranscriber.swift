// Pochodzi ze snapshotu vlr-code/dictly (MIT).
import Foundation
import WhisperKit
import VoiceAgentCore

/// WhisperKit-backed implementation of `Transcriber`.
///
/// Models are downloaded from `argmaxinc/whisperkit-coreml` and cached under
/// `~/Documents/huggingface/...`. Weights are not in the repo or the app bundle (spec D1).
/// Catalog and picker are tickets 04 and 12.
///
/// The whole class opts out of the project's MainActor default isolation: WhisperKit's
/// async API is intentionally non-isolated and we don't want every property access to
/// require a MainActor hop. Cross-thread access to the cached pipe is mediated by a
/// dedicated serial queue.
nonisolated
final class WhisperKitTranscriber: Transcriber, @unchecked Sendable {

    /// Until ticket 12, the default variant is spec D5.
    static let defaultModelID = "large-v3-v20240930_626MB"

    private static let log = AppLogger(category: "WhisperKit")

    private var pipe: WhisperKit?
    private var loadedID: String?
    private let queue = DispatchQueue(label: "com.arturwywijas.gadula.whisperkit.state")

    func prepare(modelID: String, progress: @Sendable @MainActor @escaping (Double) -> Void) async throws {
        let alreadyLoaded = queue.sync { loadedID == modelID && pipe != nil }
        if alreadyLoaded {
            await MainActor.run { progress(1.0) }
            return
        }

        guard let modelFolder = Self.folderNaDysku(dla: modelID) else {
            throw TranscriberError.modelNotLoaded
        }
        Self.log.info("Loading local model \(modelID) from \(modelFolder)")
        await MainActor.run { progress(0.0) }

        let config = WhisperKitConfig(
            model: modelID,
            modelFolder: modelFolder,
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: false
        )

        let kit = try await WhisperKit(config)
        queue.sync {
            self.pipe = kit
            self.loadedID = modelID
        }

        let warmStart = CFAbsoluteTimeGetCurrent()
        var warmOpts = DecodingOptions()
        warmOpts.task = .transcribe
        warmOpts.language = "pl"
        warmOpts.detectLanguage = false
        warmOpts.skipSpecialTokens = true
        warmOpts.withoutTimestamps = true
        warmOpts.temperatureFallbackCount = 0
        warmOpts.sampleLength = 1
        let dummy = [Float](repeating: 0, count: 16_000)
        _ = try? await kit.transcribe(audioArray: dummy, decodeOptions: warmOpts)
        Self.log.info("WhisperKit warmup: \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - warmStart))s")

        await MainActor.run { progress(1.0) }
    }

    func transcribe(samples: [Float], language: String, fallbackCount: Int) async throws -> String? {
        let kit = queue.sync { pipe }
        guard let kit else { throw TranscriberError.modelNotLoaded }
        if samples.isEmpty { throw TranscriberError.empty }

        let przygotowane = NormalizacjaNagrania.przygotuj(samples)
        Self.log.notice("FN19 normalization peakBefore=\(przygotowane.przed.szczyt) rmsBefore=\(przygotowane.przed.rms) peakAfter=\(przygotowane.po.szczyt) rmsAfter=\(przygotowane.po.rms) robustRMS=\(przygotowane.odpornyRMS) robustPeak=\(przygotowane.odpornySzczyt) gain=\(przygotowane.wzmocnienie) limitedSamples=\(przygotowane.ograniczoneProbki) reason=\(przygotowane.powod.rawValue)")
        var options = DecodingOptions()
        options.task = .transcribe
        options.language = language
        options.detectLanguage = false
        options.skipSpecialTokens = true
        options.withoutTimestamps = true
        options.temperatureFallbackCount = max(0, fallbackCount)
        // Pozostawiamy domyślne 224 tokeny biblioteki zamiast limitu 128.
        let okno = kit.featureExtractor.windowSamples ?? Constants.defaultWindowSamples
        options.chunkingStrategy = ParametryRozpoznawania.uzyjVAD(liczbaProbek: przygotowane.pcm.count, okno: okno) ? .vad : nil
        Self.log.notice("FN19 decoding sampleLength=\(options.sampleLength) fallbackCount=\(options.temperatureFallbackCount) vad=\(options.chunkingStrategy == .vad) windowSamples=\(okno)")

        let t0 = CFAbsoluteTimeGetCurrent()
        let results = try await kit.transcribe(audioArray: przygotowane.pcm, decodeOptions: options)
        let elapsed = CFAbsoluteTimeGetCurrent() - t0
        let audioSec = Double(samples.count) / 16_000.0
        let rtf = audioSec > 0 ? elapsed / audioSec : 0
        Self.log.info("kit.transcribe: \(String(format: "%.2f", elapsed))s for \(String(format: "%.2f", audioSec))s audio (RTF=\(String(format: "%.2f", rtf)))")

        let text = results.map { $0.text }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Ticket 12 pobiera model. Tu tylko lokalny cache, bez sieci.
    static func folderNaDysku(dla modelID: String) -> String? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let korzenie = [
            docs?.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Documents/huggingface/models/argmaxinc/whisperkit-coreml"),
        ].compactMap { $0 }
        let nazwy = ["openai_whisper-\(modelID)", modelID]
        for korzen in korzenie {
            for nazwa in nazwy {
                let folder = korzen.appendingPathComponent(nazwa)
                if FileManager.default.fileExists(atPath: folder.path) {
                    return folder.path
                }
            }
        }
        return nil
    }
}
