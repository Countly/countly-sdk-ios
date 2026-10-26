//
//  CountlyCrashReporterTests.swift
//  CountlyTests
//
//  Created by Arif Burak Demiray on 23.05.2024.
//  Copyright © 2024 Countly. All rights reserved.
//

import Foundation
import XCTest

@testable import Countly

class CountlyCrashReporterTests: CountlyBaseTestCase {

    /// Local Countly instances created during tests.
    var localCountlyInstances: [Countly] = []

    override func tearDown() {
        for instance in localCountlyInstances {
            instance.halt(true)
        }
        localCountlyInstances = []
        super.tearDown()
    }

    func testRecordHandledException_globalCrashFilter() throws {
        let cConfig = createBaseConfig()
        cConfig.manualSessionHandling = true
        cConfig.crashSegmentation = [
            "secret": "Minato",
            "int": String(Int.max),
            "double": String(Double.greatestFiniteMagnitude),
            "bool": String(true),
            "long": String(Int64.max),
            "float": String(1.1),
        ]

        let crashFilterBlock: (CountlyCrashData?) -> Bool = { crash in
            if crash!.crashDescription.contains("Secret") {
                return true
            }

            crash?.crashSegmentation.removeObject(forKey: "secret")
            crash?.fatal = true
            crash!.crashMetrics["secret"] = "Minato"
            crash!.crashMetrics.removeObject(forKey: "_ram_total")

            let keys = crash!.crashSegmentation.allKeys as? [String]
            return keys!.contains("sphinx_no_1")
        }

        cConfig.crashes().crashFilterCallback = crashFilterBlock

        let countly = Countly()
        localCountlyInstances.append(countly)
        countly.start(with: cConfig)

        // First Exception
        let exception1 = NSException(name: NSExceptionName(rawValue: "secret"), reason: "Secret message")
        countly.record(exception1, isFatal: false, stackTrace: nil, segmentation: nil)
        XCTAssertEqual(0, CountlyPersistency.sharedInstance().remainingRequestCount())

        // Second Exception
        let exception2 = NSException(name: NSExceptionName(rawValue: "some"), reason: "Some message")
        countly.record(exception2, isFatal: false, stackTrace: nil, segmentation: ["sphinx_no_1": "secret"])
        XCTAssertEqual(0, CountlyPersistency.sharedInstance().remainingRequestCount())

        // Third Exception
        countly.recordCrashLog("Breadcrumb_1")
        countly.recordCrashLog("Breadcrumb_2")
        let exception3 = NSException(name: NSExceptionName(rawValue: "some_other"), reason: "Some other message")
        countly.record(exception3, isFatal: false, stackTrace: nil, segmentation: ["sphinx_no": "324"])
        XCTAssertEqual(1, CountlyPersistency.sharedInstance().remainingRequestCount())

        try validateCrash(
            CountlyCrashReporterTests.extractStackTrace(exception3),
            breadcrumbs: "Breadcrumb_1\nBreadcrumb_2",
            isFatal: true,
            changedBits: 11,
            customSegmentation: [
                "int": String(Int.max),
                "double": String(Double.greatestFiniteMagnitude),
                "bool": String(true),
                "float": String(1.1),
                "long": String(Int64.max),
                "sphinx_no": "324",
            ],
            idx: 0,
            customMetrics: ["secret": "Minato"],
            metricsToExclude: ["_ram_total"]
        )
    }

    func validateCrash(
        _ stackTrace: String?, breadcrumbs: String, isFatal: Bool, changedBits: Int, customSegmentation: [String: Any],
        idx: Int, customMetrics: [String: Any], metricsToExclude: [String]
    ) throws {

        if let queuedRequests = CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? [String] {
            let request = TestUtils.parseQueryString(queuedRequests[idx])
            //TestUtils.validateRequiredParams(RQ[idx])

            let crash = request["crash"] as! [String: Any]

            // try validateCrashMetrics(crash: crash,
            //   customMetrics: customMetrics,
            //   metricsToExclude: metricsToExclude)
            var paramCount = 0

            paramCount += 2  // for nonFatal and ob
            XCTAssertEqual(!isFatal, crash["_nonfatal"] as? Bool)
            XCTAssertEqual(changedBits, crash["_ob"] as? Int)

            if !customSegmentation.isEmpty {
                paramCount += 1
                let custom = crash["_custom"] as? [String: Any]

                for (key, value) in customSegmentation {
                    XCTAssertEqual(value as? NSObject, custom![key] as? NSObject)
                }
                XCTAssertEqual(custom?.count, customSegmentation.count)
            }

            if !breadcrumbs.isEmpty {
                paramCount += 1
                XCTAssertEqual(breadcrumbs, crash["_logs"] as? String)
            }

            //XCTAssertEqual(paramCount, crash.count)
        }

    }

