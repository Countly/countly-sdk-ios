//
//  CountlyRequestCallbackTests.swift
//  CountlyTests
//
//  Tests for the CLYRequestCallback feature.
//  These tests verify individual request callbacks work correctly.
//

import XCTest
@testable import Countly

/// Tests for request callback feature (CLYRequestCallback).
/// Uses class-level setup to start SDK once, avoiding the halt() singleton issue.
class CountlyRequestCallbackTests: XCTestCase {

    private static var isSDKStarted = false
    private static let appKey = "appkey"
    private static let host = "https://testing.count.ly/"

    override class func setUp() {
        super.setUp()
        if !isSDKStarted {
            // Configure MockURLProtocol to return valid JSON by default
            MockURLProtocol.requestHandler = { request in
                let jsonResponse = Data("{\"result\":\"Success\"}".utf8)
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (jsonResponse, response, nil)
            }

            let config = CountlyConfig()
            config.appKey = appKey
            config.host = host
            config.enableDebug = true
            config.manualSessionHandling = true
            let sessionConfig = URLSessionConfiguration.default
            sessionConfig.protocolClasses = [MockURLProtocol.self]
            config.urlSessionConfiguration = sessionConfig
            Countly.sharedInstance().start(with: config)
            isSDKStarted = true
        }
    }

    override func setUp() {
        super.setUp()
        // Reset MockURLProtocol to success handler for each test
        MockURLProtocol.requestHandler = { request in
            let jsonResponse = Data("{\"result\":\"Success\"}".utf8)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (jsonResponse, response, nil)
        }
        // Clear any leftover runnables
        CountlyConnectionManager.sharedInstance()?.clearQueueFlushRunnables()

        // Wait for any pending queue requests to complete (drain the queue)
        var waitCount = 0
        while CountlyPersistency.sharedInstance().remainingRequestCount() > 0 && waitCount < 50 {
            CountlyConnectionManager.sharedInstance()?.proceedOnQueue()
            Thread.sleep(forTimeInterval: 0.1)
            waitCount += 1
        }
    }

    override func tearDown() {
        CountlyConnectionManager.sharedInstance()?.clearQueueFlushRunnables()
        super.tearDown()
    }

    // MARK: - Helper

    private func getConnectionManager() -> CountlyConnectionManager? {
        return CountlyConnectionManager.sharedInstance()
    }

    // MARK: - Basic Functionality Tests

    /**
     * Test that a callback is executed on successful request
     * Verifies callback receives success=true and response string
     */
    func test_requestCallback_executedOnSuccess() throws {
        guard let connectionManager = getConnectionManager() else {
            XCTFail("ConnectionManager not available")
            return
        }

        let expectation = XCTestExpectation(description: "Callback executed")
        var receivedSuccess: Bool?
        var receivedResponse: String?

        connectionManager.addToQueue(withCallback: "test=request", callback: { response, success in
            receivedResponse = response
            receivedSuccess = success
            expectation.fulfill()
        })

        // Trigger queue processing
        connectionManager.proceedOnQueue()

        wait(for: [expectation], timeout: 5.0)

        XCTAssertNotNil(receivedSuccess)
        XCTAssertTrue(receivedSuccess ?? false, "Callback should receive success=true")
        XCTAssertNotNil(receivedResponse, "Callback should receive a response")
    }

    /**
     * Test that callback receives failure status on server error
     * Uses MockURLProtocol to return 500 error
     */
    func test_requestCallback_failureOnServerError() throws {
        guard let connectionManager = getConnectionManager() else {
            XCTFail("ConnectionManager not available")
            return
        }

        // Configure MockURLProtocol to return 500 error
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (Data("Internal Server Error".utf8), response, nil)
        }

        let expectation = XCTestExpectation(description: "Callback executed")
        var receivedSuccess: Bool?
        var receivedResponse: String?

        connectionManager.addToQueue(withCallback: "test=error_request", callback: { response, success in
            receivedResponse = response
            receivedSuccess = success
            expectation.fulfill()
        })

        // Trigger queue processing
        connectionManager.proceedOnQueue()

        wait(for: [expectation], timeout: 5.0)

