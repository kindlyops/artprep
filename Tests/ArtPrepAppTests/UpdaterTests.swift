import AppKit
import XCTest

@testable import ArtPrep

final class UpdaterTests: XCTestCase {
    @MainActor
    func testDisabledUpdaterCannotStartNetworkChecks() {
        let updater = Updater(enabled: false)
        updater.start()
        updater.checkForUpdates()
        updater.automaticChecks = true
        XCTAssertFalse(updater.available)
        XCTAssertFalse(updater.canCheckForUpdates)
        XCTAssertFalse(updater.automaticChecks)
    }

    @MainActor
    func testDeferralWaitsAndResumesOnlyOnce() {
        let deferral = UpdateDeferral()
        var calls = 0
        XCTAssertTrue(deferral.postpone(locked: true) { calls += 1 })
        deferral.resumeIfReady(locked: true)
        XCTAssertEqual(calls, 0)
        deferral.resumeIfReady(locked: false)
        deferral.resumeIfReady(locked: false)
        XCTAssertEqual(calls, 1)
    }

    @MainActor
    func testReadyWorkspaceDoesNotRetainContinuation() {
        let deferral = UpdateDeferral()
        var calls = 0
        XCTAssertFalse(deferral.postpone(locked: false) { calls += 1 })
        deferral.resumeIfReady(locked: false)
        XCTAssertEqual(calls, 0)
    }

    @MainActor
    func testAbandonedUpdateCannotResumeAfterNextOperation() {
        let deferral = UpdateDeferral()
        var abandoned = 0
        var next = 0
        XCTAssertTrue(deferral.postpone(locked: true) { abandoned += 1 })
        deferral.cancel()
        XCTAssertTrue(deferral.postpone(locked: true) { next += 1 })
        deferral.resumeIfReady(locked: true)
        XCTAssertEqual(next, 0)
        deferral.resumeIfReady(locked: false)
        XCTAssertEqual(abandoned, 0)
        XCTAssertEqual(next, 1)
    }

    @MainActor
    func testUpdaterCannotQuitWhileWorkspaceIsLocked() {
        let workspace = Workspace()
        let delegate = AppDelegate()
        delegate.workspace = workspace
        workspace.busy = true
        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateCancel)
        workspace.busy = false
        workspace.exporting = true
        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateCancel)
    }

    func testDevelopmentBundleDoesNotEnableUpdates() {
        XCTAssertFalse(SigningCheck.isDeveloperIDSigned(bundleURL: Bundle.main.bundleURL))
        XCTAssertFalse(SigningCheck.isDeveloperIDSigned(bundleURL: URL(fileURLWithPath: "/tmp")))
    }
}
