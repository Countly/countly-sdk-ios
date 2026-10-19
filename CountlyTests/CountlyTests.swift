//
//  CountlyTests.swift
//  CountlyTests
//
//  Created by Muhammad Junaid Akram on 22/12/2023.
//  Copyright © 2023 Countly. All rights reserved.
//

import XCTest
@testable import Countly


/// A logger that, once armed, keeps the first thread other than the main thread that logs a given line waiting for a while.
private final class DelayingLogger: NSObject, CountlyLoggerDelegate {
    private let text: String
    private let delay: TimeInterval
    private let lock = NSLock()
    private var isArmed = false

    /// A logger that delays the line containing the text by the given seconds.
    init(delaying text: String, by delay: TimeInterval) {
        self.text = text
        self.delay = delay
    }

    /// Delays the next matching line.
    func arm() {
        lock.lock()
        isArmed = true
        lock.unlock()
    }

    /// Waits on the first matching line logged off the main thread after arm.
    func internalLog(_ log: String, with level: CLYInternalLogLevel) {
        guard !Thread.isMainThread, log.contains(text) else { return }
        lock.lock()
        let shouldDelay = isArmed
        isArmed = false
        lock.unlock()
        if shouldDelay {
            Thread.sleep(forTimeInterval: delay)
        }
    }
}

class CountlyTests: CountlyBaseTestCase {
    
    // MARK: - Configuration Tests
    
    func testReInitWithDeviceId() throws {
        let config = createBaseConfig()
        // No Device ID provided during init
        Countly.sharedInstance().start(with: config);
        
        let sdkGeneratedDeviceID = Countly.sharedInstance().deviceID()
        XCTAssertTrue(CountlyCommon.sharedInstance().hasStarted, "Countly initialization failed.")
        XCTAssertTrue(Countly.sharedInstance().deviceIDType() == TestPlatform.defaultDeviceIDType, "Countly deviced id type should be the platform default (IDFV on iOS/tvOS/visionOS, NSUUID on watchOS/macOS) when no device id is provided during init.")
        Countly.sharedInstance().halt(false)
        XCTAssertTrue(!CountlyCommon.sharedInstance().hasStarted, "Countly halt failed.")
        
        let deviceID = String(Int.random(in: 0..<100))
    
        let newConfig = createBaseConfig()
        newConfig.deviceID = deviceID
        Countly.sharedInstance().start(with: newConfig);
        
        XCTAssertTrue(CountlyCommon.sharedInstance().hasStarted, "Countly initialization failed.")
        XCTAssertTrue(Countly.sharedInstance().deviceID() == sdkGeneratedDeviceID, "Countly device id not match with provided device id.")
        XCTAssertTrue(Countly.sharedInstance().deviceIDType() == TestPlatform.defaultDeviceIDType, "Countly deviced id type should stay the platform default when the stored id is reused.")
    }
    
