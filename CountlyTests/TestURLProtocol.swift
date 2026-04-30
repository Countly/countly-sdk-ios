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

        // Return a dummy 200 OK response
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("OK".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        // Nothing to do here
    }

    // MARK: - Helpers for tests
    static func reset() {
        lastRequestHeaders = nil
    }

    static func capturedHeaders() -> [String: String]? {
        lastRequestHeaders
    }
}
