import Foundation

/// Pure watch-loop decision logic, hardware-independent for testability. The
/// watch loop applies enforcement for the resulting state; the only automatic
/// transition it performs is locking when `lockOnKeyRemoval` is enabled, the
/// machine is unlocked, and no enrolled key is attached.
public enum Watch {
    public static func nextState(
        current: LockState,
        lockOnKeyRemoval: Bool,
        attachedKey: Bool
    ) -> LockState {
        if current == .unlocked && lockOnKeyRemoval && !attachedKey {
            return .locked
        }
        return current
    }
}
