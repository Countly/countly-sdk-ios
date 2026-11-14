//
//  CountlyRequestCompressionTests.swift
//  CountlyTests
//
//  Copyright © 2026 Countly. All rights reserved.
//

import XCTest
@testable import Countly

/// Request compression, checked on the requests a mocked server receives: the behavior settings request asks for
/// "gzip", the server's "gzip": true answer turns compression on for request bodies of at least 1 KB, which then go
/// to the endpoint with "content_encoding=gzip" and a gzip body, and a refused compressed request turns it off for
/// the run.
class CountlyRequestCompressionTests: CountlyBaseTestCase {

    private static let bigValue = String(repeating: "a", count: 2000)

    /// A request as the mocked server received it, with its body decoded when it was compressed.
    struct Received {
        let url: URL
        let raw: Data
        let compressed: Bool
        let body: String
    }

    /// Answers the behavior settings request with "gzip": true when it reads gzip and the request asked for it, the
    /// first compressed request with 400 while refuseNextCompressed is set, and every other request with success.
    final class Server {
        private let lock = NSLock()
        private var all: [Received] = []
        var readsGzip: Bool
        var refuseNextCompressed = false

        init(readsGzip: Bool) {
            self.readsGzip = readsGzip
        }

        var received: [Received] {
            lock.lock()
            defer { lock.unlock() }
            return all
        }

        func matching(_ marker: String) -> [Received] {
            return received.filter { $0.body.contains(marker) }
        }

        func handle(_ request: URLRequest) -> Reply {
            let raw = CountlyRequestCompressionTests.bodyData(of: request)
            let compressed = request.url?.query == "content_encoding=gzip"
            let body: String
            if compressed {
                body = CountlyRequestCompressionTests.gunzip(raw) ?? ""
            } else {
                body = String(data: raw, encoding: .utf8) ?? ""
            }
            let entry = Received(url: request.url!, raw: raw, compressed: compressed, body: body)

            lock.lock()
            all.append(entry)
            let refuse = compressed && refuseNextCompressed
            if refuse {
                refuseNextCompressed = false
            }
            lock.unlock()

            if body.contains("method=sc") {
                let gzip = readsGzip && body.contains("gzip=1") ? ",\"gzip\":true" : ""
                let timestamp = Int(Date().timeIntervalSince1970 * 1000)
                return Reply(status: 200, body: "{\"v\":2,\"t\":\(timestamp),\"c\":{}\(gzip)}")
            }
            if refuse {
                return Reply(status: 400, body: "{\"result\":\"Missing parameter\"}")
            }
            return Reply(status: 200, body: "{\"result\":\"Success\"}")
        }
    }

    /// The status and JSON body the mocked server answers a request with.
    struct Reply {
        let status: Int
        let body: String
    }

    override func tearDownWithError() throws {
        Countly.sharedInstance().halt(true)
        MockURLProtocol.replyEmptyToEveryRequest()
        try super.tearDownWithError()
    }

    /// Without enableRequestCompression the settings request does not ask for gzip and a big request goes plain, even
    /// to a server that would read gzip.
    func test_compressionOff_settingsRequestDoesNotAskAndRequestsArePlain() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        let server = start(Server(readsGzip: true), compression: false)
        XCTAssertTrue(TestUtils.waitUntil("settings request") { !server.matching("method=sc").isEmpty })

        addDirectRequest("big_plain", CountlyRequestCompressionTests.bigValue)

