import CoreLocation
import Darwin
import os
import WebKit

private let logger = Logger(category: "Geolocation")

/// The position WebKit gives pages (`navigator.geolocation`). On macOS,
/// WebKit has no source of its own: without a provider set by the app, a
/// page allowed to have the position never gets one (a map waits, Google
/// Maps says it can't find it). Safari sets one through WebKit's C
/// functions (`WKGeolocationManagerSetProvider`): Ombre does the same, the
/// third tolerated private call (see CLAUDE.md), invisible to pages.
///
/// The functions are looked up at run time (`dlsym`), never linked: a
/// WebKit without them only leaves the position off. Sites are then
/// refused, and the user told once (`LocationAuthorization`), without a crash;
/// `GeolocationProviderTests` fails then, to tell.
@MainActor
final class GeolocationProvider {
    static let shared = GeolocationProvider(source: CoreLocationSource(), webKit: WebKitGeolocation.load())

    /// Whether this WebKit still has the functions.
    var isAvailable: Bool {
        webKit != nil
    }

    private let source: PositionSource
    private let webKit: GeolocationWebKit?
    /// WebKit's managers (one per process pool) whose pages want positions,
    /// with how many sites want them: WebKit starts and stops once per site.
    private var updating: [UnsafeRawPointer: Int] = [:]
    /// The process pools already given the provider.
    private let installed = NSHashTable<NSObject>.weakObjects()
    private var lastPosition: CLLocation?
    private var noPositionTask: Task<Void, Never>?
    /// How long Core Location may take to find a first position.
    var positionTimeout: Duration = .seconds(30)
    /// Tells the user (replaced in tests).
    var onNoPosition: @MainActor () -> Void = GeolocationProvider.tellNoPosition
    var onDenied: @MainActor () -> Void = { LocationAuthorization.shared.positionRefused() }

    init(source: PositionSource, webKit: GeolocationWebKit?) {
        self.source = source
        self.webKit = webKit
        source.onPosition = { [weak self] in self?.found($0) }
        source.onError = { [weak self] in self?.failed($0) }
    }

    /// Gives `pool`'s pages their positions from here (once per pool).
    func install(on pool: NSObject) {
        guard let webKit, !installed.contains(pool) else { return }
        installed.add(pool)
        webKit.setProvider(on: pool, client: Unmanaged.passUnretained(self).toOpaque())
    }

    // MARK: - WebKit's calls (on the main thread)

    /// A page of `manager`'s pool watches or asks for the position.
    func startUpdating(_ manager: UnsafeRawPointer) {
        let first = updating.isEmpty
        updating[manager, default: 0] += 1
        let sites = updating.values.reduce(0, +)
        logger.notice("WebKit wants the position (\(sites, privacy: .public) sites)")
        // A recent position at once, like Core Location's own cache.
        var answered = false
        if let lastPosition, -lastPosition.timestamp.timeIntervalSinceNow < 60 {
            webKit?.didChangePosition(manager, lastPosition)
            answered = true
        }
        guard first else { return }
        source.start()
        if !answered { waitForPosition() }
    }

    func stopUpdating(_ manager: UnsafeRawPointer) {
        guard let count = updating[manager] else { return }
        updating[manager] = count > 1 ? count - 1 : nil
        guard updating.isEmpty else { return }
        logger.notice("WebKit no longer wants the position")
        noPositionTask?.cancel()
        noPositionTask = nil
        source.stop()
    }

    func setHighAccuracy(_ enabled: Bool) {
        source.setHighAccuracy(enabled)
    }

    // MARK: - Core Location's answers

    private func found(_ location: CLLocation) {
        // An invalid fix (no accuracy): Core Location sends a real one later.
        guard location.horizontalAccuracy >= 0 else { return }
        noPositionTask?.cancel()
        noPositionTask = nil
        if lastPosition == nil { logger.notice("Core Location found the position") }
        lastPosition = location
        for manager in updating.keys {
            webKit?.didChangePosition(manager, location)
        }
    }

    private func failed(_ error: Error) {
        let code = (error as NSError).code
        logger.error("Core Location error \(code, privacy: .public)")
        // Still looking: Core Location keeps trying (see `waitForPosition`).
        guard code != CLError.locationUnknown.rawValue else { return }
        if code == CLError.denied.rawValue {
            onDenied()
            giveUp(message: "Location Services are off for Ombre.")
        } else {
            onNoPosition()
            giveUp(message: "macOS couldn't find the location.")
        }
    }

