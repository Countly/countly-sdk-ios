//
//  CountlyContentBuilderTests.swift
//  CountlyTests
//
//  Created on 02.03.2026.
//  Copyright © 2026 Countly. All rights reserved.
//

import XCTest
@testable import Countly

#if os(iOS)
class CountlyContentBuilderTests: CountlyBaseTestCase {

    override func setUp() {
        super.setUp()
        Countly.sharedInstance().halt(true)
        MockURLProtocol.requestHandler = nil
    }

    override func tearDown() {
        CountlyContentBuilderInternal.sharedInstance().exitContentZone()
        Countly.sharedInstance().halt(true)
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Creates a config with MockURLProtocol injected, manual sessions, and server config disabled.
    func createContentTestConfig(alwaysUsePOST: Bool = false) -> CountlyConfig {
        let config = TestUtils.createBaseConfig()
        config.manualSessionHandling = true
        config.alwaysUsePOST = alwaysUsePOST
        config.disableSDKBehaviorSettingsUpdates = true

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        config.urlSessionConfiguration = sessionConfig
        return config
    }

    /// Starts SDK and enters content zone with zero initial delay to speed up tests.
    func startSDKAndEnterContentZone(alwaysUsePOST: Bool = false) {
        let config = createContentTestConfig(alwaysUsePOST: alwaysUsePOST)
        Countly.sharedInstance().start(with: config)

        // Eliminate the initial delay so content fetch fires immediately
        CountlyContentBuilderInternal.sharedInstance().contentInitialDelay = 0
        CountlyContentBuilderInternal.sharedInstance().enterContentZone([])
    }

    // MARK: - Tests

    /**
     * <pre>
     * Test that content fetch request uses GET method by default
     * when query string is short and alwaysUsePOST is false.
     *
     * 1- Init SDK with MockURLProtocol, manual sessions, alwaysUsePOST = false
     * 2- Set contentInitialDelay to 0 to avoid waiting
     * 3- Trigger enterContentZone
     * 4- Wait for the content fetch request
     * 5- Verify the intercepted request uses GET
     * 6- Verify the request URL contains /o/sdk/content endpoint
     * </pre>
     */
    func test_fetchContentRequest_usesGET_whenQueryIsShort() {
        let contentExpectation = self.expectation(description: "Content fetch request intercepted")
        contentExpectation.assertForOverFulfill = false

        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            if let url = request.url?.absoluteString, url.contains("/o/sdk/content") {
                capturedRequest = request
                contentExpectation.fulfill()
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return ("{}".data(using: .utf8)!, response, nil)
        }

        startSDKAndEnterContentZone(alwaysUsePOST: false)

        waitForExpectations(timeout: 15)

        XCTAssertNotNil(capturedRequest, "Content fetch request should have been made")
        XCTAssertEqual(capturedRequest?.httpMethod, "GET", "Content fetch should use GET for short query strings")
        XCTAssertNil(capturedRequest?.httpBody, "GET request should not have HTTP body")
        XCTAssertTrue(capturedRequest?.url?.absoluteString.contains("/o/sdk/content") ?? false, "Request URL should contain content endpoint")
    }

    /**
     * <pre>
     * Test that content fetch request uses POST method
     * when alwaysUsePOST config flag is enabled.
     *
     * 1- Init SDK with MockURLProtocol, manual sessions, alwaysUsePOST = true
     * 2- Set contentInitialDelay to 0 to avoid waiting
     * 3- Trigger enterContentZone
     * 4- Wait for the content fetch request
     * 5- Verify the intercepted request uses POST
     * 6- Verify the request has an HTTP body with query parameters
     * </pre>
     */
    func test_fetchContentRequest_usesPOST_whenAlwaysUsePOSTEnabled() {
        let contentExpectation = self.expectation(description: "Content fetch request intercepted")
        contentExpectation.assertForOverFulfill = false

        var capturedRequest: URLRequest?
        var capturedBody: Data?
        MockURLProtocol.requestHandler = { request in
            if let url = request.url?.absoluteString, url.contains("/o/sdk/content") {
                capturedRequest = request
                // Capture body from the stream if httpBody is nil
                if let body = request.httpBody {
                    capturedBody = body
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
                    capturedBody = data
                }
                contentExpectation.fulfill()
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return ("{}".data(using: .utf8)!, response, nil)
        }

        startSDKAndEnterContentZone(alwaysUsePOST: true)

        waitForExpectations(timeout: 15)

        XCTAssertNotNil(capturedRequest, "Content fetch request should have been made")
        XCTAssertEqual(capturedRequest?.httpMethod, "POST", "Content fetch should use POST when alwaysUsePOST is enabled")

        if let bodyData = capturedBody, let bodyString = String(data: bodyData, encoding: .utf8) {
            XCTAssertTrue(bodyString.contains("method=queue"), "POST body should contain content fetch method parameter")
            XCTAssertTrue(bodyString.contains("app_key="), "POST body should contain app_key")
        } else {
            XCTFail("POST request should have HTTP body")
        }

        // URL should not contain query string for POST
        XCTAssertFalse(capturedRequest?.url?.absoluteString.contains("?") ?? true, "POST request URL should not contain query string")
    }

    /**
     * <pre>
     * Test that content fetch request contains required query parameters
     * (method, resolution, la, app_key, device_id).
     *
     * 1- Init SDK with MockURLProtocol
     * 2- Set contentInitialDelay to 0 to avoid waiting
     * 3- Trigger enterContentZone
     * 4- Wait for the content fetch request
     * 5- Parse the query string and verify required parameters exist
     * </pre>
     */
    func test_fetchContentRequest_containsRequiredParameters() {
        let contentExpectation = self.expectation(description: "Content fetch request intercepted")
        contentExpectation.assertForOverFulfill = false

        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            if let url = request.url?.absoluteString, url.contains("/o/sdk/content") {
                capturedRequest = request
                contentExpectation.fulfill()
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return ("{}".data(using: .utf8)!, response, nil)
        }

        startSDKAndEnterContentZone()

        waitForExpectations(timeout: 15)

        XCTAssertNotNil(capturedRequest)

        let queryString = capturedRequest?.url?.query ?? ""
        XCTAssertTrue(queryString.contains("method=queue"), "Request should contain method=queue parameter")
        XCTAssertTrue(queryString.contains("resolution="), "Request should contain resolution parameter")
        XCTAssertTrue(queryString.contains("la="), "Request should contain language parameter")
        XCTAssertTrue(queryString.contains("app_key="), "Request should contain app_key parameter")
        XCTAssertTrue(queryString.contains("device_id="), "Request should contain device_id parameter")
    }

    /**
     * <pre>
     * Test that exiting content zone stops further fetch requests.
     *
     * 1- Init SDK with MockURLProtocol
     * 2- Set contentInitialDelay to 0 to avoid waiting
     * 3- Trigger enterContentZone, wait for first fetch
     * 4- Call exitContentZone
     * 5- Verify no more content requests are made within the next timer interval
     * </pre>
     */
    func test_exitContentZone_stopsFetching() {
        let firstFetch = self.expectation(description: "First content fetch")
        firstFetch.assertForOverFulfill = false

        var fetchCount = 0
        MockURLProtocol.requestHandler = { request in
            if let url = request.url?.absoluteString, url.contains("/o/sdk/content") {
                fetchCount += 1
                if fetchCount == 1 {
                    firstFetch.fulfill()
                }
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return ("{}".data(using: .utf8)!, response, nil)
        }

        startSDKAndEnterContentZone()

        waitForExpectations(timeout: 15)

        let countAfterFirstFetch = fetchCount
        CountlyContentBuilderInternal.sharedInstance().exitContentZone()

        // Wait a bit and verify no more requests
        TestUtils.sleep(3) {}

        XCTAssertEqual(fetchCount, countAfterFirstFetch, "No additional content fetches should occur after exitContentZone")
    }

    /**
     * <pre>
     * Reproduction + regression test for the temporary-device-ID leak.
     *
     * The content fetch is an immediate request (it bypasses the persisted request queue and its
     * temporary-ID guard) and it carries device_id. While in temporary device ID mode it must not be
     * sent, otherwise a "CLYTemporaryDeviceID" user is created on the server.
     *
     * 1- Init SDK with MockURLProtocol, then enter temporary device ID mode
     * 2- Enter content zone with zero initial delay
     * 3- Verify NO request to /o/sdk/content is made while in temporary mode (inverted expectation)
     * 4- Exit content zone, switch to a real device ID (leaving temporary mode)
     * 5- Re-enter content zone and verify the content fetch now fires normally
     * </pre>
     */
    func test_fetchContent_isBlocked_inTemporaryDeviceIDMode() {
        let noFetchInTempMode = self.expectation(description: "No content fetch while in temporary device ID mode")
        noFetchInTempMode.isInverted = true
        let fetchAfterExit = self.expectation(description: "Content fetch resumes after leaving temporary mode")
        fetchAfterExit.assertForOverFulfill = false

        var inTemporaryMode = true
        MockURLProtocol.requestHandler = { request in
            if let url = request.url?.absoluteString, url.contains("/o/sdk/content") {
                if inTemporaryMode {
                    noFetchInTempMode.fulfill()
                } else {
                    fetchAfterExit.fulfill()
                }
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return ("{}".data(using: .utf8)!, response, nil)
        }

        let config = createContentTestConfig()
        Countly.sharedInstance().start(with: config)
        Countly.sharedInstance().enableTemporaryDeviceIDMode()

        CountlyContentBuilderInternal.sharedInstance().contentInitialDelay = 0
        CountlyContentBuilderInternal.sharedInstance().enterContentZone([])

        // Phase 1: nothing should hit the content endpoint while in temporary mode
        wait(for: [noFetchInTempMode], timeout: 5)

        // Phase 2: leave temporary mode by assigning a real device ID, then re-enter the content zone
        CountlyContentBuilderInternal.sharedInstance().exitContentZone()
        inTemporaryMode = false
        Countly.sharedInstance().changeDeviceIDWithoutMerge("real_user_after_temp")

        CountlyContentBuilderInternal.sharedInstance().contentInitialDelay = 0
        CountlyContentBuilderInternal.sharedInstance().enterContentZone([])

        wait(for: [fetchAfterExit], timeout: 15)
    }
}
#endif
