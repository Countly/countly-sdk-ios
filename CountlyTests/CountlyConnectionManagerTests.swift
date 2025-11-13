//
//  CountlyConnectionManagerTests.swift
//  CountlyTests
//
//  Created by Arif Burak Demiray on 13.05.2024.
//  Copyright © 2024 Countly. All rights reserved.
//

import XCTest
@testable import Countly

class CountlyConnectionManagerTests: CountlyBaseTestCase {

    
    override func setUp() {
        super.setUp()
        // Initialize or reset necessary objects here
        Countly.sharedInstance().halt(true)
    }

    override func tearDown() {
        // Ensure everything is cleaned up properly
        super.tearDown()
        Countly.sharedInstance().halt(true)
    }
    /**
     * <pre>
     * 1- Init countly with the limit of 250 requests
     *  - Check RQ is empty
     * 2- Add 300 requests
     *  - Check if the first 50 requests are removed
     *  - Check size is 250
     * 3- Stop the countly
     * 4 - Init countly with the limit of 10 requests
     *  - Check RQ is 250
     * 5- Add 20 requests
     *  - On every request addition queue should be dropped to the limit of 10
     *  - On first one queue should be dropped to the 150
     *  - On second one queue should be dropped to the 50
     *  - On third one queue should be dropped to the 10
     *  - On the last one queue should be size of 10
     *  </pre>
     */
    func test_addRequest_maxQueueSizeLimit_Scenario() throws {
        let config = createBaseConfig()
        config.storedRequestsLimit = 250
        config.manualSessionHandling = true
        // No Device ID provided during init
        Countly.sharedInstance().start(with: config)
        
        XCTAssertEqual(0, CountlyPersistency.sharedInstance().remainingRequestCount())
        
        addRequests(count: 300)
        XCTAssertEqual(250, CountlyPersistency.sharedInstance().remainingRequestCount())
        
        Countly.sharedInstance().halt(false)
        config.storedRequestsLimit = 10
        Countly.sharedInstance().start(with: config)
        
        XCTAssertEqual(250, CountlyPersistency.sharedInstance().remainingRequestCount())
        
        addRequests(count: 1)
        XCTAssertEqual(150, CountlyPersistency.sharedInstance().remainingRequestCount())
        
        addRequests(count: 1)
        XCTAssertEqual(50, CountlyPersistency.sharedInstance().remainingRequestCount())
        
        addRequests(count: 1)
        XCTAssertEqual(10, CountlyPersistency.sharedInstance().remainingRequestCount())
        
        addRequests(count: 17)
        XCTAssertEqual(10, CountlyPersistency.sharedInstance().remainingRequestCount())
        
        Countly.sharedInstance().halt(true)
        
    }
    
    func test_addCustomNetworkRequestHeaders() throws {
        let config = createBaseConfig()
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.protocolClasses = [TestURLProtocol.self]
        config.urlSessionConfiguration = sessionConfig
        
        Countly.sharedInstance().start(with: config)
        // Add custom headers through the Objective-C API
        let customHeaders: [String: String] = [
            "Authorization": "Bearer 123",
            "X-Test": "Value1"
        ]
        
        Countly.sharedInstance().addCustomNetworkRequestHeaders(customHeaders)
        Countly.sharedInstance().addDirectRequest(["test": "request"])
        
        TestUtils.sleep(2) {}
        
        let captured = TestURLProtocol.capturedHeaders()
        XCTAssertEqual(captured?["Authorization"], "Bearer 123")
        XCTAssertEqual(captured?["X-Test"], "Value1")
        XCTAssertEqual(captured?.count, 2)
    }
    
    func test_addCustomNetworkRequestHeaders_override() throws {
        let config = createBaseConfig()
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.protocolClasses = [TestURLProtocol.self]
        sessionConfig.httpAdditionalHeaders = ["X-Test": "Value0"]
        config.urlSessionConfiguration = sessionConfig
        
       
        Countly.sharedInstance().start(with: config)
        // Add custom headers through the Objective-C API
        
        TestUtils.sleep(1) {}
        let captured = TestURLProtocol.capturedHeaders()
        XCTAssertEqual(captured?["X-Test"], "Value0")
        XCTAssertEqual(captured?.count, 1)
        
        let customHeaders: [String: String] = [
            "Authorization": "Bearer 123",
            "X-Test": "Value1"
        ]
        
        Countly.sharedInstance().addCustomNetworkRequestHeaders(customHeaders)
        Countly.sharedInstance().addDirectRequest(["test": "request"])
        
        TestUtils.sleep(2) {
            let captured = TestURLProtocol.capturedHeaders()
            XCTAssertEqual(captured?["Authorization"], "Bearer 123")
            XCTAssertEqual(captured?["X-Test"], "Value1")
            XCTAssertEqual(captured?.count, 2)
        }
    }
    
    func test_addCustomNetworkRequestHeaders_invalid() throws {
        let config = createBaseConfig()
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.protocolClasses = [TestURLProtocol.self]
        config.urlSessionConfiguration = sessionConfig
        
        Countly.sharedInstance().start(with: config)
        // Add custom headers through the Objective-C API
        let customHeaders: [String: String] = [
            "Authorization": "",
            "": "Value1"
        ]
        
        Countly.sharedInstance().addCustomNetworkRequestHeaders(customHeaders)
        Countly.sharedInstance().addDirectRequest(["test": "request"])
        
        TestUtils.sleep(2) {}
        
        let captured = TestURLProtocol.capturedHeaders()
        XCTAssertEqual(captured?.count, 1)
    }
    
    func addRequests(count: Int) {
        for loop in 0...count-1 {
            CountlyPersistency.sharedInstance().add(toQueue: "&request=REQUEST\(loop)")
        }
        CountlyPersistency.sharedInstance().saveToFileSync()
    }
}