    func validateCrashMetrics(crash: [String: Any], customMetrics: [String: Any], metricsToExclude: [String]) throws
        -> Int {
        var metricCount = 20 - metricsToExclude.count

        try assertMetricIfNotExcluded(
            metricsToExclude: metricsToExclude, key: "_device", expectedValue: "C", crash: crash)
        try assertMetricIfNotExcluded(metricsToExclude: metricsToExclude, key: "_os", expectedValue: "A", crash: crash)
        try assertMetricIfNotExcluded(
            metricsToExclude: metricsToExclude, key: "_os_version", expectedValue: "B", crash: crash)
        try assertMetricIfNotExcluded(
            metricsToExclude: metricsToExclude, key: "_resolution", expectedValue: "E", crash: crash)
        try assertMetricIfNotExcluded(
            metricsToExclude: metricsToExclude, key: "_app_version", expectedValue: "Countly.DEFAULT_APP_VERSION",
            crash: crash)
        try assertMetricIfNotExcluded(
            metricsToExclude: metricsToExclude, key: "_manufacturer", expectedValue: "D", crash: crash)
        try assertMetricIfNotExcluded(metricsToExclude: metricsToExclude, key: "_cpu", expectedValue: "N", crash: crash)
        try assertMetricIfNotExcluded(
            metricsToExclude: metricsToExclude, key: "_opengl", expectedValue: "O", crash: crash)
        try assertMetricIfNotExcluded(
            metricsToExclude: metricsToExclude, key: "_root", expectedValue: "T", crash: crash)
        try assertMetricIfNotExcluded(
            metricsToExclude: metricsToExclude, key: "_has_hinge", expectedValue: "Z", crash: crash)
        try assertMetricIfNotExcluded(
            metricsToExclude: metricsToExclude, key: "_ram_total", expectedValue: "48", crash: crash)
        try assertMetricIfNotExcluded(
            metricsToExclude: metricsToExclude, key: "_disk_total", expectedValue: "45", crash: crash)
        try assertMetricIfNotExcluded(
            metricsToExclude: metricsToExclude, key: "_ram_current", expectedValue: "12", crash: crash)
        try assertMetricIfNotExcluded(
            metricsToExclude: metricsToExclude, key: "_disk_current", expectedValue: "23", crash: crash)
        try assertMetricIfNotExcluded(
            metricsToExclude: metricsToExclude, key: "_run", expectedValue: "88", crash: crash)
        try assertMetricIfNotExcluded(
            metricsToExclude: metricsToExclude, key: "_background", expectedValue: "true", crash: crash)
        try assertMetricIfNotExcluded(
            metricsToExclude: metricsToExclude, key: "_muted", expectedValue: "V", crash: crash)
        try assertMetricIfNotExcluded(
            metricsToExclude: metricsToExclude, key: "_orientation", expectedValue: "S", crash: crash)
        try assertMetricIfNotExcluded(
            metricsToExclude: metricsToExclude, key: "_online", expectedValue: "U", crash: crash)
        try assertMetricIfNotExcluded(metricsToExclude: metricsToExclude, key: "_bat", expectedValue: "6", crash: crash)

        for (key, value) in customMetrics {
            guard let crashValue = crash[key], "\(crashValue)" == "\(value)" else {
                throw ValidationError.assertionFailed
            }
        }
        metricCount += customMetrics.count

        return metricCount
    }

    enum ValidationError: Error {
        case jsonError
        case assertionFailed
    }