    /// Nothing found in time: the pages and the user are told.
    private func waitForPosition() {
        noPositionTask?.cancel()
        noPositionTask = Task { [weak self, positionTimeout] in
            try? await Task.sleep(for: positionTimeout)
            guard !Task.isCancelled, let self else { return }
            logger.error("Core Location found no position in time")
            onNoPosition()
            giveUp(message: "macOS couldn't find the location.")
        }
    }

    private func giveUp(message: String) {
        noPositionTask?.cancel()
        noPositionTask = nil
        for manager in updating.keys {
            webKit?.didFail(manager, message: message)
        }
    }

    private var toldNoPosition = false

    private static func tellNoPosition() {
        let provider = GeolocationProvider.shared
        guard !provider.toldNoPosition else { return }
        provider.toldNoPosition = true
        ToastManager.shared.show(
            "macOS couldn't find your location. Check that Wi-Fi is on, then try again.",
            type: .error,
            duration: 10
        )
    }
}

/// Where positions come from: Core Location (replaced in tests).
@MainActor
protocol PositionSource: AnyObject {
    var onPosition: ((CLLocation) -> Void)? { get set }
    var onError: ((Error) -> Void)? { get set }
    func start()
    func stop()
    func setHighAccuracy(_ enabled: Bool)
}

@MainActor
final class CoreLocationSource: NSObject, PositionSource, CLLocationManagerDelegate {
    /// Made when a site first wants the position, kept (on the main thread).
    private lazy var manager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        return manager
    }()

    var onPosition: ((CLLocation) -> Void)?
    var onError: ((Error) -> Void)?

    func start() {
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    func setHighAccuracy(_ enabled: Bool) {
        manager.desiredAccuracy = enabled ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters
    }

    nonisolated func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.onPosition?(location) }
    }

    nonisolated func locationManager(_: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.onError?(error) }
    }
}

/// The process pool of `configuration` (`WKProcessPool`, deprecated as a
/// type but still the object WebKit's C functions take), read by its key.
@MainActor
func processPool(of configuration: WKWebViewConfiguration) -> NSObject? {
    configuration.value(forKey: "processPool") as? NSObject
}

/// What the provider tells WebKit (replaced in tests).
@MainActor
protocol GeolocationWebKit {
    func setProvider(on pool: NSObject, client: UnsafeRawPointer)
    func didChangePosition(_ manager: UnsafeRawPointer, _ location: CLLocation)
    func didFail(_ manager: UnsafeRawPointer, message: String)
}

/// WebKit's C geolocation functions, found at run time (nil if one is
/// missing). On Cocoa, a `WKContextRef` is the `WKProcessPool` itself.
struct WebKitGeolocation: GeolocationWebKit {
    static let symbols = [
        "WKContextGetGeolocationManager",
        "WKGeolocationManagerSetProvider",
        "WKGeolocationManagerProviderDidChangePosition",
        "WKGeolocationManagerProviderDidFailToDeterminePositionWithErrorMessage",
        "WKGeolocationPositionCreate_b",
        "WKStringCreateWithUTF8CString",
        "WKRelease"
    ]

    private typealias GetManager = @convention(c) (UnsafeRawPointer) -> UnsafeRawPointer?
    private typealias SetProvider = @convention(c) (UnsafeRawPointer, UnsafeRawPointer) -> Void
    private typealias DidChange = @convention(c) (UnsafeRawPointer, UnsafeRawPointer) -> Void
    private typealias DidFail = @convention(c) (UnsafeRawPointer, UnsafeRawPointer) -> Void
    private typealias CreatePosition = @convention(c) (
        Double,
        Double,
        Double,
        Double,
        Bool,
        Double,
        Bool,
        Double,
        Bool,
        Double,
        Bool,
        Double
    ) -> UnsafeRawPointer?
    private typealias CreateString = @convention(c) (UnsafePointer<CChar>) -> UnsafeRawPointer?
    private typealias Release = @convention(c) (UnsafeRawPointer) -> Void

    private let getManager: GetManager
    private let setProviderFunction: SetProvider
    private let didChange: DidChange
    private let didFailFunction: DidFail
    private let createPosition: CreatePosition
    private let createString: CreateString
    private let release: Release

