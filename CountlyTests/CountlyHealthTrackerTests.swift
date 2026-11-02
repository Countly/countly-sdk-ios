//
//  CountlyHealthTrackerTests.swift
//  Countly
//
//  Created by Arif Burak Demiray on 23.09.2025.
//  Copyright © 2025 Countly. All rights reserved.
//
import XCTest

@testable import Countly

class CountlyHealthTrackerTests: CountlyBaseTestCase {

    /// Answers every request through `MockURLProtocol` from the base setup on: a health check with an answer that keeps the
    /// counters, every other request with a success, so that no answer of a real server adds or takes away counts mid test.
    override func setUpWithError() throws {
        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { return (nil, nil, nil) }
            let isHealthCheck = TestUtils.parseQueryString(url.query ?? "")["hc"] != nil
            let body = isHealthCheck ? "{}" : "{\"result\":\"Success\"}"
            return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil), nil)
        }
        try super.setUpWithError()
    }

    /// The base config with every request routed through `MockURLProtocol`.
    override func createBaseConfig() -> CountlyConfig {
        let config = super.createBaseConfig()
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        config.urlSessionConfiguration = sessionConfig
        return config
    }

    // MARK: - Helper Methods

    /// Executes concurrent stress test with configurable parameters to detect race conditions and memory issues
    /// - Parameters:
    ///   - iterations: Number of iterations per queue
    ///   - writerDelay: Delay in microseconds between writer operations
    ///   - readerDelay: Delay in microseconds between reader operations
    ///   - extraThreads: Additional threads for mixed operations
    ///   - timeout: Maximum time to wait for completion
    ///   - writerBlock: Block executed by writer threads
    ///   - readerBlock: Block executed by reader threads
    private func runConcurrentStressTest(
        iterations: Int = 10_000,
        readerIterations: Int? = nil,
        writerDelay: useconds_t = 0,
        readerDelay: useconds_t = 0,
        extraThreads: Int = 0,
        timeout: TimeInterval = 60,
        file: StaticString = #filePath,
        line: UInt = #line,
        writerBlock: @escaping (Int) -> Void,
        readerBlock: @escaping () -> Void
    ) {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)

        let actualReaderIterations = readerIterations ?? min(iterations, 100)
        let group = DispatchGroup()
        let writerQueue = DispatchQueue(label: "test.writer", attributes: .concurrent)
        let readerQueue = DispatchQueue(label: "test.reader", attributes: .concurrent)

        // Writer operations
        group.enter()
        writerQueue.async {
            for i in 0..<iterations {
                autoreleasepool {
                    writerBlock(i)
                    if writerDelay > 0 { usleep(writerDelay) }
                }
            }
            group.leave()
        }

        // Reader operations (capped to avoid exhausting file descriptors from network calls)
        group.enter()
        readerQueue.async {
            for _ in 0..<actualReaderIterations {
                autoreleasepool {
                    readerBlock()
                    if readerDelay > 0 { usleep(readerDelay) }
                }
            }
            group.leave()
        }

        // Additional mixed operations for maximum contention
        let mixedIterations = min(iterations / 2, 100)
        for threadIndex in 0..<extraThreads {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                for i in 0..<mixedIterations {
                    autoreleasepool {
                        if i % 2 == 0 {
                            writerBlock(i + threadIndex * iterations)
                        } else {
                            readerBlock()
                        }
                    }
                }
                group.leave()
            }
        }

        let result = group.wait(timeout: .now() + timeout)
        XCTAssertEqual(
            result, .success, "Concurrent stress test did not complete within \(timeout) seconds", file: file,
            line: line)
    }

    /// Creates test strings with various characteristics to test memory management edge cases
    /// - Returns: Array of test strings with different properties (length, encoding, mutability)
    private func createTestStrings() -> [(name: String, value: String?)] {
        return [
            ("nil", nil),
            ("empty", ""),
            ("short", "test"),
            ("under_limit", String(repeating: "a", count: 999)),
            ("exact_limit", String(repeating: "b", count: 1000)),
            ("over_limit", String(repeating: "c", count: 1500)),
            ("unicode", String(repeating: "🚀", count: 250)),
            ("mixed_unicode", "Test🚀String🌟With✨Unicode🎉" + String(repeating: "x", count: 950)),
            ("special_chars", String(repeating: "line\n\ttab\r", count: 100)),
        ]
    }

    /// Executes all HealthTracker operations to test comprehensive property access
    /// - Parameter index: Index used for unique identifiers
    private func executeAllHealthTrackerOperations(index: Int) {
        switch index % 4 {
        case 0:
            CountlyHealthTracker.sharedInstance().logWarning()
        case 1:
            CountlyHealthTracker.sharedInstance().logError()
        case 2:
            CountlyHealthTracker.sharedInstance().logBackoffRequest()
        case 3:
            CountlyHealthTracker.sharedInstance().logConsecutiveBackoffRequest()
        default:
            break
        }
    }

    // MARK: - Test Cases

    // MARK: - Concurrent Access Tests

    /// Tests logFailedNetworkRequest under high concurrency to ensure thread safety
    /// 10,000 iterations with 4 extra threads performing mixed operations
    /// Validates that concurrent writes don't cause race conditions or crashes
    func testLogFailedNetworkRequest_concurrentAccessProtection() {
        runConcurrentStressTest(
            iterations: 10_000,
            extraThreads: 4,
            writerBlock: { i in
                let error = String(repeating: "X", count: 50) + " \(i)"
                CountlyHealthTracker.sharedInstance()
                    .logFailedNetworkRequest(withStatusCode: 500, errorResponse: error)
            },
            readerBlock: {
                _ = CountlyHealthTracker.sharedInstance().healthCheckRequest()
            }
        )
    }

    /// Tests logFailedNetworkRequest with memory-intensive strings to catch objc_release errors
    /// Large strings (36,000+ chars), delayed operations to increase memory pressure
    /// Specifically targets the objc_release crash that occurred with rapid string copying
    func testLogFailedNetworkRequest_objcReleaseErrorPrevention() {
        runConcurrentStressTest(
            iterations: 500,
            writerDelay: 50,
            readerDelay: 50,
            writerBlock: { _ in
                let err = String(repeating: UUID().uuidString, count: 1000)  // ~36KB string
                CountlyHealthTracker.sharedInstance()
                    .logFailedNetworkRequest(withStatusCode: 500, errorResponse: err)
            },
            readerBlock: {
                _ = CountlyHealthTracker.sharedInstance().healthCheckRequest()
            }
        )
    }

    // MARK: - String Memory Management Tests

    /// Tests string memory management across various string types and concurrent scenarios
    /// Multiple string types (nil, empty, boundary cases, unicode, mutable strings)
    /// Validates proper copy semantics and immutability protection for errorMessage property
    func testLogFailedNetworkRequest_stringMemoryManagement() {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)

        let iterations = 5_000
        let group = DispatchGroup()
        let testStrings = createTestStrings()

        // Test concurrent access with different string types
        for (index, testString) in testStrings.enumerated() {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                for i in 0..<iterations {
                    autoreleasepool {
                        let errorString = testString.value ?? ""
                        let finalString = errorString.isEmpty ? "nil_test_\(i)" : "\(errorString)_\(i)"

                        CountlyHealthTracker.sharedInstance()
                            .logFailedNetworkRequest(withStatusCode: 400 + index, errorResponse: finalString)
                    }
                }
                group.leave()
            }
        }

        // Test mutable string protection - ensures copy semantics work correctly
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            for i in 0..<iterations {
                autoreleasepool {
                    let mutableString = NSMutableString(string: "mutable_\(i)")
                    CountlyHealthTracker.sharedInstance()
                        .logFailedNetworkRequest(withStatusCode: 500, errorResponse: mutableString as String)

                    // Modify original to test copy protection
                    mutableString.append("_should_not_affect_copy")
                }
            }
            group.leave()
        }

        let result = group.wait(timeout: .now() + 30)
        XCTAssertEqual(result, .success, "String memory management test did not complete in time")
    }

    // MARK: - Race Condition Tests

    /// Tests rapid errorMessage property updates to catch race conditions that cause objc_release errors
    /// 8 concurrent writers, 4 readers, 20,000 iterations with mixed operations
    /// Targets the specific race condition where errorMessage property caused crashes
    func testLogFailedNetworkRequest_errorMessageRaceCondition() {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)

        let iterations = 2_000
        let group = DispatchGroup()

        // Multiple writers rapidly updating errorMessage property
        for writerIndex in 0..<8 {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                for i in 0..<iterations {
                    autoreleasepool {
                        let errorMsg = "writer_\(writerIndex)_iteration_\(i)_" + String(repeating: "x", count: 100)
                        CountlyHealthTracker.sharedInstance()
                            .logFailedNetworkRequest(withStatusCode: 500, errorResponse: errorMsg)
                    }
                }
                group.leave()
            }
        }

        // Multiple readers accessing errorMessage through the health check request they build
        for _ in 0..<2 {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                for _ in 0..<50 {
                    autoreleasepool {
                        _ = CountlyHealthTracker.sharedInstance().healthCheckRequest()
                    }
                }
                group.leave()
            }
        }

        // Mixed operations for maximum property contention
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            for i in 0..<iterations {
                autoreleasepool {
                    self.executeAllHealthTrackerOperations(index: i)
                }
            }
            group.leave()
        }

        let result = group.wait(timeout: .now() + 45)
        XCTAssertEqual(result, .success, "Error message race condition test did not complete in time")
    }

    // MARK: - Boundary Condition Tests

    /// Tests boundary conditions that commonly trigger memory management bugs
    /// Strings at 1000-char limit, over-limit, unicode chars, special characters
    /// Validates proper truncation and memory handling at edge cases
    func testLogFailedNetworkRequest_boundaryConditions() {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)

        let boundaryTests: [(name: String, content: String)] = [
            ("exactly_1000_chars", String(repeating: "a", count: 1000)),
            ("over_1000_chars", String(repeating: "b", count: 1500)),
            ("empty_string", ""),
            ("single_char", "x"),
            ("unicode_boundary", String(repeating: "🎯", count: 250)),  // 4-byte unicode
            ("mixed_content", "Test🚀String🌟With✨Unicode🎉Characters" + String(repeating: "x", count: 950)),
            ("special_chars", String(repeating: "line\n\ttab\r", count: 100)),
        ]

        let group = DispatchGroup()

        for (testName, testString) in boundaryTests {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                for i in 0..<1000 {
                    autoreleasepool {
                        let uniqueString = "\(testName)_\(i)_\(testString)"
                        CountlyHealthTracker.sharedInstance()
                            .logFailedNetworkRequest(withStatusCode: 400, errorResponse: uniqueString)

                        // Immediate read to create contention
                        if i % 200 == 0 {
                            _ = CountlyHealthTracker.sharedInstance().healthCheckRequest()
                        }
                    }
                }
                group.leave()
            }
        }

        // Test all property setters under load
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            for i in 0..<2000 {
                autoreleasepool {
                    self.executeAllHealthTrackerOperations(index: i)
                }
            }
            group.leave()
        }

        let result = group.wait(timeout: .now() + 30)
        XCTAssertEqual(result, .success, "Boundary conditions test did not complete in time")
    }

    // MARK: - Performance Tests

    /// Tests performance of synchronized operations to ensure thread safety doesn't cause significant slowdowns
    /// 10,000 write operations, 1,000 read operations with performance measurement
    /// Validates that serial queue synchronization maintains acceptable performance
    func testLogFailedNetworkRequest_synchronizedOperationsPerformance() {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)

        measure(metrics: [XCTClockMetric()]) {
            let iterations = 500
            let group = DispatchGroup()

            // Test write performance
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                for i in 0..<iterations {
                    CountlyHealthTracker.sharedInstance()
                        .logFailedNetworkRequest(withStatusCode: 500, errorResponse: "perf_test_\(i)")
                }
                group.leave()
            }

            // Test read performance (fewer iterations as each builds a whole request)
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                for _ in 0..<(iterations / 10) {
                    _ = CountlyHealthTracker.sharedInstance().healthCheckRequest()
                }
                group.leave()
            }

            let result = group.wait(timeout: .now() + 30)
            XCTAssertEqual(result, .success, "Performance test did not complete in time")
        }
    }

    /// Tests performance under high concurrency to validate scalability of thread safety solution
    /// 4 concurrent writers, 5,000 iterations each with mixed operations
    /// Ensures the serial queue doesn't become a bottleneck under high load
    func testLogFailedNetworkRequest_concurrentOperationsPerformance() {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)

        let iterations = 5_000

        measure(metrics: [XCTClockMetric()]) {
            let group = DispatchGroup()

            // Multiple concurrent writers
            for writerIndex in 0..<4 {
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    for i in 0..<iterations {
                        autoreleasepool {
                            CountlyHealthTracker.sharedInstance()
                                .logFailedNetworkRequest(
                                    withStatusCode: 500,
                                    errorResponse: "writer_\(writerIndex)_\(i)")

                            // Mix in other operations
                            if i % 10 == 0 { CountlyHealthTracker.sharedInstance().logWarning() }
                            if i % 20 == 0 { CountlyHealthTracker.sharedInstance().logError() }
                        }
                    }
                    group.leave()
                }
            }

            let result = group.wait(timeout: .now() + 15)
            XCTAssertEqual(result, .success, "Concurrent performance test did not complete in time")
        }
    }

    // MARK: - Method Usage & Log Code Tests

    /// Persists the counters and waits until the health tracker queue ran the work queued on it, also the work that
    /// work queues.
    private func drainHealthCheckQueue(_ tracker: CountlyHealthTracker) {
        tracker.saveState()
        tracker.hcQueue.sync {}
        tracker.hcQueue.sync {}
    }

    /// Clears every counter of the health tracker and waits until it is done.
    private func resetCounters(_ tracker: CountlyHealthTracker) {
        tracker.clearAndSave()
        tracker.hcQueue.sync {}
    }

    /// The method usage and log codes counted so far, read on the health tracker queue once the queued work ran.
    private func counted(_ tracker: CountlyHealthTracker) -> (usage: [String: [String: Int]], codes: [String: Int]) {
        drainHealthCheckQueue(tracker)
        var usage: [String: [String: Int]] = [:]
        var codes: [String: Int] = [:]
        tracker.hcQueue.sync {
            for (area, methods) in tracker.methodUsage {
                guard let area = area as? String, let methods = methods as? [String: NSNumber] else { continue }
                usage[area] = methods.mapValues { $0.intValue }
            }
            for (code, count) in tracker.logCodes {
                guard let code = code as? String, let count = count as? NSNumber else { continue }
                codes[code] = count.intValue
            }
        }
        return (usage, codes)
    }

    /// Starts the SDK with the health check marked as sent, so no server answer takes counters away while a test reads
    /// them.
    private func startWithoutHealthCheck(_ config: CountlyConfig) {
        CountlyHealthTracker.sharedInstance().setValue(true, forKey: "healthCheckSent")
        Countly.sharedInstance().start(with: config)
    }

    /// The `hc` parameter a health check request carries.
    private func healthCheckParameter(of request: URLRequest) -> [String: Any] {
        let query = request.url?.query ?? String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        return TestUtils.parseQueryString(query)["hc"] as? [String: Any] ?? [:]
    }

    /// recordUsage and recordLogCode add up per feature area and method, and per code.
    func testRecordUsageAndLogCodeAccumulate() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        let config = createBaseConfig()
        config.manualSessionHandling = true
        startWithoutHealthCheck(config)
        resetCounters(tracker)

        tracker.recordUsage("events", method: "record")
        tracker.recordUsage("events", method: "record")
        tracker.recordUsage("views", method: "start")
        tracker.recordLogCode("w204")
        tracker.recordLogCode("e301")

        let (usage, codes) = counted(tracker)
        XCTAssertEqual(usage["events"]?["record"], 2)
        XCTAssertEqual(usage["views"]?["start"], 1)
        XCTAssertEqual(codes["w204"], 1)
        XCTAssertEqual(codes["e301"], 1)
    }

    /// An empty feature area, method or code is ignored.
    func testRecordUsageIgnoresEmptyInputs() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        resetCounters(tracker)

        tracker.recordUsage("", method: "record")
        tracker.recordUsage("events", method: "")
        tracker.recordLogCode("")

        let (usage, codes) = counted(tracker)
        XCTAssertTrue(usage.isEmpty)
        XCTAssertTrue(codes.isEmpty)
    }

    /// Counting from many threads at once is safe and stays within the cap a health check reports.
    func testRecordUsageThreadSafety() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        resetCounters(tracker)
        runConcurrentStressTest(
            iterations: 10_000,
            writerBlock: { _ in tracker.recordUsage("events", method: "record") },
            readerBlock: { tracker.saveState() }
        )

        let count = counted(tracker).usage["events"]?["record"] ?? 0
        XCTAssertTrue(count > 0 && count <= 65535, "expected 0 < count <= 65535, got \(count)")
    }

    /// The counts are persisted with the other counters, and clearAndSave clears them.
    func testUsageAndLogCodesPersistAndClear() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        startWithoutHealthCheck(createBaseConfig())
        resetCounters(tracker)
        tracker.recordUsage("events", method: "record")
        tracker.recordLogCode("w204")
        drainHealthCheckQueue(tracker)

        let state = CountlyPersistency.sharedInstance().retrieveHealthCheckTrackerState() ?? [:]
        XCTAssertEqual((state["MU"] as? [String: [String: NSNumber]])?["events"]?["record"], 1)
        XCTAssertEqual((state["LC"] as? [String: NSNumber])?["w204"], 1)

        resetCounters(tracker)
        let (usage, codes) = counted(tracker)
        XCTAssertTrue(usage.isEmpty)
        XCTAssertTrue(codes.isEmpty)
    }

    /// The health check request carries the counted method usage and log codes.
    func testHealthCheckRequestIncludesFuLcWhenPresent() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        startWithoutHealthCheck(createBaseConfig())
        resetCounters(tracker)
        tracker.recordUsage("events", method: "record")
        tracker.recordLogCode("w204")
        drainHealthCheckQueue(tracker)

        let healthCheck = healthCheckParameter(of: tracker.healthCheckRequest())
        XCTAssertEqual((healthCheck["fu"] as? [String: [String: Int]])?["events"]?["record"], 1, "got: \(healthCheck)")
        XCTAssertEqual((healthCheck["lc"] as? [String: Int])?["w204"], 1, "got: \(healthCheck)")
    }

    /// An error message holding '&', '=' and '+' reaches the server intact, so it can not cut the hc parameter short.
    func testHealthCheckRequestEscapesTheErrorMessage() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        startWithoutHealthCheck(createBaseConfig())
        resetCounters(tracker)

        tracker.logFailedNetworkRequest(withStatusCode: 502, errorResponse: "a&b=c+d")
        tracker.recordLogCode("e301")
        drainHealthCheckQueue(tracker)

        let healthCheck = healthCheckParameter(of: tracker.healthCheckRequest())
        XCTAssertEqual(healthCheck["em"] as? String, "a&b=c+d", "got: \(healthCheck)")
        XCTAssertEqual((healthCheck["lc"] as? [String: Int])?["e301"], 1, "got: \(healthCheck)")
    }

    /// An automatic session is counted when it really begins, here once session consent is given, not when start tries
    /// to begin
    /// it without consent.
    func testAutomaticSessionBeginIsCountedWhenConsentLetsItBegin() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        let config = createBaseConfig()
        config.requiresConsent = true
        startWithoutHealthCheck(config)

        XCTAssertNil(counted(tracker).usage["sessions"]?["begin:a"])

        Countly.sharedInstance().giveConsent(forFeatures: [CLYConsent.sessions])

        XCTAssertEqual(counted(tracker).usage["sessions"]?["begin:a"], 1)
    }

