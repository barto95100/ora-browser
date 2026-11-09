import Foundation
import os

/// SafariConverterLib prints every rule it can't convert (thousands for a
/// big list, all expected: Safari has no equivalent) with `print`, only in
/// Debug builds, with no setting to turn it off. While a list compiles, the
/// standard output goes nowhere (Ombre's own logs go through `os.Logger`,
/// on another path); Ombre says how many rules were skipped once per list.
enum ConverterOutput {
    private struct State {
        var depth = 0
        var savedOutput: Int32 = -1
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    static func silenced<T>(_ body: () throws -> T) rethrows -> T {
        #if DEBUG
            begin()
            defer { end() }
        #endif
        return try body()
    }

    /// Compilations can overlap: the first one silences, the last one
    /// gives the output back.
    private static func begin() {
        state.withLock { state in
            state.depth += 1
            guard state.depth == 1 else { return }
            fflush(stdout)
            let null = open("/dev/null", O_WRONLY)
            guard null >= 0 else { return }
            defer { close(null) }
            // Never silenced for good: only with a way back.
            let saved = fcntl(STDOUT_FILENO, F_DUPFD_CLOEXEC, 0)
            guard saved >= 0 else { return }
            state.savedOutput = saved
            dup2(null, STDOUT_FILENO)
        }
    }

    private static func end() {
        state.withLock { state in
            state.depth -= 1
            guard state.depth == 0, state.savedOutput >= 0 else { return }
            fflush(stdout)
            dup2(state.savedOutput, STDOUT_FILENO)
            close(state.savedOutput)
            state.savedOutput = -1
        }
    }
}
