//
//  CountlyRequestCompressionLimitsTests.swift
//  CountlyTests
//
//  Copyright © 2026 Countly. All rights reserved.
//

import XCTest
@testable import Countly

/// Request compression, where the SDK does not compress, stops, or starts again: a body over 1 MB, a refused request
/// followed by a new "gzip": true answer, and an immediate request whose answer is not JSON.
extension CountlyRequestCompressionTests {

    private static let maxBytes = 1024 * 1024

    /// A body over 1 MB goes plain, because the server refuses a larger compressed body, and compression stays on for
    /// the requests after it.
    func test_compressionOn_bodyOverOneMegabyteStaysPlain_compressionStaysOn() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        let server = start(Server(readsGzip: true), compression: true, debug: false)
        XCTAssertTrue(waitUntilServerSaysGzip())

        addDirectRequest("huge_plain", String(repeating: "a", count: CountlyRequestCompressionTests.maxBytes))

        let huge = try waitForRequest(server, "huge_plain")
        XCTAssertFalse(huge.compressed)
        XCTAssertNil(huge.url.query)
        XCTAssertGreaterThan(huge.raw.count, CountlyRequestCompressionTests.maxBytes)
        XCTAssertFalse(CountlyConnectionManager.sharedInstance().requestCompressionBlocked)

        addDirectRequest("big_after_huge", CountlyRequestCompressionTests.bigValue)
        XCTAssertTrue(try waitForRequest(server, "big_after_huge").compressed)
    }

    /// After a refusal stopped compression, a behavior settings answer without "gzip" leaves it stopped, and the next
    /// one with "gzip": true turns it on again.
    func test_compressedRequestRefused_nextGzipAnswerTurnsCompressionOnAgain() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        let server = Server(readsGzip: true)
        server.refuseNextCompressed = true
        _ = start(server, compression: true)
        XCTAssertTrue(waitUntilServerSaysGzip())

        addDirectRequest("big_refused", CountlyRequestCompressionTests.bigValue)
        XCTAssertTrue(TestUtils.waitUntil("refusal blocks compression") {
            CountlyConnectionManager.sharedInstance().requestCompressionBlocked
        })

        server.readsGzip = false
        fetchBehaviorSettings()
        XCTAssertTrue(TestUtils.waitUntil("answer without gzip") {
            CountlyConnectionManager.sharedInstance().gzipAcceptingHost == nil
        })
        XCTAssertTrue(CountlyConnectionManager.sharedInstance().requestCompressionBlocked)

        server.readsGzip = true
        fetchBehaviorSettings()
        XCTAssertTrue(TestUtils.waitUntil("gzip answer unblocks compression") {
            !CountlyConnectionManager.sharedInstance().requestCompressionBlocked
        })
        XCTAssertTrue(waitUntilServerSaysGzip())

        addDirectRequest("big_after_new_answer", CountlyRequestCompressionTests.bigValue)
        XCTAssertTrue(try waitForRequest(server, "big_after_new_answer").compressed)
    }

    /// A compressed immediate request answered with something that is not JSON was not accepted: compression stops.
    /// One answered with JSON leaves it on.
    func test_compressedImmediateRequestAnsweredWithoutJSON_stopsCompression() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        let server = Server(readsGzip: true)
        server.notJSONMarker = "immediate_page"
        _ = start(server, compression: true)
        XCTAssertTrue(waitUntilServerSaysGzip())

        try sendImmediateRequest("immediate_json")
        XCTAssertTrue(try waitForRequest(server, "immediate_json").compressed)
        XCTAssertFalse(CountlyConnectionManager.sharedInstance().requestCompressionBlocked)

        try sendImmediateRequest("immediate_page")
        XCTAssertTrue(try waitForRequest(server, "immediate_page").compressed)
        XCTAssertTrue(CountlyConnectionManager.sharedInstance().requestCompressionBlocked)
    }

    // MARK: - Helpers

    /// Fetches the behavior settings again, as the SDK does when its refresh interval is over.
    private func fetchBehaviorSettings() {
        CountlyServerConfig.sharedInstance().fetch(startedConfig ?? CountlyConfig())
    }

    /// Sends a POST with a 2 KB body through the SDK's immediate request path and waits for its answer.
    private func sendImmediateRequest(_ marker: String) throws {
        let host = try XCTUnwrap(CountlyConnectionManager.sharedInstance().host)
        let url = try XCTUnwrap(URL(string: host + "/o/sdk"))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let body = "app_key=\(appKey)&marker=\(marker)&payload=\(CountlyRequestCompressionTests.bigValue)"
        request.httpBody = body.data(using: .utf8)

        let answered = expectation(description: "answer to \(marker)")
        CountlyCommon.sharedInstance().immediateDataTask(with: request) { _, _, _ in
            answered.fulfill()
        }.resume()
        wait(for: [answered], timeout: 15)
    }
}