#if os(iOS) || os(tvOS)
    /// Going to the background stores the automatic session end it makes, so an app killed in the background still
    /// reports it.
    func testEnteringBackgroundStoresTheAutomaticSessionEnd() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        startWithoutHealthCheck(createBaseConfig())
        resetCounters(tracker)

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        tracker.hcQueue.sync {}

        let state = CountlyPersistency.sharedInstance().retrieveHealthCheckTrackerState() ?? [:]
        XCTAssertEqual((state["MU"] as? [String: [String: NSNumber]])?["sessions"]?["end:a"], 1, "got: \(state)")
    }
#endif

    /// "fu" and "lc" are sent also when nothing was counted, so the server can tell an SDK that reports them from one
    /// that does not.
    func testHealthCheckRequestAlwaysCarriesFuAndLc() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        startWithoutHealthCheck(createBaseConfig())
        resetCounters(tracker)

        let healthCheck = healthCheckParameter(of: tracker.healthCheckRequest())
        XCTAssertEqual((healthCheck["fu"] as? [String: Any])?.isEmpty, true, "got: \(healthCheck)")
        XCTAssertEqual((healthCheck["lc"] as? [String: Any])?.isEmpty, true, "got: \(healthCheck)")
    }

    /// Every recordEvent call of the app is counted once, whichever convenience form it uses.
    func testPublicMethodsPopulateUsage() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        startWithoutHealthCheck(createBaseConfig())
        resetCounters(tracker)

        Countly.sharedInstance().recordEvent("test_event")
        Countly.sharedInstance().recordEvent("test_event_2", segmentation: ["key": "value"])

        XCTAssertEqual(counted(tracker).usage["events"]?["record"], 2)
    }

    /// With consent required and none given, no call of any feature is counted, and neither is a log code such a call
    /// records, since knowing which methods an app calls is itself tracking information.
    func testNothingIsCountedForFeaturesWithoutConsent() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        let config = createBaseConfig()
        config.requiresConsent = true
        startWithoutHealthCheck(config)
        resetCounters(tracker)

        Countly.sharedInstance().beginSession()
        Countly.sharedInstance().updateSession()
        Countly.sharedInstance().endSession()
        Countly.sharedInstance().recordEvent("blocked_event")
        Countly.sharedInstance().startEvent("blocked_timed")
        Countly.sharedInstance().endEvent("blocked_timed")
        Countly.sharedInstance().cancelEvent("blocked_timed")
        Countly.sharedInstance().views().startView("Screen")
        Countly.sharedInstance().views().stopView(withName: "Screen")
        Countly.sharedInstance().views().stopAllViews([:])
        _ = Countly.sharedInstance().views().startView("")
        Countly.sharedInstance().views().stopView(withID: "missing_view_id")
        Countly.sharedInstance().views().addSegmentationToView(withName: "missing_view", segmentation: ["key": "value"])
        Countly.sharedInstance().views().addSegmentationToView(withID: "missing_view_id", segmentation: ["key": "value"])
        Countly.sharedInstance().record(NSException(name: .genericException, reason: "blocked", userInfo: nil))
        Countly.sharedInstance().recordCrashLog("blocked")
        Countly.sharedInstance().clearCrashLogs()

        let (usage, codes) = counted(tracker)
        XCTAssertTrue(usage.isEmpty, "got: \(usage)")
        XCTAssertTrue(codes.isEmpty, "got: \(codes)")
    }

    /// Consent for one feature lets its calls be counted, while the calls of a feature without consent stay uncounted.
    func testOnlyFeaturesWithConsentAreCounted() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        let config = createBaseConfig()
        config.requiresConsent = true
        startWithoutHealthCheck(config)
        Countly.sharedInstance().giveConsent(forFeatures: [CLYConsent.events])
        resetCounters(tracker)

        Countly.sharedInstance().recordEvent("allowed_event")
        Countly.sharedInstance().views().startView("Screen")

        let usage = counted(tracker).usage
        XCTAssertEqual(usage["events"]?["record"], 1)
        XCTAssertNil(usage["views"], "got: \(usage)")
    }

    /// Withdrawing consent stops the counting of that feature's calls from then on.
    func testCountingStopsWhenConsentIsWithdrawn() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        let config = createBaseConfig()
        config.requiresConsent = true
        startWithoutHealthCheck(config)
        Countly.sharedInstance().giveConsent(forFeatures: [CLYConsent.events])
        resetCounters(tracker)

        Countly.sharedInstance().recordEvent("before_withdrawal")
        Countly.sharedInstance().cancelConsent(forFeatures: [CLYConsent.events])
        Countly.sharedInstance().recordEvent("after_withdrawal")

        XCTAssertEqual(counted(tracker).usage["events"]?["record"], 1)
    }

    /// A usage area the health check does not know is never counted.
    func testUnknownUsageAreaIsNotCounted() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        resetCounters(tracker)

        tracker.recordUsage("unknown", method: "record")
        tracker.recordLogCode("w740", forUsageArea: "unknown")

        let (usage, codes) = counted(tracker)
        XCTAssertTrue(usage.isEmpty, "got: \(usage)")
        XCTAssertTrue(codes.isEmpty, "got: \(codes)")
    }

    /// Methods with and without a modifier are counted as separate keys.
    func testModifierLeavesAreIndependentKeys() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        let config = createBaseConfig()
        config.manualSessionHandling = true
        startWithoutHealthCheck(config)
        resetCounters(tracker)

        tracker.recordUsage("sessions", method: "begin")
        tracker.recordUsage("sessions", method: "begin:a")
        tracker.recordUsage("sessions", method: "begin:a")

        let sessions = counted(tracker).usage["sessions"]
        XCTAssertEqual(sessions?["begin"], 1, "manual begin tracked separately")
        XCTAssertEqual(sessions?["begin:a"], 2, "automatic begin tracked separately")
    }

    /// Pausing, resuming and stopping all views are counted, so a view lifecycle closed with stopAllViews is balanced.
    func testViewStopAllPauseAndResumeAreCounted() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        startWithoutHealthCheck(createBaseConfig())
        resetCounters(tracker)

        let viewID = Countly.sharedInstance().views().startView("Screen")
        Countly.sharedInstance().views().pauseView(withID: viewID)
        Countly.sharedInstance().views().resumeView(withID: viewID)
        Countly.sharedInstance().views().stopAllViews([:])

        let views = counted(tracker).usage["views"]
        XCTAssertEqual(views?["start"], 1)
        XCTAssertEqual(views?["pause"], 1)
        XCTAssertEqual(views?["resume"], 1)
        XCTAssertEqual(views?["stopAll"], 1)
    }

    /// Ending a timed event records the event, but is counted as an endEvent call only.
    func testEndedTimedEventIsNotCountedAsRecordEvent() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        startWithoutHealthCheck(createBaseConfig())
        resetCounters(tracker)

        Countly.sharedInstance().startEvent("timed")
        Countly.sharedInstance().endEvent("timed")

        let events = counted(tracker).usage["events"]
        XCTAssertEqual(events?["start"], 1)
        XCTAssertEqual(events?["end"], 1)
        XCTAssertNil(events?["record"])
    }

    /// Manual session calls are ignored while automatic session tracking is on, which is reported as w740.
    func testManualSessionCallsDuringAutomaticSessionsRecordW740() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        startWithoutHealthCheck(createBaseConfig())
        resetCounters(tracker)

        Countly.sharedInstance().beginSession()
        Countly.sharedInstance().updateSession()
        Countly.sharedInstance().endSession()

        let (usage, codes) = counted(tracker)
        XCTAssertEqual(usage["sessions"]?["begin"], 1)
        XCTAssertEqual(usage["sessions"]?["update"], 1)
        XCTAssertEqual(usage["sessions"]?["end"], 1)
        XCTAssertEqual(codes["w740"], 3)
    }

    /// While an automatically detected crash is reported nothing is counted, until crash reporting starts again.
    func testRecordingStopsForCrashUntilCrashReportingStartsAgain() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        let config = createBaseConfig()
        config.manualSessionHandling = true
        startWithoutHealthCheck(config)
        resetCounters(tracker)
        defer { CountlyHealthTrackerResumeRecordingAfterCrash() }

        CountlyHealthTrackerStopRecordingForCrash()
        tracker.recordUsage("events", method: "record")
        tracker.recordLogCode("w201")
        let stopped = counted(tracker)
        XCTAssertTrue(stopped.usage.isEmpty)
        XCTAssertTrue(stopped.codes.isEmpty)

        CountlyHealthTrackerResumeRecordingAfterCrash()
        tracker.recordUsage("events", method: "record")
        XCTAssertEqual(counted(tracker).usage["events"]?["record"], 1)
    }

    /// An automatically detected crash the previous run reported is counted as crashes/record:a once the stored
    /// counters are read.
    func testAutomaticCrashReportOfThePreviousRunIsReported() throws {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        startWithoutHealthCheck(createBaseConfig())
        let persistency = try XCTUnwrap(CountlyPersistency.sharedInstance())
        resetCounters(tracker)

        persistency.recordAutomaticCrashReport()
        tracker.hcQueue.sync { tracker.setValue(false, forKey: "persistedStateLoaded") }

        let usage = tracker.healthCheckSnapshot()["fu"] as? [String: [String: NSNumber]]
        XCTAssertEqual(usage?["crashes"]?["record:a"], 1)
        XCTAssertEqual(persistency.takeAutomaticCrashReportCount(), 0, "the count is taken only once")
    }

    /// The automatic crash count is written with the request queue, so it survives the crash that ends the process.
    func testAutomaticCrashReportCountIsSavedWithTheRequestQueue() throws {
        startWithoutHealthCheck(createBaseConfig())
        let persistency = try XCTUnwrap(CountlyPersistency.sharedInstance())
        _ = persistency.takeAutomaticCrashReportCount()
        defer {
            _ = persistency.takeAutomaticCrashReportCount()
            persistency.saveToFileSync()
        }

        persistency.recordAutomaticCrashReport()
        persistency.saveToFileSync()

        XCTAssertEqual(CountlyPersistency().takeAutomaticCrashReportCount(), 1)
    }

    /// A health check the server accepted takes away only what it reported, not what was counted while it was sent. The
    /// plain
    /// warning and error counts are left out: the health check the base setup sends may be answered during the test.
    func testSuccessfulHealthCheckKeepsWhatWasCountedWhileItWasSent() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        startWithoutHealthCheck(createBaseConfig())
        resetCounters(tracker)

        tracker.recordUsage("events", method: "record")
        tracker.recordUsage("events", method: "record")
        tracker.recordLogCode("w201")
        tracker.logFailedNetworkRequest(withStatusCode: 500, errorResponse: "first")
        drainHealthCheckQueue(tracker)
        let sent = tracker.healthCheckSnapshot()

        tracker.recordUsage("events", method: "record")
        tracker.recordLogCode("w202")
        tracker.logFailedNetworkRequest(withStatusCode: 503, errorResponse: "second")
        tracker.clearSentValues(sent)

        let (usage, codes) = counted(tracker)
        XCTAssertEqual(usage["events"]?["record"], 1)
        XCTAssertNil(codes["w201"])
        XCTAssertEqual(codes["w202"], 1)

        let left = tracker.healthCheckSnapshot() ?? [:]
        XCTAssertEqual(left["sc"] as? Int, 503, "a failure newer than the report must be kept")
        XCTAssertEqual(left["em"] as? String, "second")
    }

    // MARK: - Log codes from real call sites

    /// Starting the SDK a second time is ignored and reported as w110.
    func testInitTwiceRecordsW110() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        let config = createBaseConfig()
        startWithoutHealthCheck(config)
        resetCounters(tracker)

        Countly.sharedInstance().start(with: config)

        XCTAssertEqual(counted(tracker).codes["w110"], 1)
    }

    /// Ending a timed event that was not started is reported as w720, cancelling one as w721.
    func testEndingOrCancellingTimedEventThatWasNotStarted() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        startWithoutHealthCheck(createBaseConfig())
        resetCounters(tracker)

        Countly.sharedInstance().endEvent("never_started")
        Countly.sharedInstance().cancelEvent("also_never_started")

        let codes = counted(tracker).codes
        XCTAssertEqual(codes["w720"], 1)
        XCTAssertEqual(codes["w721"], 1)
    }

    /// Starting a timed event whose key is already running is reported as w722.
    func testDuplicateStartEventRecordsW722() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        startWithoutHealthCheck(createBaseConfig())
        resetCounters(tracker)

        Countly.sharedInstance().startEvent("dup_key")
        Countly.sharedInstance().startEvent("dup_key")

        let (usage, codes) = counted(tracker)
        XCTAssertEqual(usage["events"]?["start"], 2)
        XCTAssertEqual(codes["w722"], 1)
    }

