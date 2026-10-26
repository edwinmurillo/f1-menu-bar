import AppKit
import F1Core
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
            let token = attachmentRevision
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didBecomeKeyNotification,
                         NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
                observations.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.reportVisibility(attachment: token) }
                })
            }
            observations.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.attachmentRevision == token else { return }
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
            attachmentRevision += 1
            observations.forEach { NotificationCenter.default.removeObserver($0) }
            observations.removeAll()
            observedWindow = nil
            delivery.submit(false)
        }
    }
}
