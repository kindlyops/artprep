import AppKit
import Combine
import Sparkle

@MainActor
final class Updater: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var startError: String?
    weak var workspace: Workspace?
    private let deferral = UpdateDeferral()
    private var controller: SPUStandardUpdaterController?
    private var observation: NSKeyValueObservation?
    private var started = false

    init(enabled: Bool = SigningCheck.isDeveloperIDSigned()) {
        super.init()
        guard enabled else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        observation = controller?.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) {
            [weak self] _, change in
            let ready = change.newValue ?? false
            Task { @MainActor [weak self] in self?.canCheckForUpdates = ready }
        }
    }

    var available: Bool { controller != nil }

    var automaticChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }

    func start() {
        guard !started, let controller else { return }
        do {
            try controller.updater.start()
            started = true
        } catch { startError = error.localizedDescription }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        controller?.checkForUpdates(nil)
    }

    func resumeIfReady() { deferral.resumeIfReady(locked: workspace?.locked == true) }

    func updater(
        _ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        let locked = workspace?.locked == true
        if locked {
            workspace?.message = "Update ready. Waiting for the current operation to finish."
        }
        return deferral.postpone(locked: locked, resume: installHandler)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        deferral.cancel()
    }
}
