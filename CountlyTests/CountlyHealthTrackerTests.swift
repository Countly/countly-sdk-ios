//
//  CountlyHealthTrackerTests.swift
//  Countly
//
//  Created by Arif Burak Demiray on 23.09.2025.
//  Copyright © 2025 Countly. All rights reserved.
//
import XCTest
@testable import Countly

class CountlyHealthTrackerTests: CountlyBaseTestCase {
    
    func testConcurrentAccessCausesCrash() {
        let iterations = 100_000
        
        let group = DispatchGroup()
        let writerQueue = DispatchQueue(label: "writer", attributes: .concurrent)
        let readerQueue = DispatchQueue(label: "reader", attributes: .concurrent)
        
        // Writer: logFailedNetworkRequest with many strings
        group.enter()
        writerQueue.async {
            for i in 0..<iterations {
                autoreleasepool {
                    let error = String(repeating: "X", count: 50) + " \(i)"
                    CountlyHealthTracker.sharedInstance().logFailedNetworkRequest(withStatusCode: 500, errorResponse: error)
                }
            }
            group.leave()
        }
        
        group.enter()
        readerQueue.async {
            for _ in 0..<iterations {
                autoreleasepool {
                    _ = CountlyHealthTracker.sharedInstance().sendHealthCheck()
                }
            }
            group.leave()
        }
        
        for t in 0..<4 {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                for i in 0..<(iterations / 2) {
                    autoreleasepool {
                        if i % 2 == 0 {
                            CountlyHealthTracker.sharedInstance().logFailedNetworkRequest(withStatusCode: 400, errorResponse: "err-\(t)-\(i)")
                        } else {
                            _ = CountlyHealthTracker.sharedInstance().sendHealthCheck()
                        }
                    }
                }
                group.leave()
            }
        }
        
        let result = group.wait(timeout: .now() + 30)
        XCTAssertEqual(result, .success, "Stress test did not complete in time")
    }
}
