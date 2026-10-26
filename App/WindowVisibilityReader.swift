import AppKit
import F1Core
import OSLog
import SwiftUI

/// Attach once to the window container, outside section/content changes.
struct WindowVisibilityReader: NSViewRepresentable {
    let onChange: @MainActor (Bool) -> Void
    func makeNSView(context: Context) -> ObserverView { ObserverView(onChange: onChange) }
    func updateNSView(_ view: ObserverView, context: Context) { view.delivery.onChange = onChange }
    static func dismantleNSView(_ view: ObserverView, coordinator: ()) { view.detach() }

    @MainActor final class ObserverView: NSView {
        let delivery: WindowVisibilityDelivery
        private weak var observedWindow: NSWindow?
        private var observations: [NSObjectProtocol] = []
        private var attachmentRevision = 0
        private let logger = Logger(subsystem: "com.murilloarturo.f1menubar", category: "WindowLifecycle")

        init(onChange: @escaping @MainActor (Bool) -> Void) {
            delivery = WindowVisibilityDelivery(onChange: onChange)
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            detach()
            guard let window else { return }
            observedWindow = window
            logWindow("attached")
            let token = attachmentRevision
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didBecomeKeyNotification,
                         NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                         NSWindow.didResizeNotification, NSWindow.didResignKeyNotification] {
                observations.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.attachmentRevision == token else { return }
                        self.logWindow(name.rawValue)
                        self.reportVisibility(attachment: token)
                    }
                })
            }
            observations.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.attachmentRevision == token else { return }
                    self.logWindow("willClose")
                    self.delivery.submit(false)
                }
            })
            reportVisibility(attachment: token)
        }

        private func reportVisibility(attachment token: Int) {
            guard attachmentRevision == token, let observedWindow, observedWindow === window else { return }
            delivery.submit(observedWindow.isVisible && !observedWindow.isMiniaturized && observedWindow.occlusionState.contains(.visible))
        }

        func detach() {
            if observedWindow != nil { logWindow("detached") }
            attachmentRevision += 1
            observations.forEach { NotificationCenter.default.removeObserver($0) }
            observations.removeAll()
            observedWindow = nil
            delivery.submit(false)
        }

        private func logWindow(_ event: String) {
            guard let window = observedWindow else { return }
            // Lifecycle metadata only: never record timing payloads or connection credentials.
            logger.info("\(event, privacy: .public) window=\(window.windowNumber) visible=\(window.isVisible) key=\(window.isKeyWindow) miniaturized=\(window.isMiniaturized) occluded=\(!window.occlusionState.contains(.visible)) frame=\(NSStringFromRect(window.frame), privacy: .public) content=\(NSStringFromRect(window.contentLayoutRect), privacy: .public)")
        }
    }
}