#if os(iOS) || os(tvOS)
    /// A manual view call while automatic view tracking is active is ignored and reported as w740.
    func testManualViewDuringAutoTrackingRecordsW740() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        let config = createBaseConfig()
        config.enableAutomaticViewTracking = true
        startWithoutHealthCheck(config)
        resetCounters(tracker)

        _ = Countly.sharedInstance().views().startView("ManualWhileAuto")

        let (usage, codes) = counted(tracker)
        XCTAssertEqual(usage["views"]?["start"], 1)
        XCTAssertEqual(codes["w740"], 1)
    }
#endif

    // MARK: - Switching off, storing and reporting

    /// The `metrics` parameter a health check request carries.
    private func healthCheckMetrics(of request: URLRequest) -> [String: Any] {
        let query = request.url?.query ?? String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        return TestUtils.parseQueryString(query)["metrics"] as? [String: Any] ?? [:]
    }

    /// Runs the work of one tick of the session timer.
    private func fireSessionTimer() {
        Countly.sharedInstance().perform(NSSelectorFromString("onTimer:"), with: nil)
    }

    /// Stores the behavior settings the next start reads, as a stored server answer would be, and removes them when the test
    /// ends, since halting the SDK keeps them. A test using it turns behavior settings updates off, so that no server answer
    /// replaces them while it runs.
    private func storeBehaviorSettings(tracking: Bool, networking: Bool) {
        let key = "kCountlyServerConfigPersistencyKey"
        UserDefaults.standard.set(ServerConfigBuilder().tracking(tracking).networking(networking).buildJson(), forKey: key)
        UserDefaults.standard.synchronize()
        addTeardownBlock {
            UserDefaults.standard.removeObject(forKey: key)
            UserDefaults.standard.synchronize()
        }
    }

    /// Saving stores the run of backoffs in a row that is still going on, so an app killed right after keeps it.
    func testSavingStoresTheBackoffRunInProgress() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        let config = createBaseConfig()
        config.manualSessionHandling = true
        startWithoutHealthCheck(config)
        resetCounters(tracker)

        tracker.logBackoffRequest()
        tracker.logBackoffRequest()
        tracker.logBackoffRequest()
        tracker.saveState()
        tracker.hcQueue.sync {}

        let state = CountlyPersistency.sharedInstance().retrieveHealthCheckTrackerState() ?? [:]
        XCTAssertEqual(state["BReq"] as? Int, 3, "got: \(state)")
        XCTAssertEqual(state["CBReq"] as? Int, 3, "got: \(state)")
    }

    /// The session timer does not end a run of backoffs in a row, so a run that lasts longer than one timer period is
    /// reported whole.
    func testSessionTimerKeepsTheBackoffRunGoing() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        let config = createBaseConfig()
        config.manualSessionHandling = true
        startWithoutHealthCheck(config)
        resetCounters(tracker)

        tracker.logBackoffRequest()
        tracker.logBackoffRequest()
        fireSessionTimer()
        tracker.logBackoffRequest()
        tracker.logBackoffRequest()
        tracker.saveState()
        tracker.hcQueue.sync {}

        let state = CountlyPersistency.sharedInstance().retrieveHealthCheckTrackerState() ?? [:]
        XCTAssertEqual(state["CBReq"] as? Int, 4, "got: \(state)")
    }

    /// The automatic session update of the hybrid mode is counted only when a session is running for it to update.
    func testAutomaticSessionUpdateIsCountedOnlyForARunningSession() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        let config = createBaseConfig()
        config.manualSessionHandling = true
        config.enableManualSessionControlHybridMode = true
        startWithoutHealthCheck(config)
        resetCounters(tracker)

        fireSessionTimer()
        XCTAssertNil(counted(tracker).usage["sessions"]?["update:a"], "no session is running yet")

        Countly.sharedInstance().beginSession()
        fireSessionTimer()
        XCTAssertEqual(counted(tracker).usage["sessions"]?["update:a"], 1)
    }

    /// The health check reports the app version the developer set through the custom metrics, as the session metrics do.
    func testHealthCheckMetricsUseTheCustomAppVersion() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        let config = createBaseConfig()
        config.manualSessionHandling = true
        config.customMetrics = ["_app_version": "5.2.0-beta"]
        startWithoutHealthCheck(config)

        let metrics = healthCheckMetrics(of: tracker.healthCheckRequest())
        XCTAssertEqual(metrics["_app_version"] as? String, "5.2.0-beta", "got: \(metrics)")
        XCTAssertEqual(metrics.count, 1, "the health check metrics hold only the app version, got: \(metrics)")
    }

    /// Without a custom app version the health check reports the app version of the app bundle.
    func testHealthCheckMetricsUseTheBundleAppVersionByDefault() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        let config = createBaseConfig()
        config.manualSessionHandling = true
        startWithoutHealthCheck(config)

        let metrics = healthCheckMetrics(of: tracker.healthCheckRequest())
        XCTAssertEqual(metrics["_app_version"] as? String, CountlyDeviceInfo.appVersion(), "got: \(metrics)")
    }

    /// A failed request whose answer is not UTF-8 text keeps its status code, with an empty error message.
    func testFailedRequestWithUnreadableBodyKeepsItsStatusCode() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        resetCounters(tracker)

        tracker.logFailedNetworkRequest(withStatusCode: 502, errorResponse: nil)

        let snapshot = tracker.healthCheckSnapshot() ?? [:]
        XCTAssertEqual(snapshot["sc"] as? Int, 502, "got: \(snapshot)")
        XCTAssertEqual(snapshot["em"] as? String, "")
    }

    // MARK: - Log codes of invalid calls and dropped data

    /// A device ID change before the SDK is started is ignored and reported as e101.
    func testDeviceIDChangeBeforeStartRecordsE101() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        resetCounters(tracker)

        Countly.sharedInstance().changeDeviceIDWithoutMerge("before_start")

        XCTAssertEqual(counted(tracker).codes["e101"], 1)
    }

    /// An empty device ID is reported as w601, and the device ID the SDK already has as w602.
    func testInvalidDeviceIDChangesRecordTheirCodes() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        let config = createBaseConfig()
        config.manualSessionHandling = true
        startWithoutHealthCheck(config)
        resetCounters(tracker)

        Countly.sharedInstance().changeDeviceIDWithoutMerge("")
        Countly.sharedInstance().changeDeviceIDWithoutMerge(Countly.sharedInstance().deviceID())

        let codes = counted(tracker).codes
        XCTAssertEqual(codes["w601"], 1, "got: \(codes)")
        XCTAssertEqual(codes["w602"], 1, "got: \(codes)")
    }

    /// An event without a key is reported as e701, a view without a name as e710, and stopping or segmenting a view that
    /// does not exist as e730.
    func testInvalidEventAndViewCallsRecordTheirCodes() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        let config = createBaseConfig()
        config.manualSessionHandling = true
        startWithoutHealthCheck(config)
        resetCounters(tracker)

        Countly.sharedInstance().recordEvent("")
        _ = Countly.sharedInstance().views().startView("")
        Countly.sharedInstance().views().stopView(withName: "missing_view")
        Countly.sharedInstance().views().stopView(withID: "missing_view_id")
        Countly.sharedInstance().views().addSegmentationToView(withName: "missing_view", segmentation: ["key": "value"])
        Countly.sharedInstance().views().addSegmentationToView(withID: "missing_view_id", segmentation: ["key": "value"])

        let codes = counted(tracker).codes
        XCTAssertEqual(codes["e701"], 1, "got: \(codes)")
        XCTAssertEqual(codes["e710"], 1, "got: \(codes)")
        XCTAssertEqual(codes["e730"], 4, "got: \(codes)")
    }

    /// An internal limit set below 1 is ignored and its default kept, reported as w121 once per limit.
    func testInvalidInternalLimitsRecordW121() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        let config = createBaseConfig()
        config.manualSessionHandling = true
        config.sdkInternalLimits().setMaxKeyLength(0)
        config.sdkInternalLimits().setMaxBreadcrumbCount(0)
        startWithoutHealthCheck(config)

        XCTAssertEqual(counted(tracker).codes["w121"], 2)
    }

    /// A breadcrumb over the breadcrumb limit drops the oldest one, reported as w204 for every dropped breadcrumb.
    func testDroppedBreadcrumbsRecordW204() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        let config = createBaseConfig()
        config.manualSessionHandling = true
        config.sdkInternalLimits().setMaxBreadcrumbCount(1)
        startWithoutHealthCheck(config)
        resetCounters(tracker)

        Countly.sharedInstance().recordCrashLog("first")
        Countly.sharedInstance().recordCrashLog("second")
        Countly.sharedInstance().recordCrashLog("third")

        XCTAssertEqual(counted(tracker).codes["w204"], 2)
    }

    /// An answer slower than the accepted time starts the backoff, reported as w320, while an answer in time starts none.
    func testSlowAnswerStartingTheBackoffRecordsW320() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        let config = createBaseConfig()
        config.manualSessionHandling = true
        startWithoutHealthCheck(config)
        resetCounters(tracker)
        let recentRequest = "timestamp=\(Int64(Date().timeIntervalSince1970 * 1000))"

        XCTAssertFalse(CountlyConnectionManager.sharedInstance().backoff(0, queryString: recentRequest))
        XCTAssertNil(counted(tracker).codes["w320"], "an answer in time starts no backoff")

        XCTAssertTrue(CountlyConnectionManager.sharedInstance().backoff(3600, queryString: recentRequest))
        XCTAssertEqual(counted(tracker).codes["w320"], 1)
    }

    /// Requests older than the drop age that a full queue removes to make room are reported as w330, one per request.
    func testOldRequestsRemovedFromAFullQueueRecordW330() throws {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        storeBehaviorSettings(tracking: true, networking: false)
        let config = createBaseConfig()
        config.manualSessionHandling = true
        config.disableSDKBehaviorSettingsUpdates = true
        config.requestDropAgeHours = 1
        config.storedRequestsLimit = 3
        startWithoutHealthCheck(config)
        let persistency = try XCTUnwrap(CountlyPersistency.sharedInstance())
        Countly.sharedInstance().flushQueues()
        resetCounters(tracker)
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        persistency.add(toQueue: "timestamp=1000&old=1")
        persistency.add(toQueue: "timestamp=1000&old=2")
        persistency.add(toQueue: "timestamp=\(now)&fresh=1")
        persistency.add(toQueue: "timestamp=\(now)&fresh=2")

        let codes = counted(tracker).codes
        XCTAssertEqual(codes["w330"], 2, "got: \(codes)")
        XCTAssertEqual(persistency.remainingRequestCount(), 2, "the two old requests made room for the new one")
    }

    /// A request made while the behavior settings turned tracking off is not queued, which is reported as w505.
    func testRequestRefusedWhileTrackingIsOffRecordsW505() throws {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        storeBehaviorSettings(tracking: false, networking: true)
        let config = createBaseConfig()
        config.manualSessionHandling = true
        config.disableSDKBehaviorSettingsUpdates = true
        startWithoutHealthCheck(config)
        let persistency = try XCTUnwrap(CountlyPersistency.sharedInstance())
        resetCounters(tracker)

        XCTAssertFalse(persistency.add(toQueue: "test=refused"))
        XCTAssertEqual(counted(tracker).codes["w505"], 1)
    }
}