        let request = try waitForRequest(server, "big_plain")
        XCTAssertFalse(server.matching("method=sc")[0].body.contains("gzip=1"))
        XCTAssertEqual(request.url.path, "/i")
        XCTAssertNil(request.url.query)
        XCTAssertFalse(request.compressed)
    }

    /// With compression on and a server that answers "gzip": true, a body of at least 1 KB goes to
    /// "/i?content_encoding=gzip" as gzip, smaller than the plain body, which it decodes to.
    func test_compressionOn_serverReadsGzip_bigRequestIsCompressed() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        let server = start(Server(readsGzip: true), compression: true)
        XCTAssertTrue(waitUntilServerSaysGzip())
        XCTAssertTrue(server.matching("method=sc")[0].body.contains("gzip=1"))

        addDirectRequest("big_compressed", CountlyRequestCompressionTests.bigValue)

        let request = try waitForRequest(server, "big_compressed")
        XCTAssertTrue(request.compressed)
        XCTAssertEqual(request.url.path, "/i")
        XCTAssertEqual(request.url.query, "content_encoding=gzip")
        XCTAssertEqual(Array(request.raw.prefix(2)), [0x1f, 0x8b])
        XCTAssertLessThan(request.raw.count, request.body.utf8.count)
        XCTAssertTrue(request.body.contains("app_key=\(appKey)"))
        XCTAssertTrue(request.body.contains("payload=\(CountlyRequestCompressionTests.bigValue)"))
    }

    /// A body under 1 KB goes plain while compression is active.
    func test_compressionOn_smallRequestStaysPlain() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        let server = start(Server(readsGzip: true), compression: true)
        XCTAssertTrue(waitUntilServerSaysGzip())

        addDirectRequest("small_plain", "x")

        let request = try waitForRequest(server, "small_plain")
        XCTAssertFalse(request.compressed)
        XCTAssertNil(request.url.query)
    }

    /// A server whose settings answer has no "gzip" key gets plain requests, so older servers keep working.
    func test_compressionOn_serverDoesNotSayGzip_requestsArePlain() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        let server = start(Server(readsGzip: false), compression: true)
        XCTAssertTrue(TestUtils.waitUntil("settings request") { !server.matching("method=sc").isEmpty })
        XCTAssertTrue(server.matching("method=sc")[0].body.contains("gzip=1"))

        addDirectRequest("big_old_server", CountlyRequestCompressionTests.bigValue)

        let request = try waitForRequest(server, "big_old_server")
        XCTAssertFalse(request.compressed)
        XCTAssertNil(CountlyConnectionManager.sharedInstance().gzipAcceptingHost)
    }

    /// A compressed request the server refuses keeps its place in the queue, compression stops for the rest of the
    /// run, and the retry and later requests go plain.
    func test_compressedRequestRefused_retryAndLaterRequestsArePlain() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        let server = Server(readsGzip: true)
        server.refuseNextCompressed = true
        _ = start(server, compression: true)
        XCTAssertTrue(waitUntilServerSaysGzip())

        addDirectRequest("big_refused", CountlyRequestCompressionTests.bigValue)

        XCTAssertTrue(TestUtils.waitUntil("refusal blocks compression") {
            CountlyConnectionManager.sharedInstance().requestCompressionBlocked
        })
        XCTAssertTrue(server.matching("big_refused")[0].compressed)

        Countly.sharedInstance().attemptToSendStoredRequests()
        XCTAssertTrue(TestUtils.waitUntil("plain retry", timeout: 15) { server.matching("big_refused").count >= 2 })
        XCTAssertFalse(server.matching("big_refused")[1].compressed)

        addDirectRequest("big_after_refusal", CountlyRequestCompressionTests.bigValue)
        XCTAssertFalse(try waitForRequest(server, "big_after_refusal").compressed)
    }

    /// The "gzip" answer is read live and never stored with the behavior settings.
    func test_gzipAnswer_isNotStored() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        _ = start(Server(readsGzip: true), compression: true)
        XCTAssertTrue(waitUntilServerSaysGzip())

        let stored = try XCTUnwrap(CountlyPersistency.sharedInstance().retrieveServerConfig())
        XCTAssertNil(stored["gzip"])
    }

    /// After the server URL changes, requests go plain until the new server says it reads gzip.
    func test_setNewHost_newServerGetsPlainRequests() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        let server = start(Server(readsGzip: true), compression: true)
        XCTAssertTrue(waitUntilServerSaysGzip())

        server.readsGzip = false
        Countly.sharedInstance().setNewHost("https://other-gzip.count.ly")
        addDirectRequest("big_new_host", CountlyRequestCompressionTests.bigValue)

        let request = try waitForRequest(server, "big_new_host")
        XCTAssertEqual(request.url.host, "other-gzip.count.ly")
        XCTAssertFalse(request.compressed)
    }

    /// cly_gzipCompressed writes the gzip header, a raw DEFLATE stream and a trailer with the CRC-32 and the size.
    func test_gzipFormat() throws {
        let plain = "123456789".data(using: .utf8)! as NSData
        let gzip = try XCTUnwrap(plain.cly_gzipCompressed())

        let bytes = [UInt8](gzip)
        XCTAssertEqual(Array(bytes.prefix(4)), [0x1f, 0x8b, 0x08, 0x00])
        XCTAssertEqual(Array(bytes.suffix(8)), [0x26, 0x39, 0xf4, 0xcb, 0x09, 0x00, 0x00, 0x00])
        XCTAssertEqual(CountlyRequestCompressionTests.gunzip(gzip), "123456789")

        let big = String(repeating: "countly ", count: 500)
        let bigGzip = try XCTUnwrap((big.data(using: .utf8)! as NSData).cly_gzipCompressed())
        XCTAssertLessThan(bigGzip.count, big.utf8.count)
        XCTAssertEqual(CountlyRequestCompressionTests.gunzip(bigGzip), big)
    }

    // MARK: - Helpers

    private func start(_ server: Server, compression: Bool) -> Server {
        MockURLProtocol.requestHandler = { request in
            let reply = server.handle(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status,
                                           httpVersion: nil, headerFields: nil)
            return (reply.body.data(using: .utf8), response, nil)
        }
        let config = createBaseConfig()
        config.alwaysUsePOST = true
        config.manualSessionHandling = true
        config.enableRequestCompression = compression
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        config.urlSessionConfiguration = sessionConfig
        Countly.sharedInstance().start(with: config)
        return server
    }

    private func waitUntilServerSaysGzip() -> Bool {
        return TestUtils.waitUntil("compression active") {
            CountlyConnectionManager.sharedInstance().gzipAcceptingHost != nil
        }
    }

    private func addDirectRequest(_ marker: String, _ payload: String) {
        Countly.sharedInstance().addDirectRequest(["marker": marker, "payload": payload])
        Countly.sharedInstance().attemptToSendStoredRequests()
    }

    private func waitForRequest(_ server: Server, _ marker: String) throws -> Received {
        XCTAssertTrue(TestUtils.waitUntil("request \(marker)", timeout: 15) { !server.matching(marker).isEmpty })
        return try XCTUnwrap(server.matching(marker).first)
    }

    static func bodyData(of request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return Data()
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 {
                break
            }
            data.append(buffer, count: read)
        }
        return data
    }

    /// Decodes a gzip member without extra fields, checking the CRC-32 and the size in its trailer.
    static func gunzip(_ data: Data) -> String? {
        let bytes = [UInt8](data)
        guard bytes.count >= 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 0x08, bytes[3] == 0x00 else {
            return nil
        }
        let deflate = Data(bytes[10..<(bytes.count - 8)])
        guard let inflated = try? (deflate as NSData).decompressed(using: .zlib) as Data else {
            return nil
        }
        let trailer = Array(bytes.suffix(8))
        let crc = UInt32(trailer[0]) | UInt32(trailer[1]) << 8 | UInt32(trailer[2]) << 16 | UInt32(trailer[3]) << 24
        let size = UInt32(trailer[4]) | UInt32(trailer[5]) << 8 | UInt32(trailer[6]) << 16 | UInt32(trailer[7]) << 24
        guard crc == crc32(inflated), size == UInt32(truncatingIfNeeded: inflated.count) else {
            return nil
        }
        return String(data: inflated, encoding: .utf8)
    }

    /// CRC-32 as gzip uses it, bit by bit, independent of the SDK's table.
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (0xEDB8_8320 ^ (crc >> 1)) : (crc >> 1)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}
