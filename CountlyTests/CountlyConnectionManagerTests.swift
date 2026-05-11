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
        TestURLProtocol.reset()
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
    
    /**
     * addCustomNetworkRequestHeaders after SDK init
     * validate that added network headers are existing with outgoing requests
     * intercept request with a test protocol and validate existance of 2 added headers
     */
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
    
    /**
     * addCustomNetworkRequestHeaders after SDK init and while initializing the SDK
     * validate that added network headers are existing with outgoing requests and 1 header overridden by post-init headers
     * after SDK init validate that given 1 header exists
     * intercept request with a test protocol and validate existance of 2 added headers and validate one header is overridden
     */
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
    
    /**
     * addCustomNetworkRequestHeaders after SDK init invalid
     * validate that added network headers are existing with outgoing requests and 1 header not there because it is invalid
     * intercept request with a test protocol and validate that only 1 header exists
     */
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
    
    /**
     * <pre>
     * Test that all outgoing requests use GET method by default
     * when alwaysUsePOST is false and query strings are short.
     *
     * 1- Init SDK with MockURLProtocol, alwaysUsePOST = false
     * 2- Call all possible SDK functions: sessions, events, user details,
     *    location, direct request, attribution, views, crashes, APM, remote config, rating, feedbacks
     * 3- Wait for requests to be sent
     * 4- Verify all intercepted requests use GET method
     * 5- Verify request URL contains query string (no HTTP body)
     * </pre>
     */
    func test_allRequests_useGET_whenAlwaysUsePOSTDisabled() {
        let expectation = self.expectation(description: "Requests intercepted")
        expectation.assertForOverFulfill = false

        let expectedMinimumRequests = 10
        var capturedRequests: [URLRequest] = []
        let lock = NSLock()
        MockURLProtocol.requestHandler = { request in
            lock.lock()
            capturedRequests.append(request)
            if capturedRequests.count >= expectedMinimumRequests {
                expectation.fulfill()
            }
            lock.unlock()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            let body = "{\"result\":[]}".data(using: .utf8)!
            return (body, response, nil)
        }

        let config = createBaseConfig()
        config.alwaysUsePOST = false
        config.manualSessionHandling = true
        config.disableSDKBehaviorSettingsUpdates = true
        config.enablePerformanceMonitoring = true
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        config.urlSessionConfiguration = sessionConfig

        Countly.sharedInstance().start(with: config)

        // Session begin
        Countly.sharedInstance().beginSession()

        // Events
        Countly.sharedInstance().recordEvent("test_event_1")
        Countly.sharedInstance().recordEvent("test_event_2", segmentation: ["key": "value"], count: 1, sum: 1.5, duration: 10)

        // User details
        Countly.user().set("custom_property", value: "custom_value")
        Countly.user().increment("login_count")
        Countly.user().push("tags", value: "vip")
        Countly.user().save()

        // Location
        Countly.sharedInstance().recordLocation(CLLocationCoordinate2D(latitude: 41.0082, longitude: 28.9784), city: "Istanbul", isoCountryCode: "TR", ip: "1.2.3.4")

        // Direct request
        Countly.sharedInstance().addDirectRequest(["custom_key": "custom_value"])

        // Attribution
        Countly.sharedInstance().recordDirectAttribution(withCampaignType: "_special_test", andCampaignData: "{\"cid\":\"test_campaign\"}")
        Countly.sharedInstance().recordIndirectAttribution(["idfa": "test_idfa_value"])

        // Views
        let _ = Countly.sharedInstance().views().startAutoStoppedView("TestView")
        let _ = Countly.sharedInstance().views().startView("TestView2")
        Countly.sharedInstance().views().stopView(withName: "TestView2")

        // Crash/Error reporting
        Countly.sharedInstance().recordError("TestError", isFatal: false, stackTrace: ["frame1", "frame2"], segmentation: ["errorType": "test"])

        // Performance monitoring (APM)
        Countly.sharedInstance().recordNetworkTrace("test_trace", requestPayloadSize: 100, responsePayloadSize: 200, responseStatusCode: 200, startTime: 1111, endTime: 2222)

        // Remote config
        Countly.sharedInstance().remoteConfig().downloadKeys { _, _, _, _ in }
        Countly.sharedInstance().remoteConfig().enrollIntoABTests(forKeys: ["test_key"])
        Countly.sharedInstance().remoteConfig().exitABTests(forKeys: ["test_key"])

        // Feedbacks and Rating (iOS only)
        #if os(iOS)
        Countly.sharedInstance().recordRatingWidget(withID: "test_widget_id", rating: 5, email: "test@test.com", comment: "Great", userCanBeContacted: true)
        Countly.sharedInstance().feedback().getAvailableFeedbackWidgets { _, _ in }
        #endif

        // Session update (flushes queued events)
        Countly.sharedInstance().updateSession()

        // Session end
        Countly.sharedInstance().endSession()

        waitForExpectations(timeout: 15)

        XCTAssertGreaterThanOrEqual(capturedRequests.count, expectedMinimumRequests, "Should have captured at least \(expectedMinimumRequests) requests from various SDK functions")
        for request in capturedRequests {
            XCTAssertEqual(request.httpMethod, "GET", "Request to \(request.url?.path ?? "") should use GET")
            XCTAssertTrue(request.url?.query?.isEmpty == false, "GET request should have query string in URL")
        }
    }

    /**
     * <pre>
     * Test that all outgoing requests use POST method
     * when alwaysUsePOST config flag is enabled.
     *
     * 1- Init SDK with MockURLProtocol, alwaysUsePOST = true
     * 2- Call all possible SDK functions: sessions, events, user details,
     *    location, direct request, attribution, views, crashes, APM, remote config, rating, feedbacks
     * 3- Wait for requests to be sent
     * 4- Verify all intercepted requests use POST method
     * 5- Verify requests have HTTP body and no query string in URL
     * </pre>
     */
    func test_allRequests_usePOST_whenAlwaysUsePOSTEnabled() {
        let expectation = self.expectation(description: "Requests intercepted")
        expectation.assertForOverFulfill = false

        let expectedMinimumRequests = 10
        var capturedRequests: [URLRequest] = []
        var capturedBodies: [Data] = []
        let lock = NSLock()
        MockURLProtocol.requestHandler = { request in
            lock.lock()
            capturedRequests.append(request)
            // Read body from stream if needed
            if let body = request.httpBody {
                capturedBodies.append(body)
            } else if let stream = request.httpBodyStream {
                stream.open()
                let bufferSize = 4096
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
                var data = Data()
                while stream.hasBytesAvailable {
                    let read = stream.read(buffer, maxLength: bufferSize)
                    if read > 0 {
                        data.append(buffer, count: read)
                    }
                }
                buffer.deallocate()
                stream.close()
                capturedBodies.append(data)
            }
            if capturedRequests.count >= expectedMinimumRequests {
                expectation.fulfill()
            }
            lock.unlock()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            let body = "{\"result\":[]}".data(using: .utf8)!
            return (body, response, nil)
        }

        let config = createBaseConfig()
        config.alwaysUsePOST = true
        config.manualSessionHandling = true
        config.disableSDKBehaviorSettingsUpdates = true
        config.enablePerformanceMonitoring = true
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        config.urlSessionConfiguration = sessionConfig

        Countly.sharedInstance().start(with: config)

        // Session begin
        Countly.sharedInstance().beginSession()

        // Events
        Countly.sharedInstance().recordEvent("test_event_1")
        Countly.sharedInstance().recordEvent("test_event_2", segmentation: ["key": "value"], count: 1, sum: 1.5, duration: 10)

        // User details
        Countly.user().set("custom_property", value: "custom_value")
        Countly.user().increment("login_count")
        Countly.user().push("tags", value: "vip")
        Countly.user().save()

        // Location
        Countly.sharedInstance().recordLocation(CLLocationCoordinate2D(latitude: 41.0082, longitude: 28.9784), city: "Istanbul", isoCountryCode: "TR", ip: "1.2.3.4")

        // Direct request
        Countly.sharedInstance().addDirectRequest(["custom_key": "custom_value"])

        // Attribution
        Countly.sharedInstance().recordDirectAttribution(withCampaignType: "_special_test", andCampaignData: "{\"cid\":\"test_campaign\"}")
        Countly.sharedInstance().recordIndirectAttribution(["idfa": "test_idfa_value"])

        // Views
        let _ = Countly.sharedInstance().views().startAutoStoppedView("TestView")
        let _ = Countly.sharedInstance().views().startView("TestView2")
        Countly.sharedInstance().views().stopView(withName: "TestView2")

        // Crash/Error reporting
        Countly.sharedInstance().recordError("TestError", isFatal: false, stackTrace: ["frame1", "frame2"], segmentation: ["errorType": "test"])

        // Performance monitoring (APM)
        Countly.sharedInstance().recordNetworkTrace("test_trace", requestPayloadSize: 100, responsePayloadSize: 200, responseStatusCode: 200, startTime: 1111, endTime: 2222)

        // Remote config
        Countly.sharedInstance().remoteConfig().downloadKeys { _, _, _, _ in }
        Countly.sharedInstance().remoteConfig().enrollIntoABTests(forKeys: ["test_key"])
        Countly.sharedInstance().remoteConfig().exitABTests(forKeys: ["test_key"])

        // Feedbacks and Rating (iOS only)
        #if os(iOS)
        Countly.sharedInstance().recordRatingWidget(withID: "test_widget_id", rating: 5, email: "test@test.com", comment: "Great", userCanBeContacted: true)
        Countly.sharedInstance().feedback().getAvailableFeedbackWidgets { _, _ in }
        #endif

        // Session update (flushes queued events)
        Countly.sharedInstance().updateSession()

        // Session end
        Countly.sharedInstance().endSession()

        waitForExpectations(timeout: 15)

        XCTAssertGreaterThanOrEqual(capturedRequests.count, expectedMinimumRequests, "Should have captured at least \(expectedMinimumRequests) requests from various SDK functions")
        for (index, request) in capturedRequests.enumerated() {
            XCTAssertEqual(request.httpMethod, "POST", "Request to \(request.url?.path ?? "") should use POST")
            XCTAssertNil(request.url?.query, "POST request URL should not contain query string")

            if index < capturedBodies.count {
                let bodyString = String(data: capturedBodies[index], encoding: .utf8) ?? ""
                XCTAssertTrue(bodyString.contains("app_key="), "POST body should contain app_key for request \(index)")
            }
        }
    }

    func addRequests(count: Int) {
        for loop in 0...count-1 {
            CountlyPersistency.sharedInstance().add(toQueue: "&request=REQUEST\(loop)")
        }
        CountlyPersistency.sharedInstance().saveToFileSync()
    }
}
