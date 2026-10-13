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



