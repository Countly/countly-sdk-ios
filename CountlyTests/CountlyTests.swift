//
//  CountlyTests.swift
//  CountlyTests
//
//  Created by Muhammad Junaid Akram on 22/12/2023.
//  Copyright © 2023 Countly. All rights reserved.
//

import XCTest
@testable import Countly


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
     * "halt" with storage cleared removes only the SDK's own values from the standard user defaults. The app keeps its
     * own values in the same defaults, so they must survive it.
     * </pre>
     */
    func testHalt_clearingStorageKeepsTheAppsOwnUserDefaults() throws {
        let appKey = "ly.count.tests.appOwnValue"
        UserDefaults.standard.set("app value", forKey: appKey)
        defer { UserDefaults.standard.removeObject(forKey: appKey) }

        let config = createBaseConfig()
        config.manualSessionHandling = true
        Countly.sharedInstance().start(with: config)
        XCTAssertNotNil(UserDefaults.standard.object(forKey: "kCountlyStoredDeviceIDKey"), "the SDK stores its device ID in the standard user defaults")

        Countly.sharedInstance().halt(true)

        XCTAssertEqual("app value", UserDefaults.standard.string(forKey: appKey), "the app's own value must survive halt")
        XCTAssertNil(UserDefaults.standard.object(forKey: "kCountlyStoredDeviceIDKey"), "the SDK's own values must be removed")
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



