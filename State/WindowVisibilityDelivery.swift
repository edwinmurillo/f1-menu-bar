import Foundation

/// AppKit view attachment/removal can occur inside a SwiftUI update. Deliver visibility later,
/// collapsing temporary detach/attach events and invalidating obsolete queued notifications.
@MainActor
public final class WindowVisibilityDelivery {
    typealias Enqueue = (@escaping @MainActor @Sendable () -> Void) -> Void
    private let enqueue: Enqueue
    private var revision = 0
    private var lastDelivered: Bool?
    public var onChange: @MainActor (Bool) -> Void

    public convenience init(onChange: @escaping @MainActor (Bool) -> Void) {
        self.init(enqueue: { action in Task { @MainActor in action() } }, onChange: onChange)
    }

    init(enqueue: @escaping Enqueue, onChange: @escaping @MainActor (Bool) -> Void) {
        self.enqueue = enqueue
        self.onChange = onChange
    }

    public func submit(_ visible: Bool) {
        revision += 1
        let token = revision
        enqueue { [weak self] in
            guard let self, revision == token, lastDelivered != visible else { return }
            lastDelivered = visible
            onChange(visible)
        }
    }
}
