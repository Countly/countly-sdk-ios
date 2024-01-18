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
    
    func testCountlyAgainsInitialization1() throws {
        // Test if Countly is properly initialized
        print(Countly.sharedInstance().deviceID())
        XCTAssertTrue(CountlyCommon.sharedInstance().hasStarted, "Countly initialization failed.")
        XCTAssertTrue(Countly.sharedInstance().deviceID() == deviceID, "Countly initialization failed.")
    }
    func testCountlyInitialization2() throws {
        // Test if Countly is properly initialized
        print(Countly.sharedInstance().deviceID())
        XCTAssertTrue(CountlyCommon.sharedInstance().hasStarted, "Countly initialization failed.")
        XCTAssertTrue(Countly.sharedInstance().deviceIDType() == CLYDeviceIDType.custom, "Countly initialization failed.")
    }
    func testRecordHandledException() throws {
        // Test recording a handled exception
        let exception = NSException(name: NSExceptionName("MyException"), reason: "MyReason", userInfo: ["key": "value"])
        let segmentation = ["country": "Germany", "app_version": "1.0"]
        
        XCTAssertNoThrow(try countly.recordHandledException(exception, withStackTrace: Thread.callStackSymbols), "Recording handled exception should not throw an error")
        // Add assertions based on the expected behavior after recording the exception
    }
    
    func testRecordError() {
        // Test recording an error
        let segmentation = ["country": "Germany", "app_version": "1.0"]
        countly.recordError("ERROR_NAME", isFatal: true, stackTrace: Thread.callStackSymbols, segmentation: segmentation)
    }
    
    func testRecordCrashLog() {
        // Test recording a custom crash log
        countly.recordCrashLog("This is a custom crash log.")
    }
    
    func testEvent() async throws {
        // Test recording event
        countly.recordEvent("EVENT_NAME");
        checkPersistentValues()
        // TODO: It is added to wait for completion of request, need to find a correct way to handle this
        //        try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
        checkPersistentValues()
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
    }
    
    func testView() async throws {
        countly.views().startView("VIEW_NAME");
        checkPersistentValues()
        //        try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
        checkPersistentValues()
        countly.views().stopView(withName: "VIEW_NAME");
        checkPersistentValues()
        //        try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
        checkPersistentValues()
        
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
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
