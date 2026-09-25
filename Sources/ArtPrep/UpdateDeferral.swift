import Foundation

@MainActor
final class UpdateDeferral {
    private var continuation: (() -> Void)?

    func postpone(locked: Bool, resume: @escaping () -> Void) -> Bool {
        guard locked else { return false }
        continuation = resume
        return true
    }

    func resumeIfReady(locked: Bool) {
        guard !locked, let resume = continuation else { return }
        continuation = nil
        resume()
    }

    func cancel() { continuation = nil }
}
