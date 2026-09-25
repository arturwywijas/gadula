// Pochodzi ze snapshotu vlr-code/dictly (MIT).
import Foundation

/// Abstract STT backend. Today: WhisperKit. Tomorrow: anything we want to swap in.
///
/// Inputs are 16 kHz mono Float32 PCM samples. The implementation is responsible for
/// any chunking required by the underlying model.
protocol Transcriber: Sendable {
    /// Loads model files from disk (downloading if needed) and prepares for inference.
    /// Calling repeatedly is a no-op once a matching model is loaded.
    func prepare(modelID: String, progress: @Sendable @MainActor @escaping (Double) -> Void) async throws

    /// Returns the recognized text for the given samples, or `nil` if speech wasn't detected.
    /// `language` is an ISO 639-1 code. v1 pins `pl` (spec D5); catalog is ticket 12.
    /// `fallbackCount` is the maximum number of decoder retries (with bumped
    /// temperatures) when the first greedy pass produces a degenerate result.
    /// 0 = no retries (fastest), 1 = one safety-net retry, 3 = aggressive.
    func transcribe(samples: [Float], language: String, fallbackCount: Int) async throws -> String?

}

enum TranscriberError: Error, Equatable {
    case modelNotLoaded
    case empty
}
