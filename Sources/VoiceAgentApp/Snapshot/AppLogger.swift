// Pochodzi ze snapshotu vlr-code/dictly (MIT).
import Foundation
import OSLog

// Snapshot dictly: OSLog only. MetricKit, crash reporter and rotating local log removed (R8).
nonisolated
enum DiagnosticsConstants {
    static let subsystem = "com.arturwywijas.gadula"
}

nonisolated
struct AppLogger: Sendable {
    private let osLogger: Logger

    init(category: String) {
        self.osLogger = Logger(subsystem: DiagnosticsConstants.subsystem, category: category)
    }

    func info(_ message: @autoclosure () -> String) {
        let text = message()
        osLogger.info("\(text, privacy: .public)")
    }

    func notice(_ message: @autoclosure () -> String) {
        let text = message()
        osLogger.notice("\(text, privacy: .public)")
    }

    func error(_ message: @autoclosure () -> String) {
        let text = message()
        osLogger.error("\(text, privacy: .public)")
    }

}