    /**
     * <pre>
     * Remote config values never outlive "halt": a download still in flight writes nothing into the storage halt cleared,
     * and the next start in the same process does not serve the values the halted run held in memory.
     *
     * 1- Download a value, then start a second download and hold its reply
     * 2- Halt with storage cleared and start again
     * 3- Release the held reply, and verify it was not stored and neither value is served
     * </pre>
     */
    func testRemoteConfig_afterHalt_noValueOfTheHaltedRunIsStoredOrServed() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        final class Counter {
            private let lock = NSLock()
            private var value = 0
            /// Counts one more call and returns the new count.
            func next() -> Int {
                lock.lock()
                defer { lock.unlock() }
                value += 1
                return value
            }
        }
        let downloads = Counter()
        let releaseSecondDownload = DispatchSemaphore(value: 0)
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)
            guard request.url?.absoluteString.contains("method=rc") == true else {
                return ("{}".data(using: .utf8), response, nil)
            }
            if downloads.next() == 1 {
                return (#"{"kept_key":"kept_value"}"#.data(using: .utf8), response, nil)
            }
            _ = releaseSecondDownload.wait(timeout: .now() + 5)
            return (#"{"held_key":"held_value"}"#.data(using: .utf8), response, nil)
        }
        defer { MockURLProtocol.replyEmptyToEveryRequest() }

        let config = createBaseConfig()
        config.manualSessionHandling = true
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        config.urlSessionConfiguration = sessionConfig
        Countly.sharedInstance().start(with: config)

        let downloaded = XCTestExpectation(description: "the first download")
        Countly.sharedInstance().remoteConfig().downloadKeys { _, _, _, _ in downloaded.fulfill() }
        wait(for: [downloaded], timeout: 10)
        XCTAssertEqual("kept_value", Countly.sharedInstance().remoteConfig().getValue("kept_key").value as? String)

        Countly.sharedInstance().remoteConfig().downloadKeys { _, _, _, _ in }
        Countly.sharedInstance().halt(true)
        Countly.sharedInstance().start(with: config)
        XCTAssertNil(Countly.sharedInstance().remoteConfig().getValue("kept_key").value, "the next start serves no value the halted run held")

        releaseSecondDownload.signal()
        TestUtils.sleep(1) {}
        XCTAssertNil(CountlyPersistency.sharedInstance().retrieveRemoteConfig()["held_key"], "a reply to a request made before halt stores nothing")
        XCTAssertNil(Countly.sharedInstance().remoteConfig().getValue("held_key").value, "and is not served either")
    }

    /**
     * <pre>
     * "halt" gives the configuration given at start its own values back. Behavior settings write their resolved values
     * into it, and its internal limits are shared by every configuration, so without this the next start would take the
     * halted run's behavior settings for the developer's values.
     *
     * 1- Start with developer supplied behavior settings that lift the consent requirement and lower two values
     * 2- Verify they applied, then halt
     * 3- Verify the configuration, and a new one for the shared limits, hold the developer's values again
     * 4- Start again without behavior settings and verify the developer's values apply
     * </pre>
     */
    func testHalt_givesTheStartConfigurationItsOwnValuesBack() throws {
        let config = createBaseConfig()
        config.manualSessionHandling = true
        config.requiresConsent = true
        config.eventSendThreshold = 7
        config.sdkInternalLimits().setMaxKeyLength(64)
        config.sdkBehaviorSettings = ServerConfigBuilder()
            .consentRequired(false)
            .logging(false)
            .eventQueueSize(3)
            .limitKeyLength(20)
            .build()
        Countly.sharedInstance().start(with: config)

        XCTAssertFalse(CountlyConsentManager.sharedInstance().requiresConsent, "the behavior settings lift the consent requirement")
        XCTAssertEqual(3, CountlyPersistency.sharedInstance().eventSendThreshold)
        XCTAssertEqual(20, CountlyCommon.sharedInstance().maxKeyLength)
        XCTAssertFalse(config.requiresConsent, "while the SDK runs, the resolved values live in the start configuration")

        Countly.sharedInstance().halt(true)

        XCTAssertTrue(config.requiresConsent, "halt gives back the developer's consent requirement")
        XCTAssertTrue(config.enableDebug, "and the developer's logging")
        XCTAssertEqual(7, config.eventSendThreshold, "and the developer's event threshold")
        XCTAssertEqual(64, config.sdkInternalLimits().getMaxKeyLength(), "and the developer's key length limit")
        XCTAssertEqual(64, CountlyConfig().sdkInternalLimits().getMaxKeyLength(), "which every configuration in the process shares")

        // the property is nonnull in Swift, so the provided settings are cleared through KVC
        config.setValue(nil, forKey: "sdkBehaviorSettings")
        Countly.sharedInstance().start(with: config)

        XCTAssertTrue(CountlyConsentManager.sharedInstance().requiresConsent, "without behavior settings the developer's consent requirement applies")
        XCTAssertEqual(7, CountlyPersistency.sharedInstance().eventSendThreshold, "and the developer's event threshold")
        XCTAssertEqual(64, CountlyCommon.sharedInstance().maxKeyLength, "and the developer's key length limit")
        Countly.sharedInstance().halt(true)
    }

    /**
     * <pre>
     * "halt" resets the location state, so location info disabled before it does not hold for the next start.
     *
     * 1- Start and disable location info
     * 2- Halt and start again with consent required and all consents given
     * 3- Verify location info is enabled and no request carries the empty location sent for disabled location info
     * </pre>
     */
    func testHalt_resetsTheLocationState() throws {
        let config = createBaseConfig()
        config.manualSessionHandling = true
        Countly.sharedInstance().start(with: config)
        Countly.sharedInstance().disableLocationInfo()
        XCTAssertEqual(true, CountlyLocationManager.sharedInstance()?.isLocationInfoDisabled, "location info is disabled before halt")

        Countly.sharedInstance().halt(true)
        let restart = createBaseConfig()
        restart.requiresConsent = true
        restart.enableAllConsents = true
        Countly.sharedInstance().start(with: restart)

        XCTAssertEqual(false, CountlyLocationManager.sharedInstance()?.isLocationInfoDisabled, "halt must reset the location state")
        let rq = TestUtils.getCurrentRQ() ?? []
        XCTAssertTrue(rq.first?.contains("begin_session=1") == true, "the session begin must be the first request, got: \(rq)")
        for request in rq {
            let location = TestUtils.parseQueryString(request)["location"] as? String
            XCTAssertNotEqual("", location, "no request may carry the empty location of disabled location info: \(request)")
        }
    }

    /**
     * <pre>
     * "halt" gives back only what behavior settings wrote into the configuration. A value the app set itself before halt
     * stays, on the configuration given at start and on a newer one, which shares its internal limits and content parts.
     *
     * 1- Start without the consent requirement and with behavior settings that lower the key length limit
     * 2- Require consent on that configuration, and prepare a newer one with its own key length limit and content zone interval
     * 3- Halt and verify the app's values stayed, then start with each configuration and verify the app's values apply
     * </pre>
     */
    func testHalt_keepsTheValuesTheAppSetBeforeHalt() throws {
#if os(iOS)
        // the content parts are shared by every configuration in the process, like the limits the base class resets
        CountlyConfig().content().restoreZoneTimerInterval(0)
        defer { CountlyConfig().content().restoreZoneTimerInterval(0) }
#endif
        let config = createBaseConfig()
        config.manualSessionHandling = true
        config.requiresConsent = false
        config.sdkBehaviorSettings = ServerConfigBuilder().limitKeyLength(20).build()
        Countly.sharedInstance().start(with: config)
        XCTAssertEqual(20, CountlyCommon.sharedInstance().maxKeyLength, "the behavior settings lower the key length limit")

        config.requiresConsent = true
        let next = createBaseConfig()
        next.manualSessionHandling = true
        next.sdkInternalLimits().setMaxKeyLength(50)
#if os(iOS)
        next.content().setZoneTimerInterval(60)
#endif
        Countly.sharedInstance().halt(true)

        XCTAssertTrue(config.requiresConsent, "the consent requirement the app set before halt stays")
        XCTAssertEqual(50, CountlyConfig().sdkInternalLimits().getMaxKeyLength(), "and so does the key length limit of the newer configuration")
#if os(iOS)
        XCTAssertEqual(60, next.content().getZoneTimerInterval(), "and its content zone interval")
#endif

        // the property is nonnull in Swift, so the provided settings are cleared through KVC
        config.setValue(nil, forKey: "sdkBehaviorSettings")
        Countly.sharedInstance().start(with: config)
        XCTAssertTrue(CountlyConsentManager.sharedInstance().requiresConsent, "the next start requires consent, as the app asked")
        Countly.sharedInstance().halt(true)

        Countly.sharedInstance().start(with: next)
        XCTAssertEqual(50, CountlyCommon.sharedInstance().maxKeyLength, "a start with the newer configuration applies its key length limit")
#if os(iOS)
        XCTAssertEqual(60, CountlyContentBuilderInternal.sharedInstance().zoneTimerInterval, accuracy: 0.001, "and its content zone interval")
#endif
        Countly.sharedInstance().halt(true)
    }