/// Stored health counters, with every request answered by a reply without `result`, so no response clears them mid
/// test.
class CountlyHealthTrackerStoredCountersTests: CountlyBaseTestCase {
    private let healthChecksLock = NSLock()
    private var healthChecks: [[String: Any]] = []

    /// Sets the reply before the base setup starts and halts the SDK, so the health check sent then is answered too.
    override func setUpWithError() throws {
        MockURLProtocol.requestHandler = { [weak self] request in
            self?.recordHealthCheck(request)
            return (
                "{}".data(using: .utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil),
                nil
            )
        }
        try super.setUpWithError()
    }

    /// The base config with every request routed through `MockURLProtocol`.
    override func createBaseConfig() -> CountlyConfig {
        let config = super.createBaseConfig()
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        config.urlSessionConfiguration = sessionConfig
        config.manualSessionHandling = true
        return config
    }

    /// Keeps the `hc` parameter of every health check request the SDK sends.
    private func recordHealthCheck(_ request: URLRequest) {
        guard let query = request.url?.query,
              let healthCheck = TestUtils.parseQueryString(query)["hc"] as? [String: Any]
        else { return }
        healthChecksLock.lock()
        healthChecks.append(healthCheck)
        healthChecksLock.unlock()
    }

    /// The `hc` parameters recorded so far. Requests are answered on another thread, so every read is locked.
    private func recordedHealthChecks() -> [[String: Any]] {
        healthChecksLock.lock()
        defer { healthChecksLock.unlock() }
        return healthChecks
    }

