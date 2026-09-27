// autor: Codex, gadula-stabilnosc-20260927
import Foundation
import Darwin

/// Blokada systemowa znika także po awarii procesu; plik nie jest znacznikiem PID.
final class BlokadaInstancji {
    private let deskryptor: Int32

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        deskryptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard deskryptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
    func przejmij() -> Bool { flock(deskryptor, LOCK_EX | LOCK_NB) == 0 }
    deinit { close(deskryptor) }
}
