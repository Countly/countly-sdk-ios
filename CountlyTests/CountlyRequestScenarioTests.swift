//
//  CountlyRequestScenarioTests.swift
//  CountlyTests
//
//  This code is provided under the MIT License.
//
//  Please visit www.count.ly for more information.
//

import XCTest
@testable import Countly

/// In each request scenario the SDK sends the requests `api/requests/<platform>/<scenario>.json` records, with the
/// values that change from run to run masked. The scenarios make the calls the other Countly SDKs make in their own
/// request tests. Each platform has its own records, because the SDK sends that platform's details. A deliberate change:
/// run this class again with `TEST_RUNNER_COUNTLY_UPDATE_REQUESTS=1` on each platform that has records, which writes
/// them, check the difference and add a line to CHANGELOG.md.
final class CountlyRequestScenarioTests: CountlyBaseTestCase {
    private static let mask = "<masked>"
    private static let maskedParams: Set<String> = ["timestamp", "hour", "dow", "tz", "sdk_version", "av", "rr", "checksum", "checksum256", "session_duration"]
    private static let jsonParams: Set<String> = ["events", "metrics", "user_details", "crash", "consent", "hc"]
    private static let maskedEventFields: Set<String> = ["timestamp", "hour", "dow", "id", "pvid", "cvid", "peid"]
    private static let maskedCrashFields: Set<String> = ["_error", "_run", "_os", "_os_version", "_resolution", "_density", "_locale", "_device", "_device_type", "_manufacturer", "_cpu", "_opengl", "_ram_current", "_ram_total", "_disk_current", "_disk_total", "_bat", "_orientation", "_root", "_online", "_muted", "_background", "_app_version", "_app_build", "_build_uuid", "_binary_images", "_executable_name"]
    private static let maxInt = 2147483647

