//
//  CountlyQueueFlushRunnablesTests.swift
//  CountlyTests
//
//  Created by Arif Burak Demiray on 28.01.2026.
//  Copyright © 2026 Countly. All rights reserved.
//

import XCTest
@testable import Countly

/// Tests for queue flush runnables feature.
/// These tests use a class-level setup to start the SDK once and keep it running
/// across all tests, since halt() breaks CountlyCommon.sharedInstance recreation.
class CountlyQueueFlushRunnablesTests: XCTestCase {

    private static var isSDKStarted = false
    private static let appKey = "appkey"
    private static let host = "https://testing.count.ly/"

    override class func setUp() {
        super.setUp()
        // Start SDK once for all tests in this class
        if !isSDKStarted {
            // Configure MockURLProtocol to return valid JSON (SDK requires JSON responses)
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
        // Ensure MockURLProtocol returns success for all tests
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
        // Clear any leftover runnables from previous test
        CountlyConnectionManager.sharedInstance()?.clearQueueFlushRunnables()
    }

    override func tearDown() {
        // Clear runnables after each test
        CountlyConnectionManager.sharedInstance()?.clearQueueFlushRunnables()
        super.tearDown()
    }

    // MARK: - Helper

    private func getConnectionManager() -> CountlyConnectionManager? {
        return CountlyConnectionManager.sharedInstance()
    }

    // MARK: - Tests

    /**
     * Test adding a single queue flush runnable
     * Verify that the runnable can be added without error
     */
    func test_addQueueFlushRunnable_singleRunnable() throws {
        guard let connectionManager = getConnectionManager() else {
            XCTFail("ConnectionManager not available")
            return
        }

        var runnableExecuted = false
        connectionManager.addQueueFlushRunnable {
            runnableExecuted = true
        }

        // Runnable should not be executed yet (no queue flush)
        XCTAssertFalse(runnableExecuted)
    }

    /**
     * Test adding multiple queue flush runnables
     * Verify that multiple runnables can be registered
     */
    func test_addQueueFlushRunnable_multipleRunnables() throws {
        guard let connectionManager = getConnectionManager() else {
            XCTFail("ConnectionManager not available")
            return
        }

        var runnable1Executed = false
        var runnable2Executed = false
        var runnable3Executed = false

        connectionManager.addQueueFlushRunnable {
            runnable1Executed = true
        }
        connectionManager.addQueueFlushRunnable {
            runnable2Executed = true
        }
        connectionManager.addQueueFlushRunnable {
            runnable3Executed = true
        }

        // Runnables should not be executed yet
        XCTAssertFalse(runnable1Executed)
        XCTAssertFalse(runnable2Executed)
        XCTAssertFalse(runnable3Executed)
    }

    /**
     * Test clearing all queue flush runnables
     * Verify that clearQueueFlushRunnables removes all registered runnables
     */
    func test_clearQueueFlushRunnables() throws {
        guard let connectionManager = getConnectionManager() else {
            XCTFail("ConnectionManager not available")
            return
        }

        var runnableExecuted = false
        connectionManager.addQueueFlushRunnable {
            runnableExecuted = true
        }

        // Clear runnables before any queue processing
        connectionManager.clearQueueFlushRunnables()

        // Add a request and let it complete (queue will flush)
        Countly.sharedInstance().addDirectRequest(["test": "request"])

        TestUtils.sleep(2) {}

        // Runnable should NOT have executed because it was cleared
        XCTAssertFalse(runnableExecuted)
    }

    /**
     * Test that runnables are executed when all requests succeed
     * Uses MockURLProtocol which returns 200 OK with valid JSON
     */
    func test_queueFlushRunnables_executedOnSuccess() throws {
        guard let connectionManager = getConnectionManager() else {
            XCTFail("ConnectionManager not available")
            return
        }

        var runnableExecuted = false
        connectionManager.addQueueFlushRunnable {
            runnableExecuted = true
        }

        // Add a request - MockURLProtocol will return success
        Countly.sharedInstance().addDirectRequest(["test": "request"])

        TestUtils.sleep(3) {}

        // Runnable should have executed after successful queue flush
        XCTAssertTrue(runnableExecuted)
    }

    /**
     * Test that multiple runnables are all executed in order when queue flushes successfully
     */
    func test_queueFlushRunnables_multipleExecutedInOrder() throws {
        guard let connectionManager = getConnectionManager() else {
            XCTFail("ConnectionManager not available")
            return
        }

        var executionOrder: [Int] = []

        connectionManager.addQueueFlushRunnable {
            executionOrder.append(1)
        }
        connectionManager.addQueueFlushRunnable {
            executionOrder.append(2)
        }
        connectionManager.addQueueFlushRunnable {
            executionOrder.append(3)
        }

        // Add a request - MockURLProtocol will return success
        Countly.sharedInstance().addDirectRequest(["test": "request"])

        TestUtils.sleep(3) {}

        // All runnables should have executed in order
        XCTAssertEqual(executionOrder, [1, 2, 3])
    }

    /**
     * Test that runnables are removed after successful execution
     * Add runnable, let it execute, add another request - first runnable should not execute again
     */
    func test_queueFlushRunnables_removedAfterExecution() throws {
        guard let connectionManager = getConnectionManager() else {
            XCTFail("ConnectionManager not available")
            return
        }

        var executionCount = 0
        connectionManager.addQueueFlushRunnable {
            executionCount += 1
        }

        // First request - runnable should execute
        Countly.sharedInstance().addDirectRequest(["test": "request1"])

        TestUtils.sleep(3) {}

        XCTAssertEqual(executionCount, 1)

        // Second request - runnable should NOT execute again (was removed)
        Countly.sharedInstance().addDirectRequest(["test": "request2"])

        TestUtils.sleep(3) {}

        // Execution count should still be 1
        XCTAssertEqual(executionCount, 1)
    }

    /**
     * Test that runnables are NOT executed when a request fails
     * Uses MockURLProtocol to simulate a failure response
     */
    func test_queueFlushRunnables_notExecutedOnFailure() throws {
        guard let connectionManager = getConnectionManager() else {
            XCTFail("ConnectionManager not available")
            return
        }

        // Configure MockURLProtocol to return a failure (500 error)
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (Data("Server Error".utf8), response, nil)
        }

        var runnableExecuted = false
        connectionManager.addQueueFlushRunnable {
            runnableExecuted = true
        }

        // Add a request - MockURLProtocol will return 500 error
        Countly.sharedInstance().addDirectRequest(["test": "request"])

        TestUtils.sleep(3) {}

        // Runnable should NOT have executed due to failure
        XCTAssertFalse(runnableExecuted)

        // Restore success handler for subsequent tests
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
    }

