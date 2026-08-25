//
//  CountlyPlatformTests.swift
//  CountlyTests
//
//  Cross-platform integration coverage for the Apple platforms this SDK ships to:
//  iOS, watchOS, tvOS, macOS and visionOS. The same bundle is compiled and run for
//  every platform, so each test asserts the expected-for-this-platform behaviour taken
//  from `TestPlatform` (see TestPlatform.swift) rather than being duplicated per platform.
//
//  Scope:
//   - CountlyPlatformIntegrationTests  — identity/metrics, config defaults, API surface,
//                                        and that the core recording pipeline works everywhere.
//   - CountlyPlatformLifecycleTests    — which application-lifecycle callbacks the SDK
//                                        actually observes on each platform, and what they do.
//

import XCTest

@testable import Countly

#if canImport(UIKit)
    import UIKit
#endif
#if canImport(AppKit)
    import AppKit
#endif
#if canImport(WatchKit)
    import WatchKit
#endif

// MARK: - Identity, configuration and API surface

class CountlyPlatformIntegrationTests: CountlyBaseTestCase {

    /// Groups everything that identifies the running platform to the server: the
    /// metrics blob, the default device-ID type (and the `t` parameter derived from
    /// it) and where the request queue is persisted.
    func test_platformIdentity_metricsDeviceIDTypeAndStorageLocation() throws {
        // --- metrics -----------------------------------------------------------
        let metrics = try XCTUnwrap(CountlyDeviceInfo.metricsDictionary() as? [String: Any])

        XCTAssertEqual(TestPlatform.osName, metrics["_os"] as? String)
        let deviceType = try XCTUnwrap(metrics["_device_type"] as? String)
        XCTAssertTrue(
            TestPlatform.deviceTypes.contains(deviceType),
            "Unexpected _device_type '\(deviceType)' for \(TestPlatform.osName)")

        for key in ["_device", "_os_version", "_locale"] {
            let value = metrics[key] as? String
            XCTAssertFalse(
                (value ?? "").isEmpty, "Metric \(key) must be reported on \(TestPlatform.osName)")
        }

        if TestPlatform.reportsScreenMetrics {
            // WIDTHxHEIGHT, both parseable as Double. Same contract as
            // CountlyScreenMetricsTests.test_resolution_isWellFormedString, which also has to
            // tolerate the exponent form `%g` can emit.
            let resolution = try XCTUnwrap(metrics["_resolution"] as? String)
            let sides = resolution.components(separatedBy: "x")
            XCTAssertEqual(2, sides.count, "Unexpected _resolution '\(resolution)'")
            for side in sides {
                XCTAssertNotNil(Double(side), "Unexpected _resolution '\(resolution)'")
            }
            let density = try XCTUnwrap(metrics["_density"] as? String)
            XCTAssertTrue(density.hasPrefix("@"), "Unexpected _density '\(density)'")
            XCTAssertTrue(density.hasSuffix("x"), "Unexpected _density '\(density)'")
            XCTAssertNotNil(
                Int(density.dropFirst().dropLast()), "Unexpected _density '\(density)'")
        } else {
            XCTAssertNil(metrics["_resolution"])
            XCTAssertNil(metrics["_density"])
        }

        // `_carrier` is CoreTelephony-backed, so it can only ever appear on iOS — and even
        // there it is absent without a SIM (every simulator). Only the negative direction
        // is deterministic.
        if !TestPlatform.reportsCarrier {
            XCTAssertNil(
                metrics["_carrier"], "_carrier must not be reported on \(TestPlatform.osName)")
        }

        // --- default device ID type -------------------------------------------
        // createBaseConfig deliberately sets no deviceID, which is what this asserts.
        let config = createBaseConfig()
        config.requiresConsent = false
        config.manualSessionHandling = true
        Countly.sharedInstance().start(with: config)

        XCTAssertTrue(
            Countly.sharedInstance().deviceIDType() == TestPlatform.defaultDeviceIDType,
            "Default device ID type on \(TestPlatform.osName) should be "
                + "\(TestPlatform.defaultDeviceIDType.rawValue)")

        Countly.sharedInstance().beginSession()
        let request = TestUtils.parseQueryString(try XCTUnwrap(TestUtils.getCurrentRQ()?.first))
        XCTAssertEqual(TestPlatform.defaultDeviceIDTypeValue, request["t"] as? String)
        XCTAssertEqual(TestPlatform.osName, (request["metrics"] as? [String: Any])?["_os"] as? String)

        // --- persistence location ---------------------------------------------
        CountlyPersistency.sharedInstance().saveToFileSync()

        var expectedDirectory = try XCTUnwrap(
            FileManager.default.urls(for: TestPlatform.storageDirectory, in: .userDomainMask).last)
        #if os(macOS)
            // macOS sandboxes per bundle, so the SDK nests the file under the bundle id.
            if let bundleID = Bundle.main.bundleIdentifier {
                expectedDirectory = expectedDirectory.appendingPathComponent(bundleID)
            }
        #endif
        let storageFile = expectedDirectory.appendingPathComponent("Countly.dat")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: storageFile.path),
            "Countly.dat is not at the expected \(TestPlatform.osName) location: \(storageFile.path)")
    }

    /// The session/queue tuning defaults are the numbers the public documentation
    /// quotes, and only `updateSessionPeriod` differs per platform.
    func test_platformConfigDefaults_sessionPeriodThresholdAndQueueLimits() {
        let config = CountlyConfig()

        XCTAssertEqual(
            TestPlatform.defaultUpdateSessionPeriod, config.updateSessionPeriod, accuracy: 0.001,
            "updateSessionPeriod default is wrong for \(TestPlatform.osName)")
        // eventSendThreshold is 100 on every platform — it has not been watchOS-specific
        // since it was raised from the old 3/10 split.
        XCTAssertEqual(100, config.eventSendThreshold)
        XCTAssertEqual(1000, config.storedRequestsLimit)
        XCTAssertEqual(30, config.requestTimeoutDuration)
    }

    /// The public API surface is trimmed per platform by `TARGET_OS_*` guards. This
    /// asserts both directions: platform-specific features are absent where they are
    /// compiled out, and the always-available ones respond everywhere.
    func test_platformFeatureSurface_matchesCompiledGuards() {
        let countly = Countly.sharedInstance()

        // WebKit-backed: feedback widgets, star rating, content zone.
        for selector in [
            NSSelectorFromString("feedback"),
            NSSelectorFromString("content"),
            NSSelectorFromString("askForStarRating:"),
        ] {
            XCTAssertEqual(
                TestPlatform.hasWebKitFeatures, countly.responds(to: selector),
                "\(selector) availability does not match \(TestPlatform.osName)")
        }

        // Push notifications.
        XCTAssertEqual(
            TestPlatform.hasPushNotifications,
            countly.responds(to: NSSelectorFromString("askForNotificationPermission")),
            "Push notification API availability does not match \(TestPlatform.osName)")

        // Automatic view tracking. The public API, the `CountlyConfig` switch and the
        // internal implementation must all agree: `CountlyConsentManager` calls
        // `startAutoViewTracking` wherever the API is declared, so a narrower
        // implementation guard is an unrecognized-selector crash on consent changes.
        XCTAssertEqual(
            TestPlatform.hasAutoViewTrackingAPI,
            countly.responds(to: NSSelectorFromString("isAutoViewTrackingActive")),
            "Auto view tracking API availability does not match \(TestPlatform.osName)")
        XCTAssertEqual(
            TestPlatform.hasAutoViewTrackingAPI,
            CountlyConfig().responds(to: NSSelectorFromString("enableAutomaticViewTracking")),
            "enableAutomaticViewTracking availability does not match \(TestPlatform.osName)")
        // Checked on the class, not the singleton: `CountlyViewTrackingInternal.sharedInstance`
        // returns nil until the SDK has started.
        for selector in ["startAutoViewTracking", "stopAutoViewTracking",
                         "addExceptionForAutoViewTracking:", "removeExceptionForAutoViewTracking:"] {
            XCTAssertEqual(
                TestPlatform.hasAutoViewTracking,
                CountlyViewTrackingInternal.instancesRespond(to: NSSelectorFromString(selector)),
                "\(selector) implementation availability does not match \(TestPlatform.osName)")
        }

        // `suspend`/`resume` are implemented on every platform (the SDK drives them from
        // its own lifecycle handlers) but only *declared* in the public header on watchOS.
        // Header visibility is compile-time only — the watchOS test calling them directly
        // is what proves it — so at runtime they must respond everywhere.
        XCTAssertTrue(countly.responds(to: NSSelectorFromString("suspend")))
        XCTAssertTrue(countly.responds(to: NSSelectorFromString("resume")))

        // Available on every platform.
        for selector in [
            NSSelectorFromString("views"),
            NSSelectorFromString("remoteConfig"),
            NSSelectorFromString("userProfile"),
            NSSelectorFromString("recordEvent:"),
            NSSelectorFromString("beginSession"),
            NSSelectorFromString("endSession"),
        ] {
            XCTAssertTrue(
                countly.responds(to: selector),
                "\(selector) must be available on \(TestPlatform.osName)")
        }
    }

    /// End-to-end smoke test of the recording pipeline that every platform shares:
    /// a manual view, a custom event and a user property all reach the request queue
    /// with the right shape. Manual view recording in particular is *not* limited to
    /// the auto-view-tracking platforms.
    func test_corePipeline_recordsViewEventAndUserPropertyOnEveryPlatform() throws {
        let config = TestUtils.createBaseConfig()
        config.requiresConsent = false
        config.manualSessionHandling = true
        Countly.sharedInstance().start(with: config)

        let viewID = Countly.sharedInstance().views().startView("platform_view")
        XCTAssertNotNil(
            viewID, "Manual view recording must work on \(TestPlatform.osName)")

        Countly.sharedInstance().recordEvent("platform_event", segmentation: ["p": TestPlatform.osName])
        Countly.sharedInstance().views().stopView(withID: viewID)

        Countly.sharedInstance().userProfile().set("platform", value: TestPlatform.osName)
        Countly.sharedInstance().userProfile().save()

        // The user-details save flushes the event queue into the request queue first.
        let requests = try XCTUnwrap(TestUtils.getCurrentRQ())
        let joined = requests.joined(separator: "\n")
        XCTAssertTrue(joined.contains("platform_event"), "Custom event missing from RQ:\n\(joined)")
        XCTAssertTrue(joined.contains("%5BCLY%5D_view"), "View event missing from RQ:\n\(joined)")
        XCTAssertTrue(joined.contains("user_details"), "User details missing from RQ:\n\(joined)")

        // Every request carries the platform's metrics and device ID type.
        for request in requests {
            let parsed = TestUtils.parseQueryString(request)
            XCTAssertEqual(TestUtils.commonDeviceId, parsed["device_id"] as? String)
            XCTAssertEqual(TestUtils.SDK_NAME, parsed["sdk_name"] as? String)
        }
    }
}

