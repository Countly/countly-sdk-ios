//
//  TestURLProtocol.swift
//  Countly
//
//  Created by Arif Burak Demiray on 13.11.2025.
//  Copyright © 2025 Countly. All rights reserved.
//


import Foundation

final class TestURLProtocol: URLProtocol {
    private static var lastRequestHeaders: [String: String]? = nil
    private static var capturedRequests: [(url: String, headers: [String: String])] = []
    private static let capturedRequestsLock = NSLock()

    // MARK: - URLProtocol overrides
    override class func canInit(with request: URLRequest) -> Bool {
        // Intercept all requests
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        // Capture headers
        TestURLProtocol.lastRequestHeaders = request.allHTTPHeaderFields
        TestURLProtocol.capturedRequestsLock.lock()
        TestURLProtocol.capturedRequests.append((request.url?.absoluteString ?? "", request.allHTTPHeaderFields ?? [:]))
        TestURLProtocol.capturedRequestsLock.unlock()

        // Return a dummy 200 OK response
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // a reply the SDK accepts, so the queue moves on to the requests a test queues after start
        client?.urlProtocol(self, didLoad: Data("{\"result\":\"Success\"}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        // Nothing to do here
    }

    // MARK: - Helpers for tests
    static func reset() {
        lastRequestHeaders = nil
        capturedRequestsLock.lock()
        capturedRequests = []
        capturedRequestsLock.unlock()
    }

    static func capturedHeaders() -> [String: String]? {
        lastRequestHeaders
    }

    /// Headers of the first intercepted request whose URL contains the text, or nil. A POST body is a stream here, so only URLs match.
    static func capturedHeaders(forRequestContaining text: String) -> [String: String]? {
        capturedRequestsLock.lock()
        defer { capturedRequestsLock.unlock() }
        return capturedRequests.first { $0.url.contains(text) }?.headers
    }
}
