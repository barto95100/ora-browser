import CoreLocation
@testable import Ombre
import Testing
import WebKit

/// The position WebKit gives pages, from Core Location through WebKit's C
/// functions (the third tolerated private call, see CLAUDE.md).
@MainActor
struct GeolocationProviderTests {
    private final class FakeSource: PositionSource {
        var onPosition: ((CLLocation) -> Void)?
        var onError: ((Error) -> Void)?
        var isRunning = false
        var highAccuracy = false

        func start() {
            isRunning = true
        }

        func stop() {
            isRunning = false
        }

        func setHighAccuracy(_ enabled: Bool) {
            highAccuracy = enabled
        }
    }

    private final class FakeWebKit: GeolocationWebKit {
        var pools = 0
        var positions: [(UnsafeRawPointer, CLLocation)] = []
        var failures: [UnsafeRawPointer] = []

        func setProvider(on _: NSObject, client _: UnsafeRawPointer) {
            pools += 1
        }

        func didChangePosition(_ manager: UnsafeRawPointer, _ location: CLLocation) {
            positions.append((manager, location))
        }

        func didFail(_ manager: UnsafeRawPointer, message _: String) {
            failures.append(manager)
        }
    }

    /// Stand-ins for WebKit's managers (only compared).
    private static let first = UnsafeRawPointer(UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1))
    private static let second = UnsafeRawPointer(UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1))
    private static let paris = CLLocation(latitude: 48.8566, longitude: 2.3522)

    /// Fails when a WebKit drops one of the functions: pages would then get
    /// no position (refused, the user told once).
    @Test func webKitStillHasItsGeolocationFunctions() {
        #expect(WebKitGeolocation.load() != nil)
        #expect(GeolocationProvider.shared.isAvailable)
    }

    /// Laid out like WebKit's C struct: an int, then four pointers.
    @Test func theProviderIsLaidOutLikeWebKitsStruct() {
        #expect(MemoryLayout<ProviderV1>.offset(of: \.version) == 0)
        #expect(MemoryLayout<ProviderV1>.offset(of: \.clientInfo) == 8)
        #expect(MemoryLayout<ProviderV1>.offset(of: \.startUpdating) == 16)
        #expect(MemoryLayout<ProviderV1>.offset(of: \.stopUpdating) == 24)
        #expect(MemoryLayout<ProviderV1>.offset(of: \.setEnableHighAccuracy) == 32)
        #expect(MemoryLayout<ProviderV1>.size == 40)
    }

    /// The real functions, on a real process pool: set once per pool, no
    /// crash. (The provider goes at the end: no page uses this pool.)
    @Test func theProviderIsSetOnAProcessPool() throws {
        let webKit = try #require(WebKitGeolocation.load())
        let provider = GeolocationProvider(source: FakeSource(), webKit: webKit)
        let pool = try #require(processPool(of: WKWebViewConfiguration()))
        provider.install(on: pool)
        provider.install(on: pool)
        withExtendedLifetime(provider) {}
    }

    @Test func eachPoolIsGivenTheProviderOnce() throws {
        let webKit = FakeWebKit()
        let provider = GeolocationProvider(source: FakeSource(), webKit: webKit)
        let pool = try #require(processPool(of: WKWebViewConfiguration()))
        provider.install(on: pool)
        provider.install(on: pool)
        try provider.install(on: #require(processPool(of: WKWebViewConfiguration())))
        #expect(webKit.pools == 2)
    }

    /// Core Location runs only while a page wants the position, and each
    /// position goes to every pool that wants it.
    @Test func positionsGoToThePagesThatWantThem() {
        let source = FakeSource()
        let webKit = FakeWebKit()
        let provider = GeolocationProvider(source: source, webKit: webKit)
        provider.startUpdating(Self.first)
        provider.startUpdating(Self.second)
        #expect(source.isRunning)
        source.onPosition?(Self.paris)
        #expect(webKit.positions.map(\.0).count == 2)
        #expect(webKit.positions.first?.1.coordinate.latitude == 48.8566)

        provider.stopUpdating(Self.first)
        #expect(source.isRunning)
        provider.stopUpdating(Self.second)
        #expect(!source.isRunning)

        // A page asking again gets the recent position at once.
        provider.startUpdating(Self.first)
        #expect(webKit.positions.count == 3)
        provider.setHighAccuracy(true)
        #expect(source.highAccuracy)
    }

    /// WebKit starts and stops once per site, on the same manager: one site
    /// stopping leaves the other its positions.
    @Test func oneSiteStoppingLeavesTheOther() {
        let source = FakeSource()
        let webKit = FakeWebKit()
        let provider = GeolocationProvider(source: source, webKit: webKit)
        provider.startUpdating(Self.first)
        provider.startUpdating(Self.first)
        provider.stopUpdating(Self.first)
        #expect(source.isRunning)
        source.onPosition?(Self.paris)
        #expect(webKit.positions.count == 1)
        provider.stopUpdating(Self.first)
        #expect(!source.isRunning)
        // A stop too many changes nothing.
        provider.stopUpdating(Self.first)
        #expect(!source.isRunning)
    }

    /// A recent position given at once: no time limit after it.
    @Test func aRememberedPositionIsNotFollowedByAFailure() async {
        let source = FakeSource()
        let webKit = FakeWebKit()
        let provider = GeolocationProvider(source: source, webKit: webKit)
        var told = 0
        provider.onNoPosition = { told += 1 }
        provider.positionTimeout = .milliseconds(50)
        provider.startUpdating(Self.first)
        source.onPosition?(Self.paris)
        provider.stopUpdating(Self.first)
        provider.startUpdating(Self.first)
        #expect(webKit.positions.count == 2)
        try? await Task.sleep(for: .milliseconds(120))
        #expect(told == 0)
        #expect(webKit.failures.isEmpty)
    }

    /// Another Core Location error (the network): "couldn't find", at once.
    @Test func anotherErrorIsToldAsNoPosition() {
        let source = FakeSource()
        let webKit = FakeWebKit()
        let provider = GeolocationProvider(source: source, webKit: webKit)
        var told = 0
        provider.onNoPosition = { told += 1 }
        provider.onDenied = { Issue.record("Not a refusal") }
        provider.startUpdating(Self.first)
        source.onError?(CLError(.network))
        #expect(told == 1)
        #expect(webKit.failures.count == 1)
        // An invalid fix is no position.
        source.onPosition?(CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            altitude: 0, horizontalAccuracy: -1, verticalAccuracy: -1, timestamp: Date()
        ))
        #expect(webKit.positions.isEmpty)
    }

    /// Nothing found in time: the page gets an error, the user is told.
    @Test func noPositionIsToldToThePageAndTheUser() async {
        let source = FakeSource()
        let webKit = FakeWebKit()
        let provider = GeolocationProvider(source: source, webKit: webKit)
        var told = 0
        provider.onNoPosition = { told += 1 }
        provider.positionTimeout = .milliseconds(50)
        provider.startUpdating(Self.first)
        // Core Location still looking: nothing said yet.
        source.onError?(CLError(.locationUnknown))
        #expect(webKit.failures.isEmpty)
        for _ in 0 ..< 100 where told == 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(told == 1)
        #expect(webKit.failures.count == 1)
    }

    @Test func aPositionInTimeTellsNothing() async {
        let source = FakeSource()
        let webKit = FakeWebKit()
        let provider = GeolocationProvider(source: source, webKit: webKit)
        var told = 0
        provider.onNoPosition = { told += 1 }
        provider.positionTimeout = .milliseconds(50)
        provider.startUpdating(Self.first)
        source.onPosition?(Self.paris)
        try? await Task.sleep(for: .milliseconds(120))
        #expect(told == 0)
        #expect(webKit.failures.isEmpty)
    }

    /// Location Services turned off meanwhile: the page gets an error, the
    /// user is told why.
    @Test func aRefusalIsToldToThePageAndTheUser() {
        let source = FakeSource()
        let webKit = FakeWebKit()
        let provider = GeolocationProvider(source: source, webKit: webKit)
        var denied = 0
        provider.onDenied = { denied += 1 }
        provider.onNoPosition = {}
        provider.startUpdating(Self.first)
        source.onError?(CLError(.denied))
        #expect(denied == 1)
        #expect(webKit.failures.count == 1)
    }

    /// A WebKit without the functions: nothing set, no crash.
    @Test func withoutWebKitsFunctionsNothingIsSet() throws {
        let provider = GeolocationProvider(source: FakeSource(), webKit: nil)
        #expect(!provider.isAvailable)
        try provider.install(on: #require(processPool(of: WKWebViewConfiguration())))
        provider.startUpdating(Self.first)
    }
}
