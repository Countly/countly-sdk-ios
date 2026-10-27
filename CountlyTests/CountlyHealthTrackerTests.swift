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
                CountlyHealthTracker.sharedInstance().sendHealthCheck()
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
                CountlyHealthTracker.sharedInstance().sendHealthCheck()
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

        // Multiple readers accessing errorMessage through sendHealthCheck
        // Capped to avoid exhausting file descriptors from network calls
        for _ in 0..<2 {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                for _ in 0..<50 {
                    autoreleasepool {
                        CountlyHealthTracker.sharedInstance().sendHealthCheck()
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

                        // Immediate read to create contention (capped to avoid file descriptor exhaustion)
                        if i % 200 == 0 {
                            CountlyHealthTracker.sharedInstance().sendHealthCheck()
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
    func testLogFailedNetworkRequest_synchronizedOperationsPerformance() throws {
        // Every `sendHealthCheck` here performs a real, failing DNS lookup wherever HTTP
        // cannot be intercepted, and the watch simulator is slower on top of that, so 550
        // synchronized operations do not fit the 30 second budget. The thread safety this
        // guards is platform independent and is covered on the other four platforms.
        try TestPlatform.skipUnlessHTTPInterceptable()

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

            // Test read performance (fewer iterations as they trigger network requests)
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                for _ in 0..<(iterations / 10) {
                    CountlyHealthTracker.sharedInstance().sendHealthCheck()
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

    /// Persists the counters and waits until the health tracker queue ran the work queued on it, also the work that work queues.
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

    /// Starts the SDK with the health check marked as sent, so no server answer takes counters away while a test reads them.
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

        let hc = healthCheckParameter(of: tracker.healthCheckRequest())
        XCTAssertEqual((hc["fu"] as? [String: [String: Int]])?["events"]?["record"], 1, "got: \(hc)")
        XCTAssertEqual((hc["lc"] as? [String: Int])?["w204"], 1, "got: \(hc)")
    }

    /// "fu" and "lc" are sent also when nothing was counted, so the server can tell an SDK that reports them from one that does not.
    func testHealthCheckRequestAlwaysCarriesFuAndLc() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        startWithoutHealthCheck(createBaseConfig())
        resetCounters(tracker)

        let hc = healthCheckParameter(of: tracker.healthCheckRequest())
        XCTAssertEqual((hc["fu"] as? [String: Any])?.isEmpty, true, "got: \(hc)")
        XCTAssertEqual((hc["lc"] as? [String: Any])?.isEmpty, true, "got: \(hc)")
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

    /// An event dropped for missing consent is reported as w401.
    func testConsentBlockedRecordsLogCode() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        let config = createBaseConfig()
        config.requiresConsent = true
        startWithoutHealthCheck(config)
        resetCounters(tracker)

        Countly.sharedInstance().recordEvent("blocked_event")

        XCTAssertEqual(counted(tracker).codes["w401"], 1)
    }

    /// Methods with and without a modifier are counted as separate keys.
    func testModifierLeavesAreIndependentKeys() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
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

    /// An automatically detected crash the previous run reported is counted as crashes/record:a once the stored counters are read.
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

    /// A health check the server accepted takes away only what it reported, not what was counted while it was sent. The plain
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

        let left = tracker.healthCheckSnapshot()
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

        let _ = Countly.sharedInstance().views().startView("ManualWhileAuto")

        let (usage, codes) = counted(tracker)
        XCTAssertEqual(usage["views"]?["start"], 1)
        XCTAssertEqual(codes["w740"], 1)
    }
#endif
}

/// Stored health counters, with every request answered by a reply without `result`, so no response clears them mid test.
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

    /// The first health check after start reports the previous run's stored counts together with those counted before start.
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
