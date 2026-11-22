import Foundation

/// Event-driven auto-hide controller with 150 ms reveal dwell and 400 ms hide delay.
/// Zero polling timers; only schedules one-shot work items on mouse enter/exit.
@MainActor
final class AutoHideController {
    static let revealDwell: TimeInterval = 0.15
    static let hideDelay: TimeInterval = 0.40

    private(set) var isHidden: Bool = false
    private(set) var isEnabled: Bool = false

    private var pendingWorkItem: DispatchWorkItem?
    private let onStateChanged: (Bool) -> Void

    init(onStateChanged: @escaping (Bool) -> Void) {
        self.onStateChanged = onStateChanged
    }

    func setEnabled(_ enabled: Bool, startHidden: Bool = true) {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        isEnabled = enabled

        if !enabled {
            if isHidden {
                isHidden = false
                onStateChanged(false)
            }
        } else if startHidden && !isHidden {
            isHidden = true
            onStateChanged(true)
        }
    }

    func mouseEntered() {
        guard isEnabled else { return }
        pendingWorkItem?.cancel()
        pendingWorkItem = nil

        guard isHidden else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isEnabled else { return }
            self.isHidden = false
            self.onStateChanged(false)
        }
        pendingWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.revealDwell, execute: work)
    }

    func mouseExited() {
        guard isEnabled else { return }
        pendingWorkItem?.cancel()
        pendingWorkItem = nil

        guard !isHidden else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isEnabled else { return }
            self.isHidden = true
            self.onStateChanged(true)
        }
        pendingWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hideDelay, execute: work)
    }

    /// Cancels a pending edge-trigger reveal if the cursor only swept across a shared monitor seam.
    func edgeTriggerMouseExited() {
        guard isEnabled, isHidden else { return }
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
    }

    func revealImmediately() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        if isHidden {
            isHidden = false
            onStateChanged(false)
        }
    }

    func cancelPending() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
    }
}
