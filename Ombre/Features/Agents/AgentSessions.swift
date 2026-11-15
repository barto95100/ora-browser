import AppKit
import Foundation

/// An app driving Ombre: the one the user knows (Terminal, an editor…), not
/// the `osascript` it ran.
struct AgentSender: Equatable, Sendable {
    /// Its bundle identifier (or path): one session per app.
    let key: String
    let name: String

    /// A sender whose app wasn't found: asked each time.
    static let unknownKey = "unknown"
}

/// Who sent an Apple Event: the first regular app up the sender's parents
/// (`osascript` ← zsh ← … ← Terminal), as macOS names it in its own
/// Automation question.
enum AgentSenderLookup {
    /// Parents looked through at most.
    static let maxDepth = 12

    @MainActor
    static func sender(pid: pid_t) -> AgentSender {
        sender(pid: pid, app: regularApp(pid:), parent: parent(of:))
    }

    /// For the tests: apps and parents of their own.
    static func sender(pid: pid_t, app: (pid_t) -> AgentSender?, parent: (pid_t) -> pid_t?) -> AgentSender {
        var current: pid_t? = pid
        var depth = 0
        while let process = current, process > 1, depth < maxDepth {
            if let found = app(process) { return found }
            current = parent(process)
            depth += 1
        }
        // Not found (a process macOS doesn't show): one session for them all.
        return AgentSender(key: AgentSender.unknownKey, name: String(localized: "An app"))
    }

    /// The app of `pid` if it is a regular one (in the Dock).
    @MainActor
    private static func regularApp(pid: pid_t) -> AgentSender? {
        guard let running = NSRunningApplication(processIdentifier: pid), running.activationPolicy == .regular
        else { return nil }
        let name = running.localizedName ?? running.bundleURL?.deletingPathExtension().lastPathComponent
        return AgentSender(
            key: running.bundleIdentifier ?? running.bundleURL?.path ?? "pid \(pid)", // not shown
            name: name ?? String(localized: "An app")
        )
    }

    /// The parent of `pid` (`sysctl`), none for launchd or when unknown.
    nonisolated static func parent(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let parent = info.kp_eproc.e_ppid
        return parent > 1 ? parent : nil
    }
}

/// The apps the user allowed (or denied) for this session: until Ombre quits,
/// or an hour without a command from that app.
struct AgentSessions {
    enum Decision: Equatable {
        case allowed
        case denied
        /// A new session: ask the user.
        case ask
    }

    static let idleLimit: TimeInterval = 60 * 60

    private struct Session {
        var isAllowed: Bool
        var lastCommand: Date
    }

    private var sessions: [String: Session] = [:]

    /// What to do with a command of `app` now; a command keeps its session
    /// alive.
    mutating func decision(for app: String, now: Date = Date()) -> Decision {
        guard let session = sessions[app] else { return .ask }
        guard now.timeIntervalSince(session.lastCommand) <= Self.idleLimit else {
            sessions[app] = nil
            return .ask
        }
        sessions[app]?.lastCommand = now
        return session.isAllowed ? .allowed : .denied
    }

    /// The user's answer for `app`, for its session.
    mutating func record(_ app: String, isAllowed: Bool, now: Date = Date()) {
        sessions[app] = Session(isAllowed: isAllowed, lastCommand: now)
    }

    /// Stop Agent Control: every app asks again.
    mutating func endAll() {
        sessions = [:]
    }
}