    /**
     * Test thread safety - add runnables from multiple threads concurrently
     */
    func test_queueFlushRunnables_threadSafety() throws {
        guard let connectionManager = getConnectionManager() else {
            XCTFail("ConnectionManager not available")
            return
        }

        let expectation = XCTestExpectation(description: "All runnables added")
        let totalRunnables = 100
        var executedCount = 0
        let lock = NSLock()

        let queue1 = DispatchQueue(label: "test.queue1", attributes: .concurrent)
        let queue2 = DispatchQueue(label: "test.queue2", attributes: .concurrent)
        let group = DispatchGroup()

        // Add runnables from multiple threads concurrently
        for _ in 0..<totalRunnables/2 {
            group.enter()
            queue1.async {
                connectionManager.addQueueFlushRunnable {
                    lock.lock()
                    executedCount += 1
                    lock.unlock()
                }
                group.leave()
            }

            group.enter()
            queue2.async {
                connectionManager.addQueueFlushRunnable {
                    lock.lock()
                    executedCount += 1
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        // Trigger queue flush
        Countly.sharedInstance().addDirectRequest(["test": "request"])

        TestUtils.sleep(3) {}

        // All runnables should have been added and executed
        XCTAssertEqual(executedCount, totalRunnables)
    }

    /**
     * Test that a runnable adding new runnables during execution doesn't cause issues
     */
    func test_queueFlushRunnables_addingDuringExecution() throws {
        guard let connectionManager = getConnectionManager() else {
            XCTFail("ConnectionManager not available")
            return
        }

        var firstRunnableExecuted = false
        var nestedRunnableExecuted = false

        connectionManager.addQueueFlushRunnable {
            firstRunnableExecuted = true
            // Add a new runnable during execution
            connectionManager.addQueueFlushRunnable {
                nestedRunnableExecuted = true
            }
        }

        // First flush
        Countly.sharedInstance().addDirectRequest(["test": "request1"])

        TestUtils.sleep(3) {}

        // First runnable should have executed
        XCTAssertTrue(firstRunnableExecuted)
        // Nested runnable should NOT have executed yet (added after copy was made)
        XCTAssertFalse(nestedRunnableExecuted)

        // Second flush - nested runnable should execute
        Countly.sharedInstance().addDirectRequest(["test": "request2"])

        TestUtils.sleep(3) {}

        // Now nested runnable should have executed
        XCTAssertTrue(nestedRunnableExecuted)
    }
}
