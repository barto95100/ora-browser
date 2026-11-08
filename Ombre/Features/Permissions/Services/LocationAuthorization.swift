import CoreLocation
import os

private let logger = Logger(category: "Geolocation")

/// macOS's own permission for Ombre to use Location Services, asked when a
/// site the user allowed wants the position (WebKit never asks macOS: the
/// page waited forever). The positions then come from `GeolocationProvider`.
@MainActor
final class LocationAuthorization: NSObject {
    static let shared = LocationAuthorization()

    enum Outcome: Hashable {
        case authorized
        /// Off for Ombre (or for the whole Mac) in System Settings.
        case denied
        /// macOS showed no answer in time.
        case noAnswer
        /// This WebKit can't be given positions (`GeolocationProvider`).
        case unavailable
    }

    /// How long macOS's prompt may stay open.
    var timeout: Duration = .seconds(120)

    private let manager: LocationManaging
    private var waiting: [(Outcome) -> Void] = []
    private var timeoutTask: Task<Void, Never>?

    init(manager: LocationManaging? = nil) {
        self.manager = manager ?? SystemLocationManager()
        super.init()
        self.manager.onAuthorizationChange = { [weak self] in self?.authorizationChanged() }
    }

    /// Calls back once macOS lets Ombre use the position, or won't.
    func ensureAuthorized(_ completion: @escaping (Outcome) -> Void) {
        let status = manager.authorizationStatus
        logger.info("Location Services status for Ombre: \(Self.name(of: status), privacy: .public)")
        if let outcome = Self.outcome(of: status) {
            completion(outcome)
            return
        }
        waiting.append(completion)
        guard waiting.count == 1 else { return }
        logger.info("Asking macOS for Location Services")
        manager.requestAuthorization()
        timeoutTask = Task { [weak self, timeout] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            logger.error("macOS gave no answer about Location Services")
            self?.finish(.noAnswer)
        }
    }

    private func authorizationChanged() {
        let status = manager.authorizationStatus
        logger.info("Location Services status changed: \(Self.name(of: status), privacy: .public)")
        guard let outcome = Self.outcome(of: status) else { return }
        finish(outcome)
    }

    private func finish(_ outcome: Outcome) {
        timeoutTask?.cancel()
        timeoutTask = nil
        let callbacks = waiting
        waiting = []
        callbacks.forEach { $0(outcome) }
    }

    /// The answer to a site asking for the position, once the user decided:
    /// when allowed, macOS must let Ombre use Location Services too.
    nonisolated static func askingMacOS(
        then decisionHandler: @escaping (BrowserPermissionDecision) -> Void
    ) -> (BrowserPermissionDecision) -> Void {
        { decision in
            // WebKit and the permission banner call back on the main thread.
            MainActor.assumeIsolated {
                shared.answer(decision, then: decisionHandler)
            }
        }
    }

    /// The site's answer: a refusal as it is, an approval once macOS agrees.
    func answer(
        _ decision: BrowserPermissionDecision,
        then decisionHandler: @escaping (BrowserPermissionDecision) -> Void
    ) {
        guard decision == .grant else {
            decisionHandler(decision)
            return
        }
        guard isProviderAvailable() else {
            logger.error("Position for the site: refused, WebKit can't be given positions")
            tell(.unavailable)
            decisionHandler(.deny)
            return
        }
        ensureAuthorized { [self] outcome in
            let result = outcome == .authorized ? "allowed" : "refused"
            logger.info("Position for the site: \(result, privacy: .public)")
            tell(outcome)
            decisionHandler(outcome == .authorized ? .grant : .deny)
        }
    }

    /// Core Location refused a position after all (Location Services
    /// turned off meanwhile): said once, like a refusal.
    func positionRefused() {
        tell(.denied)
    }

    /// Tells the user why a site gets no position, once per launch for each
    /// reason (a map page loads it again and again).
    private func tell(_ outcome: Outcome) {
        guard outcome != .authorized, !told.contains(outcome) else { return }
        told.insert(outcome)
        onRefusal(outcome)
    }

    private var told: Set<Outcome> = []
    /// Whether WebKit can be given positions (replaced in tests).
    var isProviderAvailable: () -> Bool = { GeolocationProvider.shared.isAvailable }
    /// Shows the reason (replaced in tests).
    var onRefusal: (Outcome) -> Void = LocationAuthorization.show

    private static func show(_ outcome: Outcome) {
        let message = switch outcome {
        case .authorized: ""
        case .denied:
            "Location Services are off for Ombre. Turn them on in System Settings › "
                + "Privacy & Security › Location Services."
        case .noAnswer:
            "macOS didn't answer about Location Services. Try again, or check System Settings › Privacy & Security."
        case .unavailable:
            "This version of macOS doesn't let Ombre give sites your location."
        }
        ToastManager.shared.show(message, type: .error, duration: 10)
    }

    /// Nil while macOS hasn't decided.
    static func outcome(of status: CLAuthorizationStatus) -> Outcome? {
        switch status {
        case .authorizedAlways: .authorized
        case .denied, .restricted: .denied
        case .notDetermined: nil
        @unknown default: .denied
        }
    }

    private static func name(of status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedAlways: "authorized"
        case .denied: "denied"
        case .restricted: "restricted"
        case .notDetermined: "not determined"
        @unknown default: "unknown (\(status.rawValue))"
        }
    }
}

/// Core Location's authorization, replaced in tests.
@MainActor
protocol LocationManaging: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var onAuthorizationChange: (() -> Void)? { get set }
    func requestAuthorization()
}

@MainActor
final class SystemLocationManager: NSObject, LocationManaging, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onAuthorizationChange: (() -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    nonisolated func locationManagerDidChangeAuthorization(_: CLLocationManager) {
        Task { @MainActor in self.onAuthorizationChange?() }
    }
}