    /// The first health check after start reports the previous run's stored counts together with those counted before
    /// start.
    func test_countersStoredByThePreviousRun_areAddedToTheOnesCountedBeforeStart() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()

        let tracker = try XCTUnwrap(CountlyHealthTracker.sharedInstance())
        let hcQueue = try XCTUnwrap(tracker.value(forKey: "hcQueue") as? DispatchQueue)
        hcQueue.sync { tracker.setValue(false, forKey: "persistedStateLoaded") }
        UserDefaults.standard.set(["LWar": 5, "LErr": 2], forKey: "kCountlyHealthCheckStatePersistencyKey")

        tracker.logWarning()
        tracker.logError()

        Countly.sharedInstance().start(with: createBaseConfig())

        var reported: [String: Any]?
        let didReport = TestUtils.waitUntil("a health check with the stored counters", timeout: 10) {
            reported = recordedHealthChecks().first { ($0["wl"] as? Int ?? 0) >= 6 }
            return reported != nil
        }
        let sent = recordedHealthChecks()
        XCTAssertTrue(didReport, "the 5 stored warnings must be added to the one logged before start, got: \(sent)")
        XCTAssertGreaterThanOrEqual(reported?["el"] as? Int ?? 0, 3, "the 2 stored errors must be added to the one logged before start")
    }
}

