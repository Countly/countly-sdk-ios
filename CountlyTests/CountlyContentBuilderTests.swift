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
        // Reset reload-on-stall / zoom state so it can't leak into later tests.
        CountlyContentBuilderInternal.sharedInstance().enableContentReloadOnStall = false
        CountlyContentBuilderInternal.sharedInstance().contentReloadOnStallTimeout = 0
        CountlyContentBuilderInternal.sharedInstance().disableZoom = false
        CountlyContentBuilderInternal.sharedInstance().contentURLHandler = nil
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

    /**
     * <pre>
     * Content reload-on-stall configuration plumbs through to the internal builder.
     *
     * 1- A fresh CountlyContentConfig defaults the stall timeout to 1000 ms and reload disabled
     * 2- enableContentReloadOnStall and setContentReloadOnStallTimeout: round-trip on the config
     * 3- After start, the internal builder reflects the enabled flag and the timeout
     *    converted from milliseconds to seconds (2500 ms -> 2.5 s)
     * </pre>
     */
    func test_contentReloadOnStall_configDefaultsAndPlumbing() {
        // 1- Fresh config object: default 1000 ms, reload disabled.
        let freshContent = CountlyContentConfig()
        XCTAssertEqual(freshContent.getContentReloadOnStallTimeout(), 1000)
        XCTAssertFalse(freshContent.getEnableContentReloadOnStall())

        // 2- Round-trip on the config used for start.
        let config = createContentTestConfig()
        config.content().setContentReloadOnStallTimeout(2500)
        config.content().enableContentReloadOnStall()
        XCTAssertEqual(config.content().getContentReloadOnStallTimeout(), 2500)
        XCTAssertTrue(config.content().getEnableContentReloadOnStall())

        // 3- Plumbed to the internal builder on start, converted ms -> seconds.
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return ("{}".data(using: .utf8)!, response, nil)
        }
        Countly.sharedInstance().start(with: config)
        XCTAssertTrue(CountlyContentBuilderInternal.sharedInstance().enableContentReloadOnStall)
        XCTAssertEqual(CountlyContentBuilderInternal.sharedInstance().contentReloadOnStallTimeout, 2.5, accuracy: 0.0001)
    }

    /**
     * <pre>
     * disableZoom is a one-way config switch that plumbs through to the internal builder.
     *
     * 1- A fresh CountlyContentConfig has zoom enabled (disableZoom == false)
     * 2- disableZoom() turns it on and round-trips on the config
     * 3- After start, the internal builder reflects it
     * </pre>
     */
    func test_disableZoom_configDefaultsAndPlumbing() {
        // 1- Fresh config: zoom NOT disabled by default.
        XCTAssertFalse(CountlyContentConfig().getDisableZoom())

        // 2- One-way switch round-trips on the config used for start.
        let config = createContentTestConfig()
        config.content().disableZoom()
        XCTAssertTrue(config.content().getDisableZoom())

        // 3- Plumbed to the internal builder on start.
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return ("{}".data(using: .utf8)!, response, nil)
        }
        Countly.sharedInstance().start(with: config)
        XCTAssertTrue(CountlyContentBuilderInternal.sharedInstance().disableZoom)
    }

    /**
     * <pre>
     * A content URL handler set on the config plumbs through to the internal builder.
     *
     * 1- A fresh CountlyContentConfig has no handler by default
     * 2- setContentURLHandler: round-trips on the config
     * 3- After start, the internal builder holds the handler
     * </pre>
     */
    func test_contentURLHandler_configDefaultsAndPlumbing() {
        XCTAssertNil(CountlyContentConfig().getContentURLHandler())

        let config = createContentTestConfig()
        let handler: (URL) -> Bool = { _ in true }
        config.content().setContentURLHandler(handler)
        XCTAssertNotNil(config.content().getContentURLHandler())

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return ("{}".data(using: .utf8)!, response, nil)
        }
        Countly.sharedInstance().start(with: config)
        XCTAssertNotNil(CountlyContentBuilderInternal.sharedInstance().contentURLHandler)
    }

    /**
     * <pre>
     * The single-content presentation latch rejects a second concurrent presentation.
     *
     * Two content fetches completing near-simultaneously used to both pass the "already
     * shown" guard (the flag was only set once the web view was presented, after a network
     * round trip) and present two overlapping web views. tryBeginContentPresentation is an
     * atomic test-and-set that closes that window.
     *
     * 1- From a clean state, the first presentation acquires the slot
     * 2- A second presentation while the slot is held is rejected
     * 3- After the shown content is dismissed, the slot is free again
     * </pre>
     */
    func test_contentPresentationLatch_rejectsSecondConcurrentPresentation() {
        let cb = CountlyContentBuilderInternal.sharedInstance()
        cb.resetInstance()  // known "not shown" state

        XCTAssertTrue(cb.tryBeginContentPresentation(), "first presentation should acquire the slot")
        XCTAssertFalse(cb.tryBeginContentPresentation(), "second concurrent presentation must be rejected")
        XCTAssertTrue(cb.isContentShownThreadSafe())

        cb.endContentPresentation()
        // endContentPresentation is async on the serial content queue; the subsequent sync
        // read drains the queue (FIFO), so the slot reads free.
        XCTAssertFalse(cb.isContentShownThreadSafe())
        XCTAssertTrue(cb.tryBeginContentPresentation(), "slot should be free again after dismissal")

        cb.endContentPresentation()
        XCTAssertFalse(cb.isContentShownThreadSafe())
    }

    /**
     * <pre>
     * resetInstance releases the content slot through the serial content queue.
     *
     * The flag write in resetInstance must go through the same queue as every other accessor
     * (not a raw ivar write), so a reset cannot race a concurrent claim and cannot leave the
     * slot stuck "shown" (which would silently disable the content zone).
     *
     * 1- Claim the slot
     * 2- resetInstance
     * 3- The slot reads free (a subsequent claim succeeds)
     * </pre>
     */
    func test_resetInstance_releasesContentSlot() {
        let cb = CountlyContentBuilderInternal.sharedInstance()
        cb.resetInstance()

        XCTAssertTrue(cb.tryBeginContentPresentation())
        XCTAssertTrue(cb.isContentShownThreadSafe())

        cb.resetInstance()
        XCTAssertFalse(cb.isContentShownThreadSafe())
        XCTAssertTrue(cb.tryBeginContentPresentation(), "slot should be claimable again after reset")

        cb.endContentPresentation()
    }

    // MARK: - Rotation

    /// disableRotation is a one-way switch that defaults to off and plumbs through to the builder.
    func test_disableRotation_configDefaultsAndPlumbing() {
        XCTAssertFalse(CountlyContentConfig().getDisableRotation())

        let config = createContentTestConfig()
        config.content().disableRotation()
        XCTAssertTrue(config.content().getDisableRotation())

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return ("{}".data(using: .utf8)!, response, nil)
        }
        Countly.sharedInstance().start(with: config)
        XCTAssertTrue(CountlyContentBuilderInternal.sharedInstance().disableRotation)

        CountlyContentBuilderInternal.sharedInstance().disableRotation = false
    }

    // MARK: - exitContentZone closes displayed content

    /// Waits for pending main-queue work (FIFO), so a deferred teardown has completed.
    private func drainMainQueue(_ description: String = "main queue drained") {
        let marker = expectation(description: description)
        DispatchQueue.main.async { marker.fulfill() }
        waitForExpectations(timeout: 2)
    }

    /// exitContentZone must release the shown slot, or every later enter silently no-ops.
    func test_exitContentZone_releasesShownSlot_soTheZoneIsNotDeadEnded() {
        let cb = CountlyContentBuilderInternal.sharedInstance()
        cb.resetInstance()

        XCTAssertTrue(cb.tryBeginContentPresentation(), "content is now 'shown'")
        XCTAssertTrue(cb.isContentShownThreadSafe())

        cb.exitContentZone()
        // Deliberately NO queue drain. The slot must be free by the time exitContentZone returns,
        // otherwise an enterContentZone in the same turn hits the "already shown" guard, silently
        // no-ops, and dead-ends the zone until the process restarts.
        XCTAssertFalse(cb.isContentShownThreadSafe(), "the slot must be released synchronously on main")
        XCTAssertTrue(cb.tryBeginContentPresentation(), "a later presentation must be possible again")

        cb.endContentPresentation()
    }

    /// Closing content fires the dismiss block, which schedules the ~30s zone re-entry. An
    /// SDK-initiated close must suppress it, or the zone the app exited comes back.
    func test_exitContentZone_doesNotReArmTheZone_afterClosingDisplayedContent() {
        let cb = CountlyContentBuilderInternal.sharedInstance()
        cb.resetInstance()

        // A port nobody listens on: fails instantly, but a real web view is still created.
        let placement: [String: Any] = ["x": 0, "y": 0, "w": 200, "h": 200]
        cb.showContent(withHtmlPath: "https://localhost:1/content", placementCoordinates: ["p": placement, "l": placement])
        drainMainQueue("content presented")

        XCTAssertTrue(cb.isContentShownThreadSafe(), "content should be presented")

        cb.exitContentZone()
        drainMainQueue("content closed")
        // closeWebView defers one more turn; the dismiss block runs there.
        drainMainQueue("dismiss block ran")

        XCTAssertFalse(cb.isContentShownThreadSafe(), "the content must be gone")
        XCTAssertFalse(cb.isZoneReentryTimerArmed(), "an SDK-initiated close must not schedule a zone re-entry")

        // The only test presenting a real overlay window; a lingering one leaks into other suites.
        cb.resetInstance()
        drainMainQueue("reset settled")
    }

    /// Internal zone cycles use clearContentState so a routine config apply cannot dismiss content.
    func test_clearContentState_leavesDisplayedContentAlone() {
        let cb = CountlyContentBuilderInternal.sharedInstance()
        cb.resetInstance()

        XCTAssertTrue(cb.tryBeginContentPresentation())

        cb.clearContentState()

        XCTAssertTrue(cb.isContentShownThreadSafe(), "clearContentState must not dismiss displayed content")

        cb.endContentPresentation()
    }
}
#endif
