import Foundation
import os

/// An operation that took too long (see `withTimeout`).
struct AsyncTimeoutError: Error, Equatable {}

/// Runs `operation`, but gives up after `seconds`: throws `AsyncTimeoutError`
/// then (or `CancellationError` once the caller is cancelled) without waiting
/// for the operation, which is cancelled and whose late result is dropped.
/// Unlike a task group, a call that ignores cancellation can't keep the
/// caller waiting.
func withTimeout<T>(
    seconds: Double,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let outcome = TimeoutOutcome<T>()
    let operationTask = Task {
        do { try await outcome.finish(.success(operation())) } catch { outcome.finish(.failure(error)) }
    }
    let timer = Task {
        try? await Task.sleep(for: .seconds(seconds))
        if !Task.isCancelled { outcome.finish(.failure(AsyncTimeoutError())) }
    }
    defer {
        operationTask.cancel()
        timer.cancel()
    }
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { outcome.wait(with: $0) }
    } onCancel: {
        outcome.finish(.failure(CancellationError()))
    }
}

/// The first result of `withTimeout`, whether it comes before or after the
/// caller starts waiting.
private final class TimeoutOutcome<T>: @unchecked Sendable {
    private enum State {
        case pending
        case waiting(CheckedContinuation<T, Error>)
        case finished(Swift.Result<T, Error>)
        case delivered
    }

    private let state = OSAllocatedUnfairLock<State>(initialState: .pending)

    func finish(_ result: Swift.Result<T, Error>) {
        let continuation: CheckedContinuation<T, Error>? = state.withLockUnchecked { state in
            switch state {
            case .pending:
                state = .finished(result)
                return nil
            case let .waiting(continuation):
                state = .delivered
                return continuation
            case .finished, .delivered:
                return nil
            }
        }
        continuation?.resume(with: result)
    }

    func wait(with continuation: CheckedContinuation<T, Error>) {
        let result: Swift.Result<T, Error>? = state.withLockUnchecked { state in
            if case let .finished(result) = state {
                state = .delivered
                return result
            }
            state = .waiting(continuation)
            return nil
        }
        if let result { continuation.resume(with: result) }
    }
}
