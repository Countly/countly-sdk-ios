//
//  CountlyTests.swift
//  CountlyTests
//
//  Created by Muhammad Junaid Akram on 22/12/2023.
//  Copyright © 2023 Alin Radut. All rights reserved.
//

import XCTest
@testable import Countly


class CountlyTests: CountlyBaseTestCase {
    
    // MARK: - Configuration Tests
    
    func testCountlyInitialization() throws {
        // Test if Countly is properly initialized
        XCTAssertTrue(CountlyCommon.sharedInstance().hasStarted, "Countly initialization failed.")
    }
    
    func testReInitWithDeviceId() throws {
        
        XCTAssertTrue(CountlyCommon.sharedInstance().hasStarted, "Countly initialization failed.")
        XCTAssertTrue(Countly.sharedInstance().deviceIDType() == CLYDeviceIDType.IDFV, "Countly deviced id type should be IDFV when no device id is provided during init.")
        Countly.sharedInstance().halt(true)
        XCTAssertTrue(!CountlyCommon.sharedInstance().hasStarted, "Countly halt failed.")
        let config: CountlyConfig = CountlyConfig()
        config.appKey = appKey
        config.host = host
        config.enableDebug = true
        
        let deviceID = String(Int.random(in: 0..<100))
        config.deviceID = deviceID
        config.features = [CLYFeature.crashReporting];
        
        Countly.sharedInstance().start(with: config)
        
        
        print(Countly.sharedInstance().deviceID())
        XCTAssertTrue(CountlyCommon.sharedInstance().hasStarted, "Countly initialization failed.")
        XCTAssertTrue(Countly.sharedInstance().deviceID() == deviceID, "Countly device id not match with provided device id.")
        XCTAssertTrue(Countly.sharedInstance().deviceIDType() == CLYDeviceIDType.custom, "Countly deviced id type should be custom when device id is provided during init.")
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

