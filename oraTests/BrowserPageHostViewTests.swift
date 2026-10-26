import AppKit
@testable import Ora
import Testing

@MainActor
struct BrowserPageHostViewTests {
    @Test func attachingFirstContentViewAddsSubview() {
        let host = makeHost()
        let contentView = TrackingContentView()

        host.host(contentView: contentView)

        #expect(host.subviews.count == 1)
        #expect(host.subviews.first === contentView)
        #expect(host.hostedContentView === contentView)
        #expect(contentView.frame == host.bounds)
    }

    @Test func switchingContentViewsDetachesOldViewAndAttachesNewView() {
        let host = makeHost()
        let firstContentView = TrackingContentView()
        let secondContentView = TrackingContentView()

        host.host(contentView: firstContentView)
        host.host(contentView: secondContentView)

        #expect(host.subviews.count == 1)
        #expect(host.subviews.first === secondContentView)
        #expect(host.hostedContentView === secondContentView)
        #expect(firstContentView.superview == nil)
        #expect(secondContentView.superview === host)
    }

    @Test func updatingWithSameContentViewIsANoOp() {
        let host = makeHost()
        let contentView = TrackingContentView()

        host.host(contentView: contentView)
        let transitionCountAfterFirstAttach = contentView.superviewTransitions

        host.host(contentView: contentView)

        #expect(host.subviews.count == 1)
        #expect(host.subviews.first === contentView)
        #expect(contentView.superviewTransitions == transitionCountAfterFirstAttach)
    }

    @Test func clearingContentViewRemovesHostedSubview() {
        let host = makeHost()
        let contentView = TrackingContentView()

        host.host(contentView: contentView)
        host.host(contentView: nil)

        #expect(host.subviews.isEmpty)
        #expect(host.hostedContentView == nil)
        #expect(contentView.superview == nil)
    }

    @Test func attachingContentViewFromAnotherHostReparentsItCleanly() {
        let firstHost = makeHost()
        let secondHost = makeHost()
        let contentView = TrackingContentView()

        firstHost.host(contentView: contentView)
        secondHost.host(contentView: contentView)

        #expect(firstHost.subviews.isEmpty)
        #expect(firstHost.hostedContentView == nil)
        #expect(secondHost.subviews.count == 1)
        #expect(secondHost.subviews.first === contentView)
        #expect(secondHost.hostedContentView === contentView)
        #expect(contentView.superview === secondHost)
        #expect(contentView.removeFromSuperviewCalls == 1)
    }

    @Test func switchingToAStaleSubviewAlreadyAttachedToTheSameHostDoesNotReparentIt() {
        let host = makeHost()
        let firstContentView = TrackingContentView()
        let staleContentView = TrackingContentView()

        host.host(contentView: firstContentView)
        host.addSubview(staleContentView)

        let staleSuperviewTransitions = staleContentView.superviewTransitions

        host.host(contentView: staleContentView)

        #expect(host.subviews.count == 1)
        #expect(host.subviews.first === staleContentView)
        #expect(host.hostedContentView === staleContentView)
        #expect(firstContentView.superview == nil)
        #expect(staleContentView.superview === host)
        #expect(staleContentView.superviewTransitions == staleSuperviewTransitions)
        #expect(staleContentView.removeFromSuperviewCalls == 0)
    }

    @Test func cancelOperationStopsAtTheHostInsteadOfReachingTheWindow() {
        let host = makeHost()
        let nextResponder = CancelOperationSpy()
        host.nextResponder = nextResponder
        var handlerCalls = 0
        host.cancelOperationHandler = { handlerCalls += 1 }

        host.cancelOperation(nil)

        #expect(handlerCalls == 1)
        #expect(nextResponder.cancelOperationCalls == 0)
    }

    /// The docked Web Inspector WebKit takes away when its page leaves the
    /// window (tab switch) comes back with the page in its new host.
    @Test func inspectorTakenAwayOffScreenFollowsItsPage() {
        let firstHost = makeHost()
        let page = TrackingContentView()
        let inspector = NSView()
        firstHost.host(contentView: page)
        firstHost.addSubview(inspector)

        inspector.removeFromSuperview() // WebKit, page out of the window.
        let secondHost = makeHost()
        secondHost.host(contentView: page)

        #expect(inspector.superview === secondHost)
        #expect(secondHost.subviews.first === inspector) // Below the page.
    }

    /// An inspector closed by the user (on screen) is not brought back.
    @Test func inspectorClosedOnScreenIsForgotten() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [],
            backing: .buffered,
            defer: true
        )
        let firstHost = makeHost()
        window.contentView = firstHost
        let page = TrackingContentView()
        let inspector = NSView()
        firstHost.host(contentView: page)
        firstHost.addSubview(inspector)

        inspector.removeFromSuperview() // Closed, page on screen.
        let secondHost = makeHost()
        secondHost.host(contentView: page)

        #expect(inspector.superview == nil)
        #expect(secondHost.subviews.count == 1)
    }

    private func makeHost() -> BrowserPageHostView {
        BrowserPageHostView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    }
}

private final class TrackingContentView: NSView {
    var superviewTransitions = 0
    var removeFromSuperviewCalls = 0

    override func removeFromSuperview() {
        removeFromSuperviewCalls += 1
        super.removeFromSuperview()
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        superviewTransitions += 1
        super.viewWillMove(toSuperview: newSuperview)
    }
}

/// Records `cancelOperation(_:)` calls that reach it through the responder chain.
private final class CancelOperationSpy: NSResponder {
    private(set) var cancelOperationCalls = 0

    override func cancelOperation(_ sender: Any?) {
        cancelOperationCalls += 1
    }
}
