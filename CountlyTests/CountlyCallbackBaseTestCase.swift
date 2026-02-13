//
//  CountlyCallbackBaseTestCase.swift
//  CountlyTests
//
//  Shared base class for callback-related tests.
//  Provides common SDK setup, MockURLProtocol configuration, and helpers.
//

import XCTest
@testable import Countly

/// Base test class for callback tests (CLYRequestCallback and CLYQueueFlushRunnable).
/// Uses class-level setup to start SDK once, avoiding the halt() singleton issue.
class CountlyCallbackBaseTestCase: XCTestCase {

    // MARK: - Static SDK Setup

    private static var isSDKStarted = false
    static let testAppKey = "appkey"
    static let testHost = "https://testing.count.ly/"

    override class func setUp() {
        super.setUp()
        guard !isSDKStarted else { return }

        // Configure MockURLProtocol to return valid JSON by default
        MockURLProtocol.requestHandler = createSuccessHandler()

        let config = CountlyConfig()
        config.appKey = testAppKey
        config.host = testHost
        config.enableDebug = true
        config.manualSessionHandling = true
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        config.urlSessionConfiguration = sessionConfig
        Countly.sharedInstance().start(with: config)
        isSDKStarted = true
    }

    // MARK: - Instance Setup/Teardown

    override func setUp() {
        super.setUp()
        // Reset MockURLProtocol to success handler for each test
        MockURLProtocol.requestHandler = Self.createSuccessHandler()
        // Clear any leftover runnables
        connectionManager?.clearQueueFlushRunnables()
        // Drain any pending queue requests
        drainQueue()
    }

    override func tearDown() {
        connectionManager?.clearQueueFlushRunnables()
        super.tearDown()
    }

    // MARK: - Connection Manager Helper

    var connectionManager: CountlyConnectionManager? {
        return CountlyConnectionManager.sharedInstance()
    }

    // MARK: - Queue Helpers

    /// Drain the request queue to avoid state pollution between tests
    func drainQueue() {
        var waitCount = 0
        while CountlyPersistency.sharedInstance().remainingRequestCount() > 0 && waitCount < 50 {
            connectionManager?.proceedOnQueue()
            Thread.sleep(forTimeInterval: 0.1)
            waitCount += 1
        }
    }

    // MARK: - MockURLProtocol Helpers

    /// Type alias for request handler closure
    typealias RequestHandler = (URLRequest) -> (Data?, URLResponse?, Error?)

    /// Creates a success handler returning valid JSON with status 200
    static func createSuccessHandler() -> RequestHandler {
        return { request in
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

    /// Creates a success handler with custom status code (2xx range)
    static func createSuccessHandler(statusCode: Int, result: String = "Success") -> RequestHandler {
        return { request in
            let jsonResponse = Data("{\"result\":\"\(result)\"}".utf8)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (jsonResponse, response, nil)
        }
    }

    /// Creates an error handler returning specified HTTP status code
    static func createErrorHandler(statusCode: Int, message: String) -> RequestHandler {
        return { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (Data(message.utf8), response, nil)
        }
    }

    /// Creates a handler returning plain text (invalid JSON) with 200
    static func createInvalidJSONHandler() -> RequestHandler {
        return { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (Data("OK".utf8), response, nil)
        }
    }

    /// Creates a handler returning JSON without "result" key
    static func createMissingResultKeyHandler() -> RequestHandler {
        return { request in
            let jsonResponse = Data("{\"status\":\"ok\"}".utf8)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (jsonResponse, response, nil)
        }
    }
}