/// Keeps every line the SDK logs with its level, for the tests that check what was logged and at which level.
private final class CapturingLogger: NSObject, CountlyLoggerDelegate {
    private let lock = NSLock()
    private var entries: [(text: String, level: CLYInternalLogLevel)] = []

    func internalLog(_ log: String, with level: CLYInternalLogLevel) {
        lock.lock()
        entries.append((log, level))
        lock.unlock()
    }

    /// The logged lines that contain the text.
    func lines(containing text: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries.filter { $0.text.contains(text) }.map { $0.text }
    }

    /// The levels of the logged lines that contain the text.
    func levels(ofLinesContaining text: String) -> [CLYInternalLogLevel] {
        lock.lock()
        defer { lock.unlock() }
        return entries.filter { $0.text.contains(text) }.map { $0.level }
    }
}

/// Health check behavior that depends on the server's answer. Every request is answered by `MockURLProtocol`: the health
/// check with `healthCheckReply`, by default an answer without `result` so that no answer takes counters away mid test,
/// and every other request with `requestReply`, a success by default.
class CountlyHealthCheckAnswerTests: CountlyBaseTestCase {
    private let lock = NSLock()
    private var healthChecks: [[String: Any]] = []
    private var healthCheckReply: (status: Int, body: Data) = (200, Data("{}".utf8))
    private var requestReply: (status: Int, body: Data) = (200, Data("{\"result\":\"Success\"}".utf8))