    private let lock = NSLock()
    private var sent: [(path: String, query: String)] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        // MockURLProtocol sees what the SDK sends everywhere but on watchOS
        try TestPlatform.skipUnlessHTTPInterceptable()
    }

    func testParity() throws {
        try assertRequests("parity") { countly, _ in
            countly.beginSession()
            countly.recordEvent("purchase", segmentation: Self.paritySegmentation(), count: 2, sum: 9.99, duration: 5)
            Countly.user().name = "John Doe" as CountlyUserDetailsNullableString
            Countly.user().username = "john_d" as CountlyUserDetailsNullableString
            Countly.user().email = "john@example.com" as CountlyUserDetailsNullableString
            Countly.user().organization = "Countly" as CountlyUserDetailsNullableString
            Countly.user().phone = "1234567890" as CountlyUserDetailsNullableString
            Countly.user().pictureURL = "https://example.com/picture.jpg" as CountlyUserDetailsNullableString
            Countly.user().gender = "M" as CountlyUserDetailsNullableString
            Countly.user().birthYear = 1980 as CountlyUserDetailsNullableNumber
            Countly.user().custom = ["tier": "gold", "age": 30] as NSDictionary
            Countly.user().save()
            // a session update reports elapsed seconds, so at least one has to pass for it to be sent
            RunLoop.current.run(until: Date().addingTimeInterval(1.1))
            countly.updateSession()
            countly.endSession()
        }
    }

    func testViews() throws {
        try assertRequests("views") { countly, _ in
            countly.beginSession()
            countly.views().startView("Home", segmentation: ["source": "scenario"])
            countly.views().stopView(withName: "Home")
            countly.views().startView("Settings")
            countly.endSession()
        }
    }

    func testCrash() throws {
        try assertRequests("crash") { countly, _ in
            countly.recordCrashLog("breadcrumb one")
            countly.record(NSException(name: NSExceptionName("ParityCrash"), reason: "parity crash", userInfo: nil), isFatal: false, stackTrace: nil, segmentation: ["tier": "gold"])
        }
    }

    func testConsent() throws {
        try assertRequests("consent", adjust: { $0.requiresConsent = true }) { countly, settle in
            countly.giveConsent(forFeatures: [.sessions, .events])
            countly.beginSession()
            countly.recordEvent("consented")
            settle()
            countly.cancelConsent(forFeature: .events)
            countly.recordEvent("not_consented")
            countly.endSession()
        }
    }

    func testDeviceID() throws {
        try assertRequests("device-id") { countly, settle in
            countly.beginSession()
            countly.changeDeviceID(withMerge: "parity-device-002")
            countly.recordEvent("after_merge")
            settle()
            countly.changeDeviceIDWithoutMerge("parity-device-003")
            countly.recordEvent("after_new_id")
            countly.endSession()
        }
    }

    // MARK: - Scenario runner

    /// The event segmentation of the parity scenario, with one value of every type.
    private static func paritySegmentation() -> [String: Any] {
        return [
            "nar": "uto",
            "sasuke": maxInt,
            "sakura": false,
            "itachi": Double.greatestFiniteMagnitude,
            "kakaski": Double.leastNonzeroMagnitude,
            "hashirama": -maxInt,
            "tobi": ["obito": "uchiha", "zetsu": "white"],
            "stringList": ["value1", "value2", "value3"],
            "intList": [1, 2, 3],
            "doubleList": [1.1, 2.2, 3.3],
            "boolList": [true, false, true],
            "mixedList": ["value1", 2, 3.3, true] as [Any],
            "mapList": [["key1": "value1", "key2": 2], ["key1": "value2", "key2": 3], ["key1": "value3", "key2": 4]] as [[String: Any]],
        ]
    }

    /// Starts the SDK with the scenario config, runs the scenario, and compares the requests it sent with the record of
    /// the scenario, or writes the record in update mode.
    /// - Parameters:
    ///   - name: scenario name, the record file name without .json
    ///   - adjust: changes the scenario makes to the common config
    ///   - scenario: the calls, given the SDK and a function that waits until the SDK has sent what the calls queued
    private func assertRequests(_ name: String, adjust: (CountlyConfig) -> Void = { _ in }, _ scenario: (Countly, () -> Void) -> Void) throws {
        MockURLProtocol.requestHandler = { [weak self] request in
            self?.capture(request)
            return ("{\"result\":\"Success\"}".data(using: .utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil), nil)
        }
        let config = CountlyConfig()
        config.appKey = "parity-app-key"
        config.host = "https://parity.example"
        config.deviceID = "parity-device-001"
        config.manualSessionHandling = true
        config.enableOrientationTracking = false
        config.enableDebug = true
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        config.urlSessionConfiguration = sessionConfig
        adjust(config)
        Countly.sharedInstance().start(with: config)
        scenario(Countly.sharedInstance(), { self.settle() })
        settle()
        Countly.sharedInstance().halt(true)

        let current = try report()
        let file = Self.recordURL(name)
        if ProcessInfo.processInfo.environment["COUNTLY_UPDATE_REQUESTS"] == "1" {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try current.write(to: file, atomically: true, encoding: .utf8)
            return
        }
        let path = "api/requests/\(Self.platform)/\(name).json"
        guard let committed = try? String(contentsOf: file, encoding: .utf8) else {
            XCTFail("no \(path), run this class with TEST_RUNNER_COUNTLY_UPDATE_REQUESTS=1")
            return
        }
        let normalized = committed.replacingOccurrences(of: "\r\n", with: "\n")
        if normalized != current {
            XCTFail("the requests of the \(name) scenario differ from \(path). If that is deliberate, run this class with TEST_RUNNER_COUNTLY_UPDATE_REQUESTS=1, check the difference and add a line to CHANGELOG.md.\n" + Self.difference(normalized, current))
        }
    }

    /// The difference between a record and the requests sent, for the failure message: the first line where they part,
    /// which also shows requests sent in another order, then the lines only one of them has.
    private static func difference(_ recorded: String, _ current: String) -> String {
        let was = recorded.components(separatedBy: "\n")
        let now = current.components(separatedBy: "\n")
        let first = zip(was, now).enumerated().first { $0.element.0 != $0.element.1 }
        var text = first.map { "first difference, at line \($0.offset + 1):\n- \($0.element.0)\n+ \($0.element.1)" }
            ?? "the record has \(was.count) lines and the requests \(now.count)"
        let removed = was.filter { !now.contains($0) }.map { "- " + $0 }
        let added = now.filter { !was.contains($0) }.map { "+ " + $0 }
        text += "\nlines only one of them has:\n" + (removed + added).joined(separator: "\n")
        return text
    }

    /// Records a request the SDK sent: its path and its query, from the body of a POST request or the URL of a GET.
    private func capture(_ request: URLRequest) {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: 4096)
                if read <= 0 { break }
                body.append(buffer, count: read)
            }
            buffer.deallocate()
            stream.close()
        }
        let query = body.isEmpty ? (request.url?.query ?? "") : (String(data: body, encoding: .utf8) ?? "")
        lock.lock()
        sent.append((path: request.url?.path ?? "", query: query))
        lock.unlock()
    }

    /// The requests sent so far.
    private func sentRequests() -> [(path: String, query: String)] {
        lock.lock()
        defer { lock.unlock() }
        return sent
    }

    /// Moves the recorded events into the request queue and waits until the SDK has sent everything it queued: the
    /// queue is empty and no request came for longer than the SDK's own short delays.
    private func settle() {
        CountlyConnectionManager.sharedInstance().sendEvents()
        CountlyConnectionManager.sharedInstance().proceedOnQueue()
        let started = Date()
        var count = -1
        var quietSince = Date()
        while Date().timeIntervalSince(started) < 15 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            let queued = TestUtils.getCurrentRQ()?.count ?? 0
            let sentCount = sentRequests().count
            if queued > 0 || sentCount != count {
                count = sentCount
                quietSince = Date()
            } else if Date().timeIntervalSince(quietSince) > 1.5 {
                return
            }
        }
        XCTFail("the SDK still had requests to send after 15 seconds")
    }

    // MARK: - Records

    /// The folder in api/requests/ of the platform the tests run on.
    private static var platform: String {
        #if os(macOS)
        return "macos"
        #elseif os(tvOS)
        return "tvos"
        #elseif os(watchOS)
        return "watchos"
        #elseif os(visionOS)
        return "visionos"
        #else
        return "ios"
        #endif
    }

    /// The record file of a scenario on this platform, in api/requests/ next to the CountlyTests folder.
    private static func recordURL(_ name: String) -> URL {
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("api/requests/\(platform)/\(name).json")
    }

    /// The record of the sent requests: each with its path and its parameters, the values that change from run to run
    /// masked, the JSON parameters parsed and the keys of every object sorted. The SDK sends health checks and server
    /// config requests on their own, outside its queue, so they reach the server at no fixed point among the others: the
    /// record keeps the queued requests in the order they were sent, and lists those after them, sorted.
    private func report() throws -> String {
        let records: [[String: Any]] = sentRequests().map { request in
            var params: [String: Any] = [:]
            for pair in request.query.split(separator: "&", omittingEmptySubsequences: true) {
                let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let key = String(parts[0]).removingPercentEncoding ?? String(parts[0])
                let raw = parts.count > 1 ? String(parts[1]) : ""
                let value = raw.removingPercentEncoding ?? raw
                params[key] = Self.recorded(key, value)
            }
            return ["path": request.path, "params": params]
        }
        let queued = records.filter { !Self.isDirect($0) }
        let direct = try records.filter { Self.isDirect($0) }.sorted { try Self.compact($0) < Self.compact($1) }
        let data = try JSONSerialization.data(withJSONObject: queued + direct, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return (String(data: data, encoding: .utf8) ?? "") + "\n"
    }

    /// Whether a recorded request is one the SDK sends outside its queue: a health check or a server config request.
    private static func isDirect(_ record: [String: Any]) -> Bool {
        return (record["path"] as? String) == "/o/sdk" || (record["params"] as? [String: Any])?["hc"] != nil
    }

    /// A record as one line of JSON with its keys sorted, which orders the requests sent outside the queue.
    private static func compact(_ record: [String: Any]) throws -> String {
        return String(data: try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), encoding: .utf8) ?? ""
    }

    /// A parameter value as the record keeps it: masked, parsed and masked when it is JSON, or as sent.
    private static func recorded(_ key: String, _ value: String) -> Any {
        if maskedParams.contains(key) {
            return mask
        }
        guard jsonParams.contains(key), let data = value.data(using: .utf8), let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return value
        }
        if key == "metrics" || key == "hc", let object = parsed as? [String: Any] {
            return object.mapValues { _ in mask }
        }
        if key == "events", let events = parsed as? [[String: Any]] {
            return events.map { event -> [String: Any] in
                let fields = (event["key"] as? String) == "[CLY]_view" ? maskedEventFields.union(["dur"]) : maskedEventFields
                return masked(event, fields)
            }
        }
        if key == "crash", let object = parsed as? [String: Any] {
            return masked(object, maskedCrashFields)
        }
        return parsed
    }

    /// A copy of an object with the values of the given keys masked.
    private static func masked(_ object: [String: Any], _ fields: Set<String>) -> [String: Any] {
        var copy = object
        for key in object.keys where fields.contains(key) {
            copy[key] = mask
        }
        return copy
    }
}
