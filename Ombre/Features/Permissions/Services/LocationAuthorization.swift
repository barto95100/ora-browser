import CoreLocation
import os

private let logger = Logger(category: "Geolocation")

/// macOS's own permission for Ombre to use Location Services, asked when a
/// site the user allowed wants the position. WebKit reads the position from
/// Core Location but never asks macOS: without this, the page waited forever
/// (macOS never showed its prompt, the status stayed "not determined").
@MainActor
final class LocationAuthorization: NSObject {
    static let shared = LocationAuthorization()

    enum Outcome: Hashable {
        case authorized
        /// Off for Ombre (or for the whole Mac) in System Settings.
        case denied
        /// macOS showed no answer in time.
        case noAnswer
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

    /// Whether Core Location finds the position the site will get (WebKit
    /// reads it on its own and tells the page, not Ombre): logged, and the
    /// user told when it can't, so a map showing nothing has an explanation.
    func checkPosition() {
        guard !isCheckingPosition else { return }
        isCheckingPosition = true
        let started = ContinuousClock.now
        var answered = false
        let finish: (Error?) -> Void = { [weak self] error in
            guard !answered else { return }
            answered = true
            self?.isCheckingPosition = false
            let elapsed = ContinuousClock.now - started
            if let error {
                let code = (error as NSError).code
                logger.error("No position: error \(code, privacy: .public), \(elapsed, privacy: .public)")
                if code == CLError.denied.rawValue {
                    self?.tell(.denied)
                } else {
                    self?.onNoPosition()
                }
            } else {
                logger.info("Core Location found the position after \(elapsed, privacy: .public)")
            }
        }
        manager.requestOneLocation(finish)
        Task { [positionTimeout] in
            try? await Task.sleep(for: positionTimeout)
            finish(CLError(.locationUnknown))
        }
    }

    private var isCheckingPosition = false
    /// Tells the user (replaced in tests).
    var onNoPosition: () -> Void = LocationAuthorization.tellNoPosition
    /// How long Core Location may take to find the position.
    var positionTimeout: Duration = .seconds(30)

    static func tellNoPosition() {
        ToastManager.shared.show(
            "macOS couldn't find your location. Check that Wi-Fi is on, then try again.",
            type: .error,
            duration: 10
        )
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
        ensureAuthorized { [self] outcome in
            let result = outcome == .authorized ? "allowed" : "refused"
            logger.info("Position for the site: \(result, privacy: .public)")
            tell(outcome)
            decisionHandler(outcome == .authorized ? .grant : .deny)
            if outcome == .authorized { checkPosition() }
        }
    }

    /// Tells the user why a site gets no position, once per launch for each
    /// reason (a map page loads it again and again).
    private func tell(_ outcome: Outcome) {
        guard outcome != .authorized, !told.contains(outcome) else { return }
        told.insert(outcome)
        onRefusal(outcome)
    }

    private var told: Set<Outcome> = []
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
    /// Asks Core Location for one position; nil error once it has one.
    func requestOneLocation(_ completion: @escaping (Error?) -> Void)
}

@MainActor
final class SystemLocationManager: NSObject, LocationManaging, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onAuthorizationChange: (() -> Void)?
    private var locationRequests: [(Error?) -> Void] = []

    override init() {
        super.init()
        manager.delegate = self
        // Only to tell whether a position comes (WebKit gets its own).
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func requestOneLocation(_ completion: @escaping (Error?) -> Void) {
        locationRequests.append(completion)
        manager.requestLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_: CLLocationManager) {
        Task { @MainActor in self.onAuthorizationChange?() }
    }

    nonisolated func locationManager(_: CLLocationManager, didUpdateLocations _: [CLLocation]) {
        Task { @MainActor in self.finishLocationRequests(nil) }
    }

    nonisolated func locationManager(_: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finishLocationRequests(error) }
    }

    private func finishLocationRequests(_ error: Error?) {
        let requests = locationRequests
        locationRequests = []
        requests.forEach { $0(error) }
    }
}