    func assertMetricIfNotExcluded(metricsToExclude: [String], key: String, expectedValue: String, crash: [String: Any])
        throws
    {
        if !metricsToExclude.contains(key) {
            XCTAssertTrue(expectedValue == crash[key] as? String)
        } else {
            XCTAssertNil(crash[key])
        }
    }

    static func extractStackTrace(_ exception: NSException) -> String? {
        return exception.callStackSymbols.joined(separator: "\n")
    }

    // MARK: - handing crashes on to the handlers the SDK replaced

    #if !os(watchOS)
    /// Address of the handler a signal currently runs, so a test can tell whose handler is live.
    private func liveSignalHandler(_ signalCode: Int32) -> UnsafeRawPointer? {
        var action = sigaction()
        sigaction(signalCode, nil, &action)
        return unsafeBitCast(action.__sigaction_u.__sa_handler, to: UnsafeRawPointer?.self)
    }

    /// Address of the live uncaught exception handler.
    private func liveExceptionHandler() -> UnsafeRawPointer? {
        unsafeBitCast(NSGetUncaughtExceptionHandler(), to: UnsafeRawPointer?.self)
    }

    /**
     * <pre>
     * The SDK installs over the handlers the app had, chains to them, leaves a signal the app ignores
     * alone, never takes the hook back from a crash tool installed after it, and puts its replaced
     * handlers back on halt.
     *
     * 1- Install an app exception handler and an app SIGFPE handler, and ignore SIGPIPE
     * 2- Start with crash consent and verify the SDK's handlers are live, SIGPIPE stays ignored
     * 3- Install a later crash tool's exception handler and apply the behavior settings again
     * 4- Verify the later tool keeps the hook
     * 5- Withdraw crash consent, verify the app's SIGFPE handler is back and the later tool still holds the exception hook
     * 6- Call the SDK's handler the way the later tool chains to it, verify the app's handler runs and no crash is recorded
     * 7- Give consent again, halt, and verify the app's SIGFPE handler is back once more
     * </pre>
     */
    func test_crashHandlers_chainToTheReplacedHandlers_andLeaveIgnoredSignalsAndLaterHandlers() throws {
        appExceptionHandlerCalls = 0
        let appExceptionHandler: @convention(c) (NSException) -> Void = { _ in appExceptionHandlerCalls += 1 }
        let laterExceptionHandler: @convention(c) (NSException) -> Void = { _ in }
        let appSignalHandler: @convention(c) (Int32) -> Void = { _ in }
        NSSetUncaughtExceptionHandler(appExceptionHandler)
        signal(SIGFPE, appSignalHandler)
        signal(SIGPIPE, SIG_IGN)
        defer {
            NSSetUncaughtExceptionHandler(nil)
            signal(SIGFPE, SIG_DFL)
            signal(SIGPIPE, SIG_DFL)
        }
        let appExceptionAddress = unsafeBitCast(appExceptionHandler, to: UnsafeRawPointer.self)
        let laterExceptionAddress = unsafeBitCast(laterExceptionHandler, to: UnsafeRawPointer.self)
        let appSignalAddress = unsafeBitCast(appSignalHandler, to: UnsafeRawPointer.self)

        let config = createBaseConfig()
        config.manualSessionHandling = true
        config.requiresConsent = true
        config.consents = [CLYConsent.crashReporting]
        Countly.sharedInstance().start(with: config)

        let sdkExceptionHandler = try XCTUnwrap(NSGetUncaughtExceptionHandler())
        XCTAssertNotEqual(appExceptionAddress, liveExceptionHandler(), "the SDK installs its exception handler over the app's")
        XCTAssertNotEqual(appSignalAddress, liveSignalHandler(SIGFPE), "the SDK installs its signal handler over the app's")
        XCTAssertEqual(unsafeBitCast(SIG_IGN, to: UnsafeRawPointer?.self), liveSignalHandler(SIGPIPE), "a signal the app ignores is not a crash")

        NSSetUncaughtExceptionHandler(laterExceptionHandler)
        CountlyServerConfig.sharedInstance()?.applyAutomaticTrackingState()
        XCTAssertEqual(laterExceptionAddress, liveExceptionHandler(), "applying behavior settings never takes the hook back from a crash tool installed later")

        Countly.sharedInstance().cancelConsent(forFeature: CLYConsent.crashReporting)
        XCTAssertEqual(appSignalAddress, liveSignalHandler(SIGFPE), "withdrawing consent puts the app's signal handler back")
        XCTAssertEqual(laterExceptionAddress, liveExceptionHandler(), "a handler installed over the SDK's is not removed")

        sdkExceptionHandler(NSException(name: NSExceptionName("ChainedException"), reason: "chained by a later crash tool", userInfo: nil))
        XCTAssertEqual(1, appExceptionHandlerCalls, "the SDK's handler passes the crash on to the handler it replaced")
        XCTAssertFalse(TestUtils.getCurrentRQ()?.contains { $0.contains("crash=") } ?? true, "without crash consent a chained crash is not recorded")

        Countly.sharedInstance().giveConsent(forFeature: CLYConsent.crashReporting)
        XCTAssertNotEqual(appSignalAddress, liveSignalHandler(SIGFPE), "giving consent again reinstalls over the handler the SDK put back")
        Countly.sharedInstance().halt(true)
        XCTAssertEqual(appSignalAddress, liveSignalHandler(SIGFPE), "halt puts back the handler the SDK replaced")
        XCTAssertEqual(laterExceptionAddress, liveExceptionHandler(), "halt leaves a later crash tool's handler alone")
    }

