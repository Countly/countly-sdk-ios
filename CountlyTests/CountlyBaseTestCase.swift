//
//  CountlyBaseTestCase.swift
//  CountlyTests
//
//  Created by Muhammad Junaid Akram on 27/12/2023.
//  Copyright © 2023 Alin Radut. All rights reserved.
//

import XCTest
@testable import Countly

class CountlyBaseTestCase: XCTestCase {
    var countly: Countly!
    var deviceID: String = ""
    
    override func setUpWithError() throws {
        Countly.sharedInstance().halt()
        // Put setup code here. This method is called before the invocation of each test method in the class.
        let config: CountlyConfig = CountlyConfig()
        config.appKey = "58594c9a3f461ebc000761a68c2146659ef75ea0"
        config.host = "https://master.count.ly/"
        config.enableDebug = true
        //        config.eventSendThreshold = 0
        
        deviceID = String(Int.random(in: 0..<100))
        config.deviceID = deviceID
        config.features = [CLYFeature.crashReporting];
        countly = Countly();
        countly.start(with: config)
        //         let queuedRequests = CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? NSMutableArray
        
        
    }
    
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        CountlyConnectionManager.sharedInstance().sendEvents();
        let expectation = self.expectation(description: "Async Operation")
        
        // Assuming you have an asynchronous operation to perform, like a network request or async function call
        yourAsyncOperation { result in
            // Handle the result or cleanup
            expectation.fulfill()
        }
        
        // Wait for the asynchronous operation to complete (or fail after a timeout)
        waitForExpectations(timeout: 11) { error in
            if let error = error {
                XCTFail("Error waiting for expectations: \(error)")
            }
        }
        cleanupState()
    }
    
    func yourAsyncOperation(completion: @escaping (Result<Void, Error>) -> Void) {
        // Perform your asynchronous operation
        // Call the completion handler when the operation is done
        // You can replace this with your actual asynchronous code
        DispatchQueue.global().async {
            // Simulating an async operation
            Thread.sleep(forTimeInterval: 10)
            completion(.success(()))
        }
    }
    
    func cleanupState() {
        Countly.sharedInstance().halt()
    }
    
}