#if os(iOS)
    /**
     * <pre>
     * The content zone interval that behavior settings gave does not outlive "halt", so a next start that applies no
     * behavior settings polls content at the default interval.
     *
     * 1- Start with behavior settings that set the content zone interval
     * 2- Halt with storage cleared and start again with behavior settings updates disabled, so none apply
     * 3- Verify content is polled at the default interval again
     * </pre>
     */
    func testHalt_contentZoneIntervalOfBehaviorSettingsDoesNotOutliveHalt() throws {
        // the content parts are shared by every configuration in the process, so an interval an earlier test set is cleared
        CountlyConfig().content().restoreZoneTimerInterval(0)
        let config = createBaseConfig()
        config.manualSessionHandling = true
        config.sdkBehaviorSettings = ServerConfigBuilder().contentZoneInterval(60).build()
        Countly.sharedInstance().start(with: config)
        XCTAssertEqual(60, CountlyContentBuilderInternal.sharedInstance().zoneTimerInterval, accuracy: 0.001, "the behavior settings set the interval")

        Countly.sharedInstance().halt(true)
        let restart = createBaseConfig()
        restart.manualSessionHandling = true
        restart.disableSDKBehaviorSettingsUpdates = true
        Countly.sharedInstance().start(with: restart)

        XCTAssertEqual(30, CountlyContentBuilderInternal.sharedInstance().zoneTimerInterval, accuracy: 0.001, "without behavior settings the default interval applies")
    }
