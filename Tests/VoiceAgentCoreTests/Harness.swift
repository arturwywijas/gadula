import Foundation

enum TestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message):
            return message
        }
    }
}

func expectEqual<T: Equatable>(
    _ got: T,
    _ expected: T,
    file: String = #fileID,
    line: Int = #line
) throws {
    if got != expected {
        throw TestFailure.failed("\(file):\(line): expected \(expected), got \(got)")
    }
}

@MainActor
func runTests(_ cases: [(String, @MainActor () async throws -> Void)]) async {
    let all = TestyNadzoruDzwieku.przypadki() + TestyNormalizacjiNagrania.przypadki() + TestyStabilnosciSesji.przypadki() + TestyKonfiguracjiAudio.przypadki() + TestyStyluWskaznika.przypadki() + TestyPrzygotowaniaModelu.przypadki() + cases + TestySkrotuWyzwalacza.przypadki() + TestyPigulkiNagrywania.przypadki()
    var failed = 0
    for (name, body) in all {
        do {
            try await body()
            print("PASS \(name)")
        } catch {
            failed += 1
            print("FAIL \(name): \(error)")
        }
    }
    print("\(all.count - failed) pass / \(failed) fail")
    if failed > 0 {
        exit(1)
    }
}
