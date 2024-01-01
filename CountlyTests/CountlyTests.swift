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

    func testEvent() async throws {
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
        Countly.sharedInstance().views().startView("VIEW_NAME");
        checkPersistentValues()
//        try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
        checkPersistentValues()
        Countly.sharedInstance().views().stopView(withName: "VIEW_NAME");
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
//            Countly.sharedInstance().recordEvent("TestEvent");
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