    /**
     * <pre>
     * A broken pipe is often survived, and only the app's own SIGPIPE handler knows whether it is, so the
     * SDK leaves a SIGPIPE the app handles to it, as it leaves one the app ignores, while it still
     * installs over the app's other handlers.
     *
     * 1- Install app handlers for SIGPIPE and SIGFPE and start with crash reporting
     * 2- Verify the app's SIGPIPE handler is still live and the SDK's handler runs for SIGFPE
     * 3- Raise SIGPIPE and verify only the app's handler ran and nothing is recorded
     * </pre>
     */
    func test_crashHandlers_leaveASigpipeTheAppHandlesToTheApp() throws {
        appSignalHandlerCalls = 0
        let appSignalHandler: @convention(c) (Int32) -> Void = { _ in appSignalHandlerCalls += 1 }
        signal(SIGPIPE, appSignalHandler)
        signal(SIGFPE, appSignalHandler)
        defer {
            signal(SIGPIPE, SIG_DFL)
            signal(SIGFPE, SIG_DFL)
        }
        let appSignalAddress = unsafeBitCast(appSignalHandler, to: UnsafeRawPointer.self)

        let config = createBaseConfig()
        config.manualSessionHandling = true
        Countly.sharedInstance().start(with: config)
        XCTAssertEqual(appSignalAddress, liveSignalHandler(SIGPIPE), "the app's SIGPIPE handler stays live")
        XCTAssertNotEqual(appSignalAddress, liveSignalHandler(SIGFPE),
                          "the SDK still installs over the app's other handlers")

        raise(SIGPIPE)
        XCTAssertEqual(1, appSignalHandlerCalls, "the broken pipe goes to the app's handler alone")
        let queue = TestUtils.getCurrentRQ() ?? []
        XCTAssertFalse(queue.contains { $0.contains("crash=") }, "and is not reported as a crash")
        Countly.sharedInstance().halt(true)
    }

    /**
     * <pre>
     * A crash tool installed while the SDK's handlers were removed chains to the handler before them, not
     * to the SDK's, so the SDK installs over it once crash reporting is wanted again instead of staying
     * silently off.
     *
     * 1- Start requiring consent with crash consent given, then withdraw it, which removes the SDK's handler
     * 2- Install a crash tool's exception handler
     * 3- Give crash consent again and verify the SDK's handler is live over the tool's
     * </pre>
     */
    func test_crashHandlers_installOverAToolInstalledWhileTheyWereRemoved() throws {
        let toolExceptionHandler: @convention(c) (NSException) -> Void = { _ in }
        defer { NSSetUncaughtExceptionHandler(nil) }
        let toolExceptionAddress = unsafeBitCast(toolExceptionHandler, to: UnsafeRawPointer.self)

        let config = createBaseConfig()
        config.manualSessionHandling = true
        config.requiresConsent = true
        config.consents = [CLYConsent.crashReporting]
        Countly.sharedInstance().start(with: config)
        let sdkExceptionAddress = liveExceptionHandler()

        Countly.sharedInstance().cancelConsent(forFeature: CLYConsent.crashReporting)
        XCTAssertNotEqual(sdkExceptionAddress, liveExceptionHandler(), "withdrawing consent removes the SDK's handler")

        NSSetUncaughtExceptionHandler(toolExceptionHandler)
        Countly.sharedInstance().giveConsent(forFeature: CLYConsent.crashReporting)
        XCTAssertEqual(sdkExceptionAddress, liveExceptionHandler(),
                       "the SDK installs over the tool installed while it was removed")
        XCTAssertNotEqual(toolExceptionAddress, liveExceptionHandler())

        Countly.sharedInstance().halt(true)
        XCTAssertEqual(toolExceptionAddress, liveExceptionHandler(), "halt gives the tool its hook back")
    }