        XCTAssertNotNil(receivedSuccess)
        XCTAssertFalse(receivedSuccess ?? true, "Callback should receive success=false on server error")
        XCTAssertNotNil(receivedResponse, "Callback should receive error response")
    }

    /**
     * Test that callback receives failure on invalid JSON response
     * Server returns 200 but with plain text (not valid JSON)
     */
    func test_requestCallback_failureOnInvalidJSON() throws {
        guard let connectionManager = getConnectionManager() else {
            XCTFail("ConnectionManager not available")
            return
        }

        // Configure MockURLProtocol to return 200 with plain text (invalid JSON)
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (Data("OK".utf8), response, nil)
        }

        let expectation = XCTestExpectation(description: "Callback executed")
        var receivedSuccess: Bool?

        connectionManager.addToQueue(withCallback: "test=invalid_json", callback: { response, success in
            receivedSuccess = success
            expectation.fulfill()
        })

        // Trigger queue processing
        connectionManager.proceedOnQueue()

        wait(for: [expectation], timeout: 5.0)

        XCTAssertNotNil(receivedSuccess)
        XCTAssertFalse(receivedSuccess ?? true, "Callback should receive success=false on invalid JSON")
    }

    /**
     * Test that callback receives failure when JSON lacks "result" key
     */
    func test_requestCallback_failureOnMissingResultKey() throws {
        guard let connectionManager = getConnectionManager() else {
            XCTFail("ConnectionManager not available")
            return
        }

        // Configure MockURLProtocol to return JSON without "result" key
        MockURLProtocol.requestHandler = { request in
            let jsonResponse = Data("{\"status\":\"ok\"}".utf8)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (jsonResponse, response, nil)
        }

        let expectation = XCTestExpectation(description: "Callback executed")
        var receivedSuccess: Bool?

        connectionManager.addToQueue(withCallback: "test=missing_result", callback: { response, success in
            receivedSuccess = success
            expectation.fulfill()
        })

        // Trigger queue processing
        connectionManager.proceedOnQueue()

        wait(for: [expectation], timeout: 5.0)

        XCTAssertNotNil(receivedSuccess)
        XCTAssertFalse(receivedSuccess ?? true, "Callback should receive success=false when JSON missing 'result' key")
    }

    // MARK: - Lifecycle Tests

    /**
     * Test that callback is only called once (removed after execution)
     */
    func test_requestCallback_calledOnlyOnce() throws {
        guard let connectionManager = getConnectionManager() else {
            XCTFail("ConnectionManager not available")
            return
        }

        var callbackCount = 0
        let expectation = XCTestExpectation(description: "Callback executed")

        connectionManager.addToQueue(withCallback: "test=once_request", callback: { response, success in
            callbackCount += 1
            expectation.fulfill()
        })

        // Trigger queue processing
        connectionManager.proceedOnQueue()

        wait(for: [expectation], timeout: 5.0)

        // Wait a bit more to ensure callback isn't called again
        TestUtils.sleep(2) {}

        XCTAssertEqual(callbackCount, 1, "Callback should be called exactly once")
    }

    /**
     * Test that callback is removed after successful execution
     * Second request should not trigger first callback
     */
    func test_requestCallback_removedAfterSuccess() throws {
        guard let connectionManager = getConnectionManager() else {
            XCTFail("ConnectionManager not available")
            return
        }

        var firstCallbackCount = 0
        var secondCallbackCount = 0
        let expectation1 = XCTestExpectation(description: "First callback executed")
        let expectation2 = XCTestExpectation(description: "Second callback executed")

        connectionManager.addToQueue(withCallback: "test=first_request", callback: { response, success in
            firstCallbackCount += 1
            expectation1.fulfill()
        })

        // Trigger queue processing for first request
        connectionManager.proceedOnQueue()

        wait(for: [expectation1], timeout: 5.0)

        // Add second request with different callback
        connectionManager.addToQueue(withCallback: "test=second_request", callback: { response, success in
            secondCallbackCount += 1
            expectation2.fulfill()
        })

        // Trigger queue processing for second request
        connectionManager.proceedOnQueue()

        wait(for: [expectation2], timeout: 5.0)

        XCTAssertEqual(firstCallbackCount, 1, "First callback should be called once")
        XCTAssertEqual(secondCallbackCount, 1, "Second callback should be called once")
    }

    /**
     * Test that callback is removed after failure execution
     */
    func test_requestCallback_removedAfterFailure() throws {
        guard let connectionManager = getConnectionManager() else {
            XCTFail("ConnectionManager not available")
            return
        }

        // Configure failure response
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (Data("Error".utf8), response, nil)
        }

        var callbackCount = 0
        let expectation = XCTestExpectation(description: "Callback executed")

        connectionManager.addToQueue(withCallback: "test=failure_request", callback: { response, success in
            callbackCount += 1
            expectation.fulfill()
        })

        // Trigger queue processing
        connectionManager.proceedOnQueue()

        wait(for: [expectation], timeout: 5.0)

        // Wait to ensure no second call
        TestUtils.sleep(2) {}

        XCTAssertEqual(callbackCount, 1, "Callback should be called exactly once even on failure")
    }

    // MARK: - Multiple Callbacks Tests

    /**
     * Test multiple callbacks for different requests all execute
     */
    func test_multipleRequestCallbacks_allExecuted() throws {
        guard let connectionManager = getConnectionManager() else {
            XCTFail("ConnectionManager not available")
            return
        }

        var callback1Executed = false
        var callback2Executed = false
        var callback3Executed = false
        let expectation = XCTestExpectation(description: "All callbacks")
        expectation.expectedFulfillmentCount = 3

        connectionManager.addToQueue(withCallback: "test=request1", callback: { response, success in
            callback1Executed = true
            expectation.fulfill()
        })

        connectionManager.addToQueue(withCallback: "test=request2", callback: { response, success in
            callback2Executed = true
            expectation.fulfill()
        })

        connectionManager.addToQueue(withCallback: "test=request3", callback: { response, success in
            callback3Executed = true
            expectation.fulfill()
        })

        // Trigger queue processing
        connectionManager.proceedOnQueue()

        wait(for: [expectation], timeout: 15.0)

        XCTAssertTrue(callback1Executed, "Callback 1 should have executed")
        XCTAssertTrue(callback2Executed, "Callback 2 should have executed")
        XCTAssertTrue(callback3Executed, "Callback 3 should have executed")
    }

    /**
     * Test callbacks execute in queue order (FIFO)
     */
    func test_multipleRequestCallbacks_executeInOrder() throws {
        guard let connectionManager = getConnectionManager() else {
            XCTFail("ConnectionManager not available")
            return
        }

        var executionOrder: [Int] = []
        let lock = NSLock()
        let expectation = XCTestExpectation(description: "All callbacks executed")
        expectation.expectedFulfillmentCount = 3

        connectionManager.addToQueue(withCallback: "test=order1", callback: { response, success in
            lock.lock()
            executionOrder.append(1)
            lock.unlock()
            expectation.fulfill()
        })

        connectionManager.addToQueue(withCallback: "test=order2", callback: { response, success in
            lock.lock()
            executionOrder.append(2)
            lock.unlock()
            expectation.fulfill()
        })

        connectionManager.addToQueue(withCallback: "test=order3", callback: { response, success in
            lock.lock()
            executionOrder.append(3)
            lock.unlock()
            expectation.fulfill()
        })

        // Trigger queue processing
        connectionManager.proceedOnQueue()

        wait(for: [expectation], timeout: 15.0)

        XCTAssertEqual(executionOrder, [1, 2, 3], "Callbacks should execute in FIFO order")
    }

    // MARK: - Error Scenarios

    /**
     * Test callback on 400 Bad Request
     */
    func test_requestCallback_400_badRequest() throws {
        guard let connectionManager = getConnectionManager() else {
            XCTFail("ConnectionManager not available")
            return
        }

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 400,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (Data("Bad Request".utf8), response, nil)
        }

        let expectation = XCTestExpectation(description: "Callback executed")
        var receivedSuccess: Bool?

        connectionManager.addToQueue(withCallback: "test=bad_request", callback: { response, success in
            receivedSuccess = success
            expectation.fulfill()
        })

        // Trigger queue processing
        connectionManager.proceedOnQueue()

        wait(for: [expectation], timeout: 5.0)

        XCTAssertFalse(receivedSuccess ?? true, "Callback should receive failure on 400")
    }

    /**
     * Test callback on 404 Not Found
     */
    func test_requestCallback_404_notFound() throws {
        guard let connectionManager = getConnectionManager() else {
            XCTFail("ConnectionManager not available")
            return
        }

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (Data("Not Found".utf8), response, nil)
        }

        let expectation = XCTestExpectation(description: "Callback executed")
        var receivedSuccess: Bool?

        connectionManager.addToQueue(withCallback: "test=notfound", callback: { response, success in
            receivedSuccess = success
            expectation.fulfill()
        })

        // Trigger queue processing
        connectionManager.proceedOnQueue()

        wait(for: [expectation], timeout: 5.0)

        XCTAssertFalse(receivedSuccess ?? true, "Callback should receive failure on 404")
    }

    /**
     * Test callback on 503 Service Unavailable
     */
    func test_requestCallback_503_serviceUnavailable() throws {
        guard let connectionManager = getConnectionManager() else {
            XCTFail("ConnectionManager not available")
            return
        }

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 503,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (Data("Service Unavailable".utf8), response, nil)
        }

        let expectation = XCTestExpectation(description: "Callback executed")
        var receivedSuccess: Bool?

        connectionManager.addToQueue(withCallback: "test=unavailable", callback: { response, success in
            receivedSuccess = success
            expectation.fulfill()
        })

        // Trigger queue processing
        connectionManager.proceedOnQueue()

        wait(for: [expectation], timeout: 5.0)

        XCTAssertFalse(receivedSuccess ?? true, "Callback should receive failure on 503")
    }

    // MARK: - Integration Tests

    /**
     * Test that request callback and queue flush runnable both execute
     */
    func test_requestCallback_andQueueFlushRunnable_bothExecute() throws {
        guard let connectionManager = getConnectionManager() else {
            XCTFail("ConnectionManager not available")
            return
        }

        var callbackExecuted = false
        var runnableExecuted = false
        let callbackExpectation = XCTestExpectation(description: "Callback executed")

        // Add a queue flush runnable
        connectionManager.addQueueFlushRunnable {
            runnableExecuted = true
        }

        // Add request with callback
        connectionManager.addToQueue(withCallback: "test=combined", callback: { response, success in
            callbackExecuted = true
            callbackExpectation.fulfill()
        })

        // Trigger queue processing
        connectionManager.proceedOnQueue()

        wait(for: [callbackExpectation], timeout: 5.0)

        // Give runnable time to execute
        TestUtils.sleep(1) {}

        XCTAssertTrue(callbackExecuted, "Request callback should have executed")
        XCTAssertTrue(runnableExecuted, "Queue flush runnable should have executed")
    }

    /**
     * Test that callback failure prevents queue flush runnable from executing
     */
    func test_requestCallback_failure_preventsQueueFlushRunnable() throws {
        guard let connectionManager = getConnectionManager() else {
            XCTFail("ConnectionManager not available")
            return
        }

        // Configure failure response
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (Data("Error".utf8), response, nil)
        }

        var callbackExecuted = false
        var runnableExecuted = false
        let callbackExpectation = XCTestExpectation(description: "Callback executed")

        // Add a queue flush runnable
        connectionManager.addQueueFlushRunnable {
            runnableExecuted = true
        }

        // Add request with callback (will fail)
        connectionManager.addToQueue(withCallback: "test=failing", callback: { response, success in
            callbackExecuted = true
            callbackExpectation.fulfill()
        })

        // Trigger queue processing
        connectionManager.proceedOnQueue()

        wait(for: [callbackExpectation], timeout: 5.0)

        // Give time for runnable to potentially execute
        TestUtils.sleep(2) {}

        XCTAssertTrue(callbackExecuted, "Request callback should have executed")
        XCTAssertFalse(runnableExecuted, "Queue flush runnable should NOT have executed due to failure")
    }

    /**
     * Test callback with 201 Created success code
     */
    func test_requestCallback_201_created_success() throws {
        guard let connectionManager = getConnectionManager() else {
            XCTFail("ConnectionManager not available")
            return
        }

        MockURLProtocol.requestHandler = { request in
            let jsonResponse = Data("{\"result\":\"Created\"}".utf8)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 201,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (jsonResponse, response, nil)
        }

        let expectation = XCTestExpectation(description: "Callback executed")
        var receivedSuccess: Bool?

        connectionManager.addToQueue(withCallback: "test=create", callback: { response, success in
            receivedSuccess = success
            expectation.fulfill()
        })

        // Trigger queue processing
        connectionManager.proceedOnQueue()

        wait(for: [expectation], timeout: 5.0)

        XCTAssertTrue(receivedSuccess ?? false, "Callback should receive success on 201")
    }
}