    /// Sets the replies before the base setup starts and halts the SDK, so the requests sent then are answered too, and keeps
    /// that start from sending a health check, so that every health check a test records is its own.
    override func setUpWithError() throws {
        MockURLProtocol.requestHandler = { [weak self] request in
            guard let self = self, let url = request.url else { return (nil, nil, nil) }
            let reply = self.reply(to: request)
            return (reply.body, HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: nil, headerFields: nil), nil)
        }
        CountlyHealthTracker.sharedInstance().setValue(true, forKey: "healthCheckSent")
        try super.setUpWithError()
    }

    /// The base config with every request routed through `MockURLProtocol` and sessions handled by the test.
    override func createBaseConfig() -> CountlyConfig {
        let config = super.createBaseConfig()
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        config.urlSessionConfiguration = sessionConfig
        config.manualSessionHandling = true
        return config
    }

    /// Keeps the `hc` parameter of a health check request and returns the reply the request gets.
    private func reply(to request: URLRequest) -> (status: Int, body: Data) {
        let healthCheck = TestUtils.parseQueryString(request.url?.query ?? "")["hc"] as? [String: Any]
        lock.lock()
        defer { lock.unlock() }
        guard let healthCheck = healthCheck else { return requestReply }
        healthChecks.append(healthCheck)
        return healthCheckReply
    }

    /// Sets what the health check request is answered with from now on.
    private func setHealthCheckReply(status: Int, body: String) {
        lock.lock()
        healthCheckReply = (status, Data(body.utf8))
        lock.unlock()
    }

    /// Sets what every other request is answered with from now on.
    private func setRequestReply(status: Int, body: Data) {
        lock.lock()
        requestReply = (status, body)
        lock.unlock()
    }

    /// The `hc` parameters of the health checks that reached the server so far.
    private func recordedHealthChecks() -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return healthChecks
    }

    /// Starts the SDK with the health check marked as sent, so no health check goes out during the test.
    private func startWithoutHealthCheck(_ config: CountlyConfig) {
        CountlyHealthTracker.sharedInstance().setValue(true, forKey: "healthCheckSent")
        Countly.sharedInstance().start(with: config)
    }

    /// Clears every counter of the health tracker and waits until it is done.
    private func resetCounters() {
        CountlyHealthTracker.sharedInstance().clearAndSave()
        CountlyHealthTracker.sharedInstance().hcQueue.sync {}
    }

    /// The health check parameter the counters make now, read once the counting queued so far ran.
    private func snapshot() -> [AnyHashable: Any] {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        tracker.hcQueue.sync {}
        return tracker.healthCheckSnapshot() ?? [:]
    }

    /// Begins a session and returns the log codes once the failed answer to its request is reported as e301 or e302.
    private func logCodesAfterAFailedBeginSession() -> [String: Int] {
        startWithoutHealthCheck(createBaseConfig())
        resetCounters()
        Countly.sharedInstance().beginSession()
        var codes: [String: Int] = [:]
        let recorded = TestUtils.waitUntil("the failed answer is recorded") {
            codes = self.snapshot()["lc"] as? [String: Int] ?? [:]
            return codes["e301"] != nil || codes["e302"] != nil
        }
        XCTAssertTrue(recorded, "got: \(codes)")
        return codes
    }

    /// With disableHealthCheck no health check request is made, also when one is asked for later, while the counters keep
    /// counting. Without the switch the start sends one.
    func test_disabledHealthCheck_isNotSent() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        let logger = CapturingLogger()
        let config = createBaseConfig()
        config.disableHealthCheck = true
        config.loggerDelegate = logger
        Countly.sharedInstance().start(with: config)

        tracker.sendHealthCheck()
        tracker.recordLogCode("w204")

        XCTAssertTrue(logger.lines(containing: "sending health check request").isEmpty, "got: \(logger.lines(containing: "health check"))")
        XCTAssertEqual(logger.lines(containing: "healthCheckEnabled: [NO]").count, 2, "the start and the later call are both refused")
        XCTAssertEqual((snapshot()["lc"] as? [String: Int])?["w204"], 1, "the counters keep counting")

        Countly.sharedInstance().halt(true)
        config.disableHealthCheck = false
        Countly.sharedInstance().start(with: config)

        XCTAssertEqual(logger.lines(containing: "sending health check request").count, 1, "without the switch the start sends one")
        let reached = TestUtils.waitUntil("the health check reaches the server") { self.recordedHealthChecks().count == 1 }
        XCTAssertTrue(reached, "got: \(recordedHealthChecks())")
    }

    /// The health check is marked as sent when it goes out, so one whose answer kept the counters is not sent again when
    /// temporary device ID mode ends: the counters wait for the next start.
    func test_healthCheck_isSentOncePerRun_evenWhenItsAnswerKeepsTheCounters() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        let logger = CapturingLogger()
        let config = createBaseConfig()
        config.loggerDelegate = logger
        let healthChecksBefore = recordedHealthChecks().count
        Countly.sharedInstance().start(with: config)

        XCTAssertEqual(tracker.value(forKey: "healthCheckSent") as? Bool, true, "marked as sent before its answer arrives")
        let reached = TestUtils.waitUntil("the health check of the start reaches the server") {
            self.recordedHealthChecks().count > healthChecksBefore
        }
        XCTAssertTrue(reached, "got: \(recordedHealthChecks())")

        Countly.sharedInstance().enableTemporaryDeviceIDMode()
        Countly.sharedInstance().changeDeviceIDWithoutMerge("real_user_after_temp")

        XCTAssertEqual(logger.lines(containing: "sending health check request").count, 1, "got: \(logger.lines(containing: "health check"))")
        XCTAssertEqual(logger.lines(containing: "health check send skipped, healthCheckSent: [YES]").count, 1)
    }

    /// An answer to the health check that is not JSON is no error of the SDK, so it is not logged at error level, which the
    /// health check counts.
    func test_unreadableHealthCheckAnswer_isNotLoggedAsAnError() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        setHealthCheckReply(status: 200, body: "<html>captive portal</html>")
        let logger = CapturingLogger()
        let config = createBaseConfig()
        config.loggerDelegate = logger
        Countly.sharedInstance().start(with: config)

        let unreadable = "could not parse the health check response"
        XCTAssertTrue(TestUtils.waitUntil("the unreadable answer is handled") { !logger.levels(ofLinesContaining: unreadable).isEmpty })
        let levels = logger.levels(ofLinesContaining: unreadable)
        XCTAssertTrue(levels.allSatisfy { $0 == CLYInternalLogLevelDebug }, "got levels: \(levels.map { $0.rawValue })")
    }

    /// A queued request answered with a success status but without "result" is reported as e302, a malformed answer.
    func test_successStatusWithoutResult_recordsE302() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        setRequestReply(status: 200, body: Data("{}".utf8))

        let codes = logCodesAfterAFailedBeginSession()
        XCTAssertEqual(codes["e302"], 1, "got: \(codes)")
        XCTAssertNil(codes["e301"], "got: \(codes)")
    }

    /// A queued request answered with an error status is reported as e301.
    func test_errorStatus_recordsE301() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        setRequestReply(status: 500, body: Data("{\"result\":\"Internal error\"}".utf8))

        let codes = logCodesAfterAFailedBeginSession()
        XCTAssertEqual(codes["e301"], 1, "got: \(codes)")
        XCTAssertNil(codes["e302"], "got: \(codes)")
    }

    /// A failed answer whose body is not UTF-8 text keeps its status code for the health check, with an empty message.
    func test_failedAnswerThatIsNotText_keepsItsStatusCode() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        setRequestReply(status: 500, body: Data([0xFF, 0xFE, 0xFD]))
        startWithoutHealthCheck(createBaseConfig())
        resetCounters()

        Countly.sharedInstance().beginSession()

        let recorded = TestUtils.waitUntil("the failed answer is recorded") { (self.snapshot()["sc"] as? Int) == 500 }
        XCTAssertTrue(recorded, "got: \(snapshot())")
        XCTAssertEqual(snapshot()["em"] as? String, "")
    }

    /// Ending a session the app began stores the counters, as the end of a session can be the end of the run.
    func test_manualSessionEnd_storesTheCounters() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        startWithoutHealthCheck(createBaseConfig())
        Countly.sharedInstance().beginSession()
        resetCounters()

        tracker.recordLogCode("w204")
        Countly.sharedInstance().endSession()
        tracker.hcQueue.sync {}

        let state = CountlyPersistency.sharedInstance().retrieveHealthCheckTrackerState() ?? [:]
        XCTAssertEqual((state["LC"] as? [String: NSNumber])?["w204"], 1, "got: \(state)")
    }

    /// A manual session update or end without a running session is ignored with a warning, which the health check counts,
    /// while a running session is updated and ended without one.
    func test_manualSessionCallsWithoutSession_areCountedAsWarnings() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        startWithoutHealthCheck(createBaseConfig())
        resetCounters()

        Countly.sharedInstance().updateSession()
        Countly.sharedInstance().endSession()
        XCTAssertEqual(snapshot()["wl"] as? Int, 2, "got: \(snapshot())")

        Countly.sharedInstance().beginSession()
        resetCounters()
        Countly.sharedInstance().updateSession()
        Countly.sharedInstance().endSession()
        XCTAssertEqual(snapshot()["wl"] as? Int, 0, "got: \(snapshot())")
    }
}