    /**
     * <pre>
     * A signal that reaches the SDK's handler after the server turned automatic crash reporting off goes
     * back to the handler the app had instead of returning into the code that raised it, which for a
     * hardware fault would run the faulting instruction again forever.
     *
     * 1- Install an app SIGFPE handler, start the SDK with the settings reply held back
     * 2- Release a reply that turns automatic crash reporting off, verify the SDK's handler stays live
     * 3- Raise the signal and verify the app's handler ran once, is live again, and no crash is recorded
     * 4- Install the SDK's handler again, raise again and verify the signal is handed back the same way
     * </pre>
     */
    func test_signalHandler_handsTheSignalBack_whenAutomaticCrashReportingTurnsOffAtRuntime() throws {
        appSignalHandlerCalls = 0
        let appSignalHandler: @convention(c) (Int32) -> Void = { _ in appSignalHandlerCalls += 1 }
        signal(SIGFPE, appSignalHandler)
        defer { signal(SIGFPE, SIG_DFL) }
        let appSignalAddress = unsafeBitCast(appSignalHandler, to: UnsafeRawPointer.self)

        let releaseSettings = DispatchSemaphore(value: 0)
        let settings = ServerConfigBuilder().automaticCrashReporting(false).build()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url?.absoluteString.contains("method=sc") == true {
                _ = releaseSettings.wait(timeout: .now() + 5)
                return (settings.data(using: .utf8), response, nil)
            }
            return ("{\"result\":\"fail\"}".data(using: .utf8), HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil), nil)
        }
        defer { MockURLProtocol.replyEmptyToEveryRequest() }

        let config = createBaseConfig()
        config.manualSessionHandling = true
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        config.urlSessionConfiguration = sessionConfig
        Countly.sharedInstance().start(with: config)
        XCTAssertNotEqual(appSignalAddress, liveSignalHandler(SIGFPE), "the SDK installs its signal handler over the app's")

        releaseSettings.signal()
        TestUtils.waitUntil("the reply to turn automatic crash reporting off") {
            CountlyServerConfig.sharedInstance()?.automaticCrashReportingEnabled() == false
        }
        XCTAssertNotEqual(appSignalAddress, liveSignalHandler(SIGFPE),
                          "a runtime 'acr' = false leaves the SDK's handler installed")

        raise(SIGFPE)

        XCTAssertEqual(1, appSignalHandlerCalls, "the signal is handed back to the app's handler")
        XCTAssertEqual(appSignalAddress, liveSignalHandler(SIGFPE), "the app's handler is live again")
        XCTAssertFalse(TestUtils.getCurrentRQ()?.contains { $0.contains("crash=") } ?? true, "automatic crash reporting is off, so nothing is recorded")

        let serverConfig = try XCTUnwrap(CountlyServerConfig.sharedInstance())
        serverConfig.setValue(true, forKey: "automaticCrashReportingEnabled")
        try XCTUnwrap(CountlyCrashReporter.sharedInstance()).startCrashReporting()
        serverConfig.setValue(false, forKey: "automaticCrashReportingEnabled")
        XCTAssertNotEqual(appSignalAddress, liveSignalHandler(SIGFPE),
                          "the SDK installs its handler over the app's again")

        raise(SIGFPE)

        XCTAssertEqual(2, appSignalHandlerCalls, "a signal the app survived does not make the next one end the app")
        XCTAssertEqual(appSignalAddress, liveSignalHandler(SIGFPE), "the app's handler is live again")
    }

    /// Starts the SDK with crash reporting while every request fails, so a crash it reports stays in the request queue.
    private func startWithEveryRequestFailing() {
        MockURLProtocol.requestHandler = { request in
            ("{\"result\":\"fail\"}".data(using: .utf8), HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil), nil)
        }

        let config = createBaseConfig()
        config.manualSessionHandling = true
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        config.urlSessionConfiguration = sessionConfig
        Countly.sharedInstance().start(with: config)
    }

    /// Halts the SDK after writing an empty request queue to disk. Halt writes the queue it clears in the background, so on a
    /// slow runner the next test's start would otherwise load the crash this test left queued.
    private func haltWithAnEmptyStoredQueue() {
        CountlyPersistency.sharedInstance().flushQueue()
        CountlyPersistency.sharedInstance().saveToFileSync()
        Countly.sharedInstance().halt(true)
    }

    /// The messages of the log lines the SDK holds for the running gather that start with the given text, read under its
    /// gathering lock, since the SDK captures into the same arrays from its own threads.
    private func heldLogLines(startingWith prefix: String) -> [String] {
        let common: CountlyCommon = CountlyCommon.sharedInstance()
        let lock = common.value(forKey: "sdkLogsLock") as AnyObject
        objc_sync_enter(lock)
        defer { objc_sync_exit(lock) }
        let held = ["sdkLogs", "sdkLogsAwaitingConsent"].flatMap { (common.value(forKey: $0) as? [[String: Any]]) ?? [] }
        return held.compactMap { $0["m"] as? String }.filter { $0.hasPrefix(prefix) }
    }

    /**
     * <pre>
     * A crash the SDK reports is passed on to the exception handler the app had before the SDK started, as one it does
     * not report is.
     *
     * 1- Install an app exception handler, then start with crash reporting while every request fails
     * 2- Call the SDK's handler the way the runtime calls it for an uncaught exception
     * 3- Verify the crash is queued, and the app's handler ran once and is live again
     * </pre>
     */
    func test_uncaughtExceptionHandler_passesAReportedCrashOnToTheReplacedHandler() throws {
        appExceptionHandlerCalls = 0
        let appExceptionHandler: @convention(c) (NSException) -> Void = { _ in appExceptionHandlerCalls += 1 }
        NSSetUncaughtExceptionHandler(appExceptionHandler)
        defer {
            NSSetUncaughtExceptionHandler(nil)
            MockURLProtocol.replyEmptyToEveryRequest()
        }
        let appExceptionAddress = unsafeBitCast(appExceptionHandler, to: UnsafeRawPointer.self)

        startWithEveryRequestFailing()
        let sdkExceptionHandler = try XCTUnwrap(NSGetUncaughtExceptionHandler())
        XCTAssertNotEqual(appExceptionAddress, liveExceptionHandler(), "the SDK installs its exception handler over the app's")

        sdkExceptionHandler(NSException(name: NSExceptionName("ReportedException"), reason: "reported and passed on", userInfo: nil))

        XCTAssertTrue(TestUtils.getCurrentRQ()?.contains { $0.contains("crash=") && $0.contains("ReportedException") } ?? false, "the SDK reports the crash")
        XCTAssertEqual(1, appExceptionHandlerCalls, "and passes it on to the handler it replaced")
        XCTAssertEqual(appExceptionAddress, liveExceptionHandler(), "which is live again")
        haltWithAnEmptyStoredQueue()
    }

    /**
     * <pre>
     * A signal the SDK reports as a crash goes on to the handler the app had before the SDK started, not to the default
     * action, which would end the app before that handler runs.
     *
     * 1- Install an app SIGFPE handler, then start with crash reporting while every request fails
     * 2- Raise the signal
     * 3- Verify the crash is queued, and the app's handler ran once and is live again
     * </pre>
     */
    func test_signalHandler_handsAReportedCrashOnToTheReplacedHandler() throws {
        appSignalHandlerCalls = 0
        let appSignalHandler: @convention(c) (Int32) -> Void = { _ in appSignalHandlerCalls += 1 }
        signal(SIGFPE, appSignalHandler)
        defer {
            signal(SIGFPE, SIG_DFL)
            MockURLProtocol.replyEmptyToEveryRequest()
        }
        let appSignalAddress = unsafeBitCast(appSignalHandler, to: UnsafeRawPointer.self)

        startWithEveryRequestFailing()
        XCTAssertNotEqual(appSignalAddress, liveSignalHandler(SIGFPE), "the SDK installs its signal handler over the app's")

        raise(SIGFPE)

        XCTAssertTrue(TestUtils.getCurrentRQ()?.contains { $0.contains("crash=") && $0.contains("SIGFPE") } ?? false, "the SDK reports the crash")
        XCTAssertEqual(1, appSignalHandlerCalls, "and hands the signal on to the handler it replaced")
        XCTAssertEqual(appSignalAddress, liveSignalHandler(SIGFPE), "which is live again")
        haltWithAnEmptyStoredQueue()
    }

    /**
     * <pre>
     * Log gathering stops capturing while the SDK reports a crash. An app that outlives a reported crash through a handler
     * of its own gets capture back when crash reporting starts again, as it gets the SDK's handler back.
     *
     * 1- Install an app SIGFPE handler, start with crash reporting while every request fails, and arm a gather of errors
     * 2- Raise the signal and verify the crash is queued, the app's handler ran, and a line logged after it is not gathered
     * 3- Start crash reporting again and verify the SDK's handler is live and a line logged now is gathered
     * </pre>
     */
    func test_signalHandler_logCaptureResumesWithCrashReporting_afterTheAppOutlivesAReportedCrash() throws {
        appSignalHandlerCalls = 0
        let appSignalHandler: @convention(c) (Int32) -> Void = { _ in appSignalHandlerCalls += 1 }
        signal(SIGFPE, appSignalHandler)
        defer {
            signal(SIGFPE, SIG_DFL)
            MockURLProtocol.replyEmptyToEveryRequest()
        }
        let appSignalAddress = unsafeBitCast(appSignalHandler, to: UnsafeRawPointer.self)
        let errorLevel = CChar(Character("e").asciiValue!)

        startWithEveryRequestFailing()
        let common: CountlyCommon = CountlyCommon.sharedInstance()
        // the delivery that init end scheduled runs first, so the lines of the gather armed below stay held where they are read
        try XCTUnwrap(common.value(forKey: "sdkLogsDeliveryQueue") as? DispatchQueue).sync {}
        // errors only, so the SDK's own lines stay out of the gather
        common.updateLogGatheringState(true, levels: "e", batch: 100, lgid: "crash_gather")
        common.captureSdkLogLine("gathered before the crash", level: errorLevel)
        XCTAssertTrue(common.isCapturingSdkLogs(), "the gather captures")

        raise(SIGFPE)
        common.captureSdkLogLine("gathered while crash reporting is off", level: errorLevel)

        XCTAssertTrue(TestUtils.getCurrentRQ()?.contains { $0.contains("crash=") && $0.contains("SIGFPE") } ?? false, "the SDK reports the crash")
        XCTAssertEqual(1, appSignalHandlerCalls, "and the app outlives it")
        XCTAssertFalse(common.isCapturingSdkLogs(), "capture stops for the report")

        try XCTUnwrap(CountlyCrashReporter.sharedInstance()).startCrashReporting()
        common.captureSdkLogLine("gathered once crash reporting is back", level: errorLevel)

        XCTAssertNotEqual(appSignalAddress, liveSignalHandler(SIGFPE), "crash reporting starts again")
        XCTAssertTrue(common.isCapturingSdkLogs(), "and so does capture")
        XCTAssertEqual(["gathered before the crash", "gathered once crash reporting is back"], heldLogLines(startingWith: "gathered"),
                       "only the line logged while crash reporting was off is missing")
        haltWithAnEmptyStoredQueue()
    }
    #endif

}

#if !os(watchOS)
/// Times the app's stand-in exception handler ran.
private var appExceptionHandlerCalls = 0
/// Times the app's stand-in signal handler ran.
private var appSignalHandlerCalls = 0
#endif

