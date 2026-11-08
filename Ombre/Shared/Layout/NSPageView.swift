import SwiftUI

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
    import AppKit
    import os.log

    private let logger = Logger(category: "NSPageView"
    )

    /// Finds a page from its identifier. Identifiers must be unique, or the
    /// later pages with the same one show the first page's content.
    enum PageIdentity {
        static func object<T>(withID id: String, in pages: [T], idKeyPath: KeyPath<T, String>) -> T? {
            pages.first { $0[keyPath: idKeyPath] == id }
        }
    }

    /// What the pager does with a new set of pages and selection. An animated
    /// transition only to show another page the user asked for, with pages
    /// in place and on screen; never while one runs (the new state waits for
    /// its end); never with no page or an index out of range (AppKit then
    /// crashes inside its animation).
    enum PagerUpdate: Equatable {
        case none
        /// No page left: the pager shows nothing.
        case clear
        case show(index: Int)
        case animate(index: Int)
        /// A transition runs: applied once it ends.
        case wait

        static func plan(
            currentCount: Int,
            currentIndex: Int,
            newCount: Int,
            newIndex: Int,
            pagesChanged: Bool,
            wantsAnimation: Bool,
            isAnimating: Bool,
            isOnScreen: Bool
        ) -> PagerUpdate {
            if isAnimating { return .wait }
            guard newCount > 0 else { return currentCount == 0 ? .none : .clear }
            let index = min(max(newIndex, 0), newCount - 1)
            if !pagesChanged, index == currentIndex { return .none }
            let canAnimate = wantsAnimation && !pagesChanged && isOnScreen
                && currentCount == newCount && currentIndex >= 0 && currentIndex < currentCount
            return canAnimate ? .animate(index: index) : .show(index: index)
        }
    }

    /// A ``NSViewControllerRepresentable`` for showing ``NSPageController``.
    /// Use ``init(selection:pageObjects:idKeyPath:contentView:)`` to initialize a view and add it to a SwiftUI view
    /// hierarchy.
    public struct NSPageView<T: Equatable, V: View>: NSViewControllerRepresentable {
        let selection: Binding<Int>
        let pageObjects: [T]
        let idKeyPath: KeyPath<T, String>

        let onContentPrepared: ((T) -> Void)?
        let contentView: (T) -> V

        /// Construct a ``NSPageView``.
        /// - parameter selection: a binding to the selected index, which should in range of ``pageObjects``
        /// - parameter pageObjects: provides data source
        /// - parameter idKeyPath: key path to access the id of ``T``
        /// - parameter contentView: given a ``T`` from ``pageObjects``, return a view to be displayed
        public init(
            selection: Binding<Int>,
            pageObjects: [T],
            idKeyPath: KeyPath<T, String>,
            onContentPrepared: ((T) -> Void)? = nil,
            @ViewBuilder contentView: @escaping (T) -> V
        ) {
            self.selection = selection
            self.pageObjects = pageObjects
            self.idKeyPath = idKeyPath
            self.onContentPrepared = onContentPrepared
            self.contentView = contentView
        }

        public func makeNSViewController(context: Context) -> some NSViewController {
            let controller = NSPageViewContainerController<T, V>()
            controller.pageObjects = pageObjects
            controller.idFromObject = { object in
                return object[keyPath: idKeyPath]
            }
            controller.objectToView = { object in
                return contentView(object)
            }
            controller.idToObject = { [weak controller] id in
                guard let controller else {
                    return nil
                }
                return PageIdentity.object(withID: id, in: controller.pageObjects, idKeyPath: idKeyPath)
            }
            controller.onContentPrepared = onContentPrepared
            controller.onSelectedIndexChanged = { index in
                withTransaction(selection.transaction) {
                    selection.wrappedValue = index
                }
            }
            controller.transitionStyle = .horizontalStrip
            // Its first page is the selected one, not page 0 animated to it.
            controller.initialIndex = selection.wrappedValue
            return controller
        }

        /// Pages made from now on show the current content, not the one of
        /// when the pager was made.
        func refresh(_ controller: NSPageViewContainerController<T, V>) {
            controller.objectToView = { object in contentView(object) }
        }

        public func updateNSViewController(_ nsViewController: some NSViewController, context: Context) {
            guard let controller = nsViewController as? NSPageViewContainerController<T, V> else {
                return
            }

            refresh(controller)
            let selectionAnimation = selection.transaction.animation
            let contextAnimation = context.transaction.animation
            controller.request(
                pageObjects: pageObjects,
                index: selection.wrappedValue,
                animated: selectionAnimation != nil || contextAnimation != nil
            )
        }
    }

    /// A NSView to exposure the ``onStartLiveResize`` and ``onEndLiveResize`` event.
    public class ResizeAwareNSView: NSView {
        public var onEndLiveResize: (() -> Void)?
        public var onStartLiveResize: (() -> Void)?

        override public func viewDidEndLiveResize() {
            super.viewDidEndLiveResize()
            onEndLiveResize?()
        }

        override public func viewWillStartLiveResize() {
            super.viewWillStartLiveResize()
            onStartLiveResize?()
        }
    }

    class NSPageViewContainerController<T, V: View>: NSPageController, NSPageControllerDelegate {
        var pageObjects: [T] = []

        var idFromObject: ((T) -> String)?
        var idToObject: ((String) -> T?)?
        var objectToView: ((T) -> V)?

        var onSelectedIndexChanged: ((Int) -> Void)?
        var onContentPrepared: ((T) -> Void)?
        var initialIndex = 0
        private var previousBoundsSize: CGSize = .zero
        private(set) var isAnimating = false

        /// Pages and selection SwiftUI asked for.
        struct Request {
            let pages: [T]
            let index: Int
            let animated: Bool
        }

        /// The latest request, applied outside of the SwiftUI update that
        /// asked (a transition started while a page's view lays out found no
        /// page to animate), or after a transition.
        private var requested: Request?
        private var isApplyScheduled = false

        override func loadView() {
            let view = ResizeAwareNSView()
            view.onStartLiveResize = { [weak self] in
                self?.completeTransition()
            }
            view.onEndLiveResize = { [weak self] in
                self?.completeTransition()
            }
            self.view = view
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            self.delegate = self
            self.updateDataSource()
            if !pageObjects.isEmpty {
                self.selectedIndex = min(max(initialIndex, 0), pageObjects.count - 1)
            }
            self.view.wantsLayer = true
        }

        override func viewDidLayout() {
            super.viewDidLayout()
            for view in self.view.subviews {
                view.frame = self.view.bounds
            }

            let currentSize = self.view.bounds.size
            if currentSize != previousBoundsSize {
                previousBoundsSize = currentSize
                self.completeTransition()
            }
        }

        func updateDataSource() {
            self.arrangedObjects = pageObjects
            logger.log("NSPageView updateDataSource \(self.arrangedObjects.count)")
        }

        func request(pageObjects pages: [T], index: Int, animated: Bool) {
            requested = Request(pages: pages, index: index, animated: animated)
            guard !isApplyScheduled else { return }
            isApplyScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.isApplyScheduled = false
                self?.applyRequest()
            }
        }

        private func applyRequest() {
            guard let requested else { return }
            let pagesChanged = !Self.samePages(pageObjects, requested.pages, idFromObject)
            let plan = PagerUpdate.plan(
                currentCount: arrangedObjects.count,
                currentIndex: selectedIndex,
                newCount: requested.pages.count,
                newIndex: requested.index,
                pagesChanged: pagesChanged,
                wantsAnimation: requested.animated,
                isAnimating: isAnimating,
                isOnScreen: view.window != nil && view.bounds.width > 0
            )
            logger.log("NSPageView \(String(describing: plan)), \(requested.pages.count) pages")
            switch plan {
            case .wait:
                return
            case .none:
                self.requested = nil
            case .clear:
                self.requested = nil
                pageObjects = []
                updateDataSource()
            case let .show(index):
                self.requested = nil
                pageObjects = requested.pages
                updateDataSource()
                selectedIndex = index
                completeTransition()
            case let .animate(index: index):
                self.requested = nil
                pageObjects = requested.pages
                isAnimating = true
                NSAnimationContext.runAnimationGroup { context in
                    // Short and easing out, like the downloads panel.
                    context.duration = 0.3
                    context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
                    self.animator().selectedIndex = index
                } completionHandler: {
                    // AppKit ends its animations on the main thread.
                    MainActor.assumeIsolated {
                        self.completeTransition()
                        self.isAnimating = false
                        // What was asked meanwhile.
                        self.applyRequest()
                    }
                }
            }
        }

        /// Same pages in the same order, by identifier.
        private static func samePages(_ lhs: [T], _ rhs: [T], _ identifier: ((T) -> String)?) -> Bool {
            guard let identifier else { return false }
            return lhs.map(identifier) == rhs.map(identifier)
        }

        func pageController(
            _ pageController: NSPageController,
            identifierFor object: Any
        ) -> NSPageController.ObjectIdentifier {
            guard let typedObject = object as? T else {
                logger.log("NSPageView identifierFor: unexpected object type")
                return ""
            }
            return idFromObject?(typedObject) ?? ""
        }

        func pageController(
            _ pageController: NSPageController,
            viewControllerForIdentifier identifier: NSPageController.ObjectIdentifier
        ) -> NSViewController {
            let controller = NSPageViewContentController<T, V>()
            controller.content = objectToView
            controller.object = idToObject?(identifier)
            if let object = controller.object {
                onContentPrepared?(object)
            }
            return controller
        }

        /// A page reached (a swipe at the ends): told back, unless the pager
        /// is still on its way to another one asked for.
        func pageController(_ pageController: NSPageController, didTransitionTo object: Any) {
            DispatchQueue.main.async {
                guard !self.isAnimating, self.requested == nil else { return }
                self.onSelectedIndexChanged?(self.selectedIndex)
            }
        }
    }

    class NSPageViewContentController<T, V: View>: NSViewController {
        var content: ((T) -> V)?
        var object: T?

        private var hostingView: NSHostingView<AnyView>?

        override func loadView() {
            self.view = NSView()
        }

        override func viewDidLoad() {
            super.viewDidLoad()

            guard let object, let content else {
                return
            }
            let view = content(object)
            let wrappedView = AnyView(view.ignoresSafeArea())
            let hostingView = NSHostingView(rootView: wrappedView)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: self.view.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
            ])
            self.hostingView = hostingView
        }
    }
#endif