// MARK: - Application lifecycle

class CountlyPlatformLifecycleTests: CountlyBaseTestCase {

    /// Starts the SDK with automatic session handling and a live session, so lifecycle
    /// notifications have something observable to act on.
    ///
    /// The assertions below count `begin_session` / `end_session` occurrences in the whole
    /// request queue, so the queue has to start empty. `cleanupState()` in setUp is not enough
    /// on its own: classes that start the SDK once per class rather than per test can leave
    /// requests behind, which showed up as "expected 1 session, got 2". halt(true) here runs
    /// while the SDK is live, so it genuinely wipes the persisted queue.
    private func startWithAutomaticSession() {
        Countly.sharedInstance().halt(true)
        let config = TestUtils.createBaseConfig()
        config.requiresConsent = false
        Countly.sharedInstance().start(with: config)
    }

    private func requestQueue() -> [String] {
        return TestUtils.getCurrentRQ() ?? []
    }

    private func count(of marker: String) -> Int {
        return requestQueue().filter { $0.contains(marker) }.count
    }

    /// Posts a notification. The queue mutations these tests assert on are synchronous, so
    /// no wait is needed; `waitUntil` is there for the handlers that hop through
    /// `dispatch_async` (health state save, `saveToFile`).
    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }

    /// Returns as soon as `condition` holds, so a satisfied expectation costs no wall clock.
    private func waitUntil(
        _ description: String, timeout: TimeInterval = 2.0, _ condition: () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        XCTAssertTrue(condition(), "Timed out waiting for \(description)")
    }

    /// The core lifecycle contract, asserted per platform in one flow:
    ///  - iOS/tvOS/visionOS observe UIKit background/foreground and cycle the session.
    ///  - macOS has no background state; it only recovers a dropped `begin_session`
    ///    when the app becomes active, and never ends the session automatically.
    ///  - watchOS observes nothing; the host app drives `suspend`/`resume`.
    func test_lifecycleNotifications_cycleSessionAccordingToPlatform() throws {
        startWithAutomaticSession()

        #if os(iOS) || os(tvOS) || os(visionOS)
            // The simulator's xctest host is active, so start already opened a session.
            let sessionsAtStart = count(of: "begin_session=1")
            XCTAssertGreaterThanOrEqual(sessionsAtStart, 1, "Expected a session at start")
            let endsAtStart = count(of: "end_session=1")

            // Background ends the session and persists health state.
            post(UIApplication.didEnterBackgroundNotification)
            XCTAssertEqual(endsAtStart + 1, count(of: "end_session=1"), "Background must end the session")

            // Foreground alone is only a notification hook; activation is what resumes.
            post(UIApplication.willEnterForegroundNotification)
            XCTAssertEqual(
                sessionsAtStart, count(of: "begin_session=1"),
                "willEnterForeground must not begin a session")

            post(UIApplication.didBecomeActiveNotification)
            XCTAssertEqual(
                sessionsAtStart + 1, count(of: "begin_session=1"),
                "Activation must begin a new session")

            // Resigning active saves health state but must not end the session.
            post(UIApplication.willResignActiveNotification)
            XCTAssertEqual(
                endsAtStart + 1, count(of: "end_session=1"),
                "willResignActive must not end the session")

        #elseif os(macOS)
            // The base test case reports the app as active, so start opened a session.
            let sessionsAtStart = count(of: "begin_session=1")
            XCTAssertGreaterThanOrEqual(sessionsAtStart, 1, "Expected a session at start")

            // macOS has no background state, so nothing ends the session on its own and
            // re-activation must not open a second one.
            let endsAtStart = count(of: "end_session=1")
            post(NSApplication.willResignActiveNotification)
            XCTAssertEqual(
                endsAtStart, count(of: "end_session=1"),
                "macOS must not end sessions on resign active")

            post(NSApplication.didBecomeActiveNotification)
            XCTAssertEqual(
                sessionsAtStart, count(of: "begin_session=1"),
                "Re-activation must not open a second session")

        #elseif os(watchOS)
            // watchOS registers no lifecycle observers, and there is no notification to post
            // there in the first place. The observable contract is that the session opened at
            // start stays open until the host app calls `suspend` itself, which is what
            // test_manualSuspendResume_isTheWatchOSSessionDriver covers.
            XCTAssertEqual(1, count(of: "begin_session=1"), "Expected a session at start")
            XCTAssertEqual(
                0, count(of: "end_session=1"), "Nothing may end a watchOS session on its own")
        #endif
    }

    #if !os(watchOS)
    /// `applicationWillTerminate` is observed on every platform but watchOS, where there is
    /// no such notification and `suspend` is the documented equivalent (covered by the
    /// suspend/resume test). It must flush pending events into the request queue, stop
    /// running views and mark the connection manager as terminating.
    func test_terminateCallback_flushesEventsAndStopsViews() throws {
        let config = TestUtils.createBaseConfig()
        config.requiresConsent = false
        config.manualSessionHandling = true
        Countly.sharedInstance().start(with: config)

        let viewID = Countly.sharedInstance().views().startView("terminating_view")
        Countly.sharedInstance().recordEvent("pending_event")
        XCTAssertFalse(
            (TestUtils.getCurrentEQ() ?? []).isEmpty, "Event should still be queued before terminate")

        #if os(macOS)
            post(NSApplication.willTerminateNotification)
        #else
            post(UIApplication.willTerminateNotification)
        #endif

        XCTAssertTrue(CountlyConnectionManager.sharedInstance().isTerminating)
        XCTAssertEqual(0, TestUtils.getCurrentEQ()?.count, "Terminate must flush the event queue")

        let joined = requestQueue().joined(separator: "\n")
        XCTAssertTrue(joined.contains("pending_event"), "Flushed event missing from RQ:\n\(joined)")
        XCTAssertTrue(joined.contains("%5BCLY%5D_view"), "View end event missing from RQ:\n\(joined)")

        // Reset so later tests are not affected by the terminating flag.
        CountlyConnectionManager.sharedInstance().isTerminating = false
        XCTAssertNotNil(viewID)
    }
    #endif

    #if os(watchOS)
    /// `suspend`/`resume` are the host app's substitute for the UIKit notifications on
    /// watchOS. `suspend` must end the session and flush, and `resume` must open exactly one
    /// new session however many times it is called.
    func test_manualSuspendResume_isTheWatchOSSessionDriver() throws {
            startWithAutomaticSession()
            Countly.sharedInstance().recordEvent("watch_event")

            Countly.sharedInstance().suspend()
            XCTAssertEqual(1, count(of: "end_session=1"), "suspend must end the session")
            XCTAssertEqual(0, TestUtils.getCurrentEQ()?.count, "suspend must flush the event queue")
            XCTAssertTrue(
                requestQueue().joined(separator: "\n").contains("watch_event"),
                "suspend must move recorded events into the request queue")

            // suspend is idempotent — a second call must not add another end_session.
            Countly.sharedInstance().suspend()
            XCTAssertEqual(1, count(of: "end_session=1"), "suspend must be idempotent")

            // `resume` skips its very first invocation in a process to avoid double
            // sessions on watch app launch, so two calls yield exactly one new session.
            let sessionsBefore = count(of: "begin_session=1")
            Countly.sharedInstance().resume()
            Countly.sharedInstance().resume()
            XCTAssertEqual(
                sessionsBefore + 1, count(of: "begin_session=1"),
                "resume must open exactly one new session")
    }
    #endif

    /// Visibility segmentation depends on a per-platform foreground check
    /// (`UIApplication` / `NSApplication` / `WKExtension`). It must be resolvable —
    /// and therefore emitted as 0 or 1 — on every platform.
    func test_visibilityTracking_resolvesForegroundStateOnEveryPlatform() throws {
        let config = TestUtils.createBaseConfig()
        config.requiresConsent = false
        config.manualSessionHandling = true
        config.experimental().enableVisibiltyTracking = true
        // `CountlyConfig.experimental` is a process-wide shared object, so leaving the flag
        // set would turn visibility segmentation on for every later test.
        defer { config.experimental().enableVisibiltyTracking = false }
        Countly.sharedInstance().start(with: config)

        Countly.sharedInstance().recordEvent("visibility_event")
        CountlyConnectionManager.sharedInstance().sendEvents()
        waitUntil("the event to reach the request queue") {
            self.requestQueue().contains { $0.contains("visibility_event") }
        }

        let eventRequest = try XCTUnwrap(
            requestQueue().first { $0.contains("visibility_event") },
            "No request carried the visibility event")
        let events = try XCTUnwrap(
            TestUtils.parseQueryString(eventRequest)["events"] as? String)
        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(events.utf8)) as? [[String: Any]])
        let segmentation = try XCTUnwrap(
            parsed.first(where: { $0["key"] as? String == "visibility_event" })?["segmentation"]
                as? [String: Any])
        let visibility = try XCTUnwrap(
            segmentation["cly_v"] as? Int,
            "cly_v must be reported on \(TestPlatform.osName), got: \(segmentation)")
        XCTAssertTrue(
            visibility == 0 || visibility == 1, "cly_v must be 0 or 1, got \(visibility)")
    }

    #if os(macOS)
    /// `beginSession` refuses to open a session while a macOS app is not active (launched
    /// hidden, as a login item, or opened by another app). macOS observes
    /// `NSApplicationDidBecomeActiveNotification` so that the dropped session is opened on
    /// the first activation instead of being lost for the life of the process.
    func test_macOSInactiveLaunch_recoversDroppedSessionOnActivation() throws {
            TestAppActivation.isActive = false
            startWithAutomaticSession()
            XCTAssertEqual(
                0, count(of: "begin_session=1"),
                "An inactive macOS app must not open a session at start")

            // Still inactive: activation notifications alone must not fabricate a session.
            post(NSApplication.didBecomeActiveNotification)
            XCTAssertEqual(0, count(of: "begin_session=1"))

            TestAppActivation.isActive = true
            post(NSApplication.didBecomeActiveNotification)
            XCTAssertEqual(
                1, count(of: "begin_session=1"),
                "Activation must recover the session macOS dropped at start")

            post(NSApplication.didBecomeActiveNotification)
            XCTAssertEqual(1, count(of: "begin_session=1"), "and only one session")
    }
    #endif
}