#endif

    /**
     * <pre>
     * A header added at runtime belongs to that run. It is not written into the app's URL session configuration, so a
     * next start with the same configuration, for the next user after a logout for example, does not send it.
     *
     * 1- Start with a URL session configuration and add an authorization header at runtime
     * 2- Verify the URL session configuration the start configuration holds was left as the app set it
     * 3- Halt with storage cleared, start again with the same configuration, and verify an immediate request goes without the header
     * </pre>
     */
    func testHalt_headersAddedAtRuntimeAreNotSentByTheNextStart() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        TestURLProtocol.reset()
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [TestURLProtocol.self]
        let config = createBaseConfig()
        config.manualSessionHandling = true
        config.urlSessionConfiguration = sessionConfig
        Countly.sharedInstance().start(with: config)

        Countly.sharedInstance().addCustomNetworkRequestHeaders(["Authorization": "Bearer user-a"])
        XCTAssertEqual("Bearer user-a", CountlyConnectionManager.sharedInstance().urlSessionConfiguration?.httpAdditionalHeaders?["Authorization"] as? String, "the header applies to this run")
        XCTAssertNil(config.urlSessionConfiguration.httpAdditionalHeaders?["Authorization"], "the URL session configuration of the start configuration is left as the app set it")

        Countly.sharedInstance().halt(true)
        TestURLProtocol.reset()
        Countly.sharedInstance().start(with: config)
        let downloaded = XCTestExpectation(description: "the remote config download")
        Countly.sharedInstance().remoteConfig().downloadKeys { _, _, _, _ in downloaded.fulfill() }
        wait(for: [downloaded], timeout: TestUtils.asyncTimeout)

        let headers = try XCTUnwrap(TestURLProtocol.capturedHeaders(forRequestContaining: "method=rc"), "the download must be intercepted")
        XCTAssertNil(headers["Authorization"], "the next start must not send the previous run's header")
    }

    /**
     * <pre>
     * "halt" with storage cleared removes only the SDK's own values from the standard user defaults: the current ones and
     * those older SDK versions kept, which an app updated from such a version still has. The app's own values stay, and
     * so does the PLCrashReporter suppression marker, so a crash between halt and the next start is still discarded.
     * </pre>
     */
    func testHalt_clearingStorageRemovesOnlyTheSDKsOwnUserDefaults() throws {
        let appKey = "ly.count.tests.appOwnValue"
        let markerKey = "kCountlyPLCrashCaptureSuppressedSinceKey"
        let olderVersionKeys = ["kCountlyRemoteConfigPersistencyKey", "kCountlyRemoteConfigPersistencyKeyMeta", "kCountlyTVOSNSUDKey"]
        UserDefaults.standard.set("app value", forKey: appKey)
        UserDefaults.standard.set(Date(), forKey: markerKey)
        olderVersionKeys.forEach { UserDefaults.standard.set(Data("stored by an older version".utf8), forKey: $0) }
        defer { ([appKey, markerKey] + olderVersionKeys).forEach { UserDefaults.standard.removeObject(forKey: $0) } }

        let config = createBaseConfig()
        config.manualSessionHandling = true
        Countly.sharedInstance().start(with: config)
        XCTAssertNotNil(UserDefaults.standard.object(forKey: "kCountlyStoredDeviceIDKey"), "the SDK stores its device ID in the standard user defaults")

        Countly.sharedInstance().halt(true)

        XCTAssertEqual("app value", UserDefaults.standard.string(forKey: appKey), "the app's own value must survive halt")
        XCTAssertNotNil(UserDefaults.standard.object(forKey: markerKey), "the PLCrashReporter suppression marker must survive halt")
        XCTAssertNil(UserDefaults.standard.object(forKey: "kCountlyStoredDeviceIDKey"), "the SDK's own values must be removed")
        for key in olderVersionKeys {
            XCTAssertNil(UserDefaults.standard.object(forKey: key), "[\(key)] was stored by an older SDK version, so halt must remove it too")
        }
    }

    /**
     * <pre>
     * "halt" finishes resetting the health tracker before it returns. The reset runs on the tracker's own queue, and one
     * still running while halt drops the shared state uses objects halt has already freed.
     *
     * 1- Start and count a warning in the health tracker
     * 2- Halt while a logger holds the tracker's reset for a moment
     * 3- Verify the count is cleared by the time halt returns
     * </pre>
     */
    func testHalt_waitsForTheHealthTrackerReset() throws {
        let logger = DelayingLogger(delaying: "clearing counters", by: 0.5)
        let config = createBaseConfig()
        config.manualSessionHandling = true
        config.loggerDelegate = logger
        Countly.sharedInstance().start(with: config)
        let tracker = try XCTUnwrap(CountlyHealthTracker.sharedInstance())
        tracker.logWarning()
        TestUtils.waitUntil("the warning is counted") { (tracker.value(forKey: "countLogWarning") as? Int ?? 0) > 0 }

        logger.arm()
        Countly.sharedInstance().halt(true)

        XCTAssertEqual(0, tracker.value(forKey: "countLogWarning") as? Int, "the health tracker is reset by the time halt returns")
    }

    func testPerformanceExample() async throws {
        // This is an example of a performance test case.
        measure {
            // Put the code you want to measure the time of here.
        }
    }
    
    
    func checkPersistentValues() {
        let countlyPersistency =  CountlyPersistency.sharedInstance()
        if(countlyPersistency != nil) {
            if let queuedRequests = CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? NSMutableArray,
               let recordedEvents =  CountlyPersistency.sharedInstance().value(forKey: "recordedEvents") as? NSMutableArray,
               let startedEvents =  CountlyPersistency.sharedInstance().value(forKey: "startedEvents") as? NSMutableDictionary,
               let isQueueBeingModified =  CountlyPersistency.sharedInstance().value(forKey: "isQueueBeingModified") as? Bool {
                print("Successfully access private properties.")
                
                
            }
            else {
                print("Failed to access private properties.")
            }
        }
        
    }
}



