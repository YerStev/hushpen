import Darwin
import Foundation

enum ServiceLock {
    nonisolated(unsafe) private static var descriptor: Int32 = -1

    // Held for the lifetime of the service process.
    static func acquire() -> Bool {
        guard (try? Paths.ensureStateDirectory()) != nil else { return false }
        let fd = open(Paths.serviceLock.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return false }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return false
        }
        descriptor = fd
        return true
    }

    static var isHeldElsewhere: Bool {
        let fd = open(Paths.serviceLock.path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        if flock(fd, LOCK_SH | LOCK_NB) == 0 {
            flock(fd, LOCK_UN)
            return false
        }
        return true
    }
}
