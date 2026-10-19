//
//  MockURLProtocol.swift
//  Countly
//
//  Created by Arif Burak Demiray on 27.03.2025.
//  Copyright © 2025 Countly. All rights reserved.
//


import Foundation
import XCTest

class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) -> (Data?, URLResponse?, Error?))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            XCTFail("Request handler not set!")
            return
        }
        
        let (data, response, error) = handler(request)
        
        if let response = response {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        if let data = data {
            client?.urlProtocol(self, didLoad: data)
        }
        if let error = error {
            client?.urlProtocol(self, didFailWithError: error)
        }

        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// Answers every later request with an empty JSON object, so requests still in flight after a test do not fail the next one.
    static func replyEmptyToEveryRequest() {
        requestHandler = { request in
            (
                "{}".data(using: .utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil),
                nil
            )
        }
    }
}