    /// Looks the functions up in the WebKit already loaded.
    static func load() -> WebKitGeolocation? {
        // RTLD_DEFAULT: every image loaded.
        let everywhere = UnsafeMutableRawPointer(bitPattern: -2)
        var found: [String: UnsafeMutableRawPointer] = [:]
        for name in symbols {
            guard let pointer = dlsym(everywhere, name) else {
                logger.error("WebKit has no \(name, privacy: .public): no position for pages")
                return nil
            }
            found[name] = pointer
        }
        func function<T>(_ name: String, as _: T.Type) -> T {
            unsafeBitCast(found[name], to: T.self)
        }
        return WebKitGeolocation(
            getManager: function("WKContextGetGeolocationManager", as: GetManager.self),
            setProviderFunction: function("WKGeolocationManagerSetProvider", as: SetProvider.self),
            didChange: function("WKGeolocationManagerProviderDidChangePosition", as: DidChange.self),
            didFailFunction: function(
                "WKGeolocationManagerProviderDidFailToDeterminePositionWithErrorMessage",
                as: DidFail.self
            ),
            createPosition: function("WKGeolocationPositionCreate_b", as: CreatePosition.self),
            createString: function("WKStringCreateWithUTF8CString", as: CreateString.self),
            release: function("WKRelease", as: Release.self)
        )
    }

    /// `WKGeolocationProviderV1`: version, client, then the three callbacks
    /// (WebKit copies it). Its callbacks reach the provider through `client`.
    func setProvider(on pool: NSObject, client: UnsafeRawPointer) {
        guard let manager = getManager(Unmanaged.passUnretained(pool).toOpaque()) else { return }
        let start: @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?) -> Void = { manager, client in
            guard let manager, let client else { return }
            MainActor.assumeIsolated {
                Unmanaged<GeolocationProvider>.fromOpaque(client).takeUnretainedValue().startUpdating(manager)
            }
        }
        let stop: @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?) -> Void = { manager, client in
            guard let manager, let client else { return }
            MainActor.assumeIsolated {
                Unmanaged<GeolocationProvider>.fromOpaque(client).takeUnretainedValue().stopUpdating(manager)
            }
        }
        let highAccuracy: @convention(c) (UnsafeRawPointer?, Bool, UnsafeRawPointer?) -> Void = { _, enabled, client in
            guard let client else { return }
            MainActor.assumeIsolated {
                Unmanaged<GeolocationProvider>.fromOpaque(client).takeUnretainedValue().setHighAccuracy(enabled)
            }
        }
        var provider = ProviderV1(
            version: 1,
            clientInfo: client,
            startUpdating: start,
            stopUpdating: stop,
            setEnableHighAccuracy: highAccuracy
        )
        withUnsafePointer(to: &provider) { setProviderFunction(manager, UnsafeRawPointer($0)) }
        logger.notice("Position provider set for a process pool")
    }

    func didChangePosition(_ manager: UnsafeRawPointer, _ location: CLLocation) {
        let hasAltitude = location.verticalAccuracy >= 0
        let hasHeading = location.course >= 0
        let hasSpeed = location.speed >= 0
        guard let position = createPosition(
            location.timestamp.timeIntervalSince1970,
            location.coordinate.latitude,
            location.coordinate.longitude,
            location.horizontalAccuracy,
            hasAltitude, location.altitude,
            hasAltitude, location.verticalAccuracy,
            hasHeading, location.course,
            hasSpeed, location.speed
        ) else { return }
        didChange(manager, position)
        release(position)
    }

    func didFail(_ manager: UnsafeRawPointer, message: String) {
        guard let text = message.withCString({ createString($0) }) else { return }
        didFailFunction(manager, text)
        release(text)
    }
}

/// WebKit's `WKGeolocationProviderV1`, field for field (its layout is
/// checked by `GeolocationProviderTests`). WebKit calls back on the main thread.
struct ProviderV1 {
    var version: Int32
    var clientInfo: UnsafeRawPointer?
    var startUpdating: @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?) -> Void
    var stopUpdating: @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?) -> Void
    var setEnableHighAccuracy: @convention(c) (UnsafeRawPointer?, Bool, UnsafeRawPointer?) -> Void
}
