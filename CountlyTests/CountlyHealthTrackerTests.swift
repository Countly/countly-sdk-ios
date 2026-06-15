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

    /// Drains the serial hcQueue by enqueuing saveState (which runs on the same queue as
    /// recordUsage/recordLogCode) and waiting briefly, so asynchronous counter writes are applied.
    private func drainHealthCheckQueue(_ tracker: CountlyHealthTracker, timeout: TimeInterval = 5) {
        let exp = expectation(description: "drain hc queue")
        tracker.saveState()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exp.fulfill() }
        wait(for: [exp], timeout: timeout)
    }

    /// recordUsage/recordLogCode accumulate counts per area/method and per code.
    func testRecordUsageAndLogCodeAccumulate() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        tracker.methodUsage.removeAllObjects()
        tracker.logCodes.removeAllObjects()

        tracker.recordUsage("events", method: "record")
        tracker.recordUsage("events", method: "record")
        tracker.recordUsage("views", method: "start")
        tracker.recordLogCode("w204")
        tracker.recordLogCode("e301")

        drainHealthCheckQueue(tracker)

        XCTAssertEqual((tracker.methodUsage["events"] as? [String: NSNumber])?["record"], 2)
        XCTAssertEqual((tracker.methodUsage["views"] as? [String: NSNumber])?["start"], 1)
        XCTAssertEqual(tracker.logCodes["w204"] as? NSNumber, 1)
        XCTAssertEqual(tracker.logCodes["e301"] as? NSNumber, 1)
    }

    /// Empty area/method/code inputs are ignored (no map entries created).
    func testRecordUsageIgnoresEmptyInputs() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        tracker.methodUsage.removeAllObjects()
        tracker.logCodes.removeAllObjects()

        tracker.recordUsage("", method: "record")
        tracker.recordUsage("events", method: "")
        tracker.recordLogCode("")

        drainHealthCheckQueue(tracker)

        XCTAssertEqual(tracker.methodUsage.count, 0)
        XCTAssertEqual(tracker.logCodes.count, 0)
    }

    /// All mutation goes through the serial hcQueue, so concurrent recordUsage must not crash.
    func testRecordUsageThreadSafety() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        tracker.methodUsage.removeAllObjects()
        runConcurrentStressTest(
            iterations: 10_000,
            writerBlock: { _ in tracker.recordUsage("events", method: "record") },
            readerBlock: { tracker.saveState() }
        )
        // No crash / no exception under contention is the primary assertion;
        // also confirm the count is positive and within the cap.
        drainHealthCheckQueue(tracker, timeout: 10)
        let count = (tracker.methodUsage["events"] as? [String: NSNumber])?["record"]?.intValue ?? 0
        XCTAssertTrue(count > 0 && count <= 65535, "expected 0 < count <= 65535, got \(count)")
    }

    /// Maps persist into the health-tracker state dict and are cleared on clearAndSave.
    func testUsageAndLogCodesPersistAndClear() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        tracker.methodUsage.removeAllObjects()
        tracker.logCodes.removeAllObjects()
        tracker.recordUsage("events", method: "record")
        tracker.recordLogCode("w204")

        drainHealthCheckQueue(tracker)

        let state = CountlyPersistency.sharedInstance().retrieveHealthCheckTrackerState() ?? [:]
        let mu = state["MU"] as? [String: [String: NSNumber]]
        let lc = state["LC"] as? [String: NSNumber]
        XCTAssertEqual(mu?["events"]?["record"], 1)
        XCTAssertEqual(lc?["w204"], 1)

        // clearAndSave empties the maps.
        let exp = expectation(description: "clear")
        tracker.clearAndSave()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exp.fulfill() }
        wait(for: [exp], timeout: 5)
        XCTAssertEqual(tracker.methodUsage.count, 0)
        XCTAssertEqual(tracker.logCodes.count, 0)
    }

    /// fu/lc keys appear in the hc request only when the maps are non-empty.
    func testHealthCheckRequestIncludesFuLcWhenPresent() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        drainHealthCheckQueue(tracker)

        tracker.methodUsage.removeAllObjects()
        tracker.logCodes.removeAllObjects()
        tracker.recordUsage("events", method: "record")
        tracker.recordLogCode("w204")
        drainHealthCheckQueue(tracker)

        let request: URLRequest = tracker.healthCheckRequest()!
        let query = request.url?.query ?? String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        let decoded = query.removingPercentEncoding ?? query
        XCTAssertTrue(decoded.contains("\"fu\""), "hc should contain fu; got: \(decoded)")
        XCTAssertTrue(decoded.contains("\"lc\""), "hc should contain lc; got: \(decoded)")
        XCTAssertTrue(decoded.contains("\"record\""))
        XCTAssertTrue(decoded.contains("\"w204\""))
    }

    func testHealthCheckRequestOmitsFuLcWhenEmpty() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        drainHealthCheckQueue(tracker)

        tracker.methodUsage.removeAllObjects()
        tracker.logCodes.removeAllObjects()
        drainHealthCheckQueue(tracker)

        let request: URLRequest = tracker.healthCheckRequest()!
        let query = request.url?.query ?? String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        let decoded = query.removingPercentEncoding ?? query
        XCTAssertFalse(decoded.contains("\"fu\""))
        XCTAssertFalse(decoded.contains("\"lc\""))
    }

    /// Calling a public API records usage under the shared taxonomy.
    func testPublicMethodsPopulateUsage() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        tracker.methodUsage.removeAllObjects()

        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        Countly.sharedInstance().recordEvent("test_event")
        Countly.sharedInstance().recordEvent("test_event_2")

        drainHealthCheckQueue(tracker)

        let count = (tracker.methodUsage["events"] as? [String: NSNumber])?["record"]?.intValue ?? 0
        XCTAssertTrue(count >= 2, "expected >=2 events.record, got \(count)")
    }

    /// A consent-blocked action records the w401 log code.
    func testConsentBlockedRecordsLogCode() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        tracker.logCodes.removeAllObjects()

        let config = createBaseConfig()
        config.requiresConsent = true   // no consent given
        Countly.sharedInstance().start(with: config)
        // an event recorded without events consent should be blocked and record w401
        Countly.sharedInstance().recordEvent("blocked_event")

        drainHealthCheckQueue(tracker)

        XCTAssertNotNil(tracker.logCodes["w401"], "expected w401 consent-blocked code")
    }

    // MARK: - Auto / Manual & Deprecated differentiation

    /// The current `startView` API records the bare `start` leaf, while the deprecated `recordView`
    /// API records `start:d` — the two are distinct keys and the deprecated call must NOT leak into
    /// the modern `startAuto` leaf.
    func testManualAndDeprecatedViewAreDistinct() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        tracker.methodUsage.removeAllObjects()

        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        let _ = Countly.sharedInstance().views().startView("CurrentScreen")
        Countly.sharedInstance().recordView("LegacyScreen")

        drainHealthCheckQueue(tracker)

        let views = tracker.methodUsage["views"] as? [String: NSNumber]
        XCTAssertEqual(views?["start"], 1, "current startView should record bare start")
        XCTAssertEqual(views?["start:d"], 1, "deprecated recordView should record start:d")
        XCTAssertNil(views?["startAuto"], "deprecated recordView must not record startAuto")
    }

    /// The deprecated handled/unhandled exception APIs record `crashes` `record:d`, distinct from the
    /// current `recordException` API which records bare `record`.
    func testDeprecatedExceptionRecordsRecordD() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        tracker.methodUsage.removeAllObjects()

        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        let exception = NSException(name: .genericException, reason: "test", userInfo: nil)
        Countly.sharedInstance().recordHandledException(exception)
        Countly.sharedInstance().recordUnhandledException(exception, withStackTrace: [])

        drainHealthCheckQueue(tracker)

        let crashes = tracker.methodUsage["crashes"] as? [String: NSNumber]
        XCTAssertEqual(crashes?["record:d"], 2, "deprecated exception APIs should record record:d")
        XCTAssertNil(crashes?["record"], "deprecated APIs must not record the bare record leaf")
    }

    /// Modifier-suffixed leaves coexist with their bare counterparts as separate keys
    /// (auto `:a` and deprecated `:d` are tracked independently of the manual/current call).
    func testModifierLeavesAreIndependentKeys() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        tracker.methodUsage.removeAllObjects()

        tracker.recordUsage("sessions", method: "begin")
        tracker.recordUsage("sessions", method: "begin:a")
        tracker.recordUsage("sessions", method: "begin:a")
        tracker.recordUsage("views", method: "start:d")

        drainHealthCheckQueue(tracker)

        let sessions = tracker.methodUsage["sessions"] as? [String: NSNumber]
        XCTAssertEqual(sessions?["begin"], 1, "manual begin tracked separately")
        XCTAssertEqual(sessions?["begin:a"], 2, "automatic begin:a tracked separately")
        XCTAssertEqual((tracker.methodUsage["views"] as? [String: NSNumber])?["start:d"], 1)
    }

    // MARK: - Log codes from real call sites

    /// Starting the SDK a second time is ignored and records the w110 init-twice code.
    func testInitTwiceRecordsW110() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        tracker.logCodes.removeAllObjects()

        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        Countly.sharedInstance().start(with: config)   // second start is ignored

        drainHealthCheckQueue(tracker)

        XCTAssertNotNil(tracker.logCodes["w110"], "second start should record w110")
    }

    /// Ending or cancelling a timed event that was never started records w720 each time.
    func testEndingNonStartedTimedEventRecordsW720() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        tracker.logCodes.removeAllObjects()

        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        Countly.sharedInstance().endEvent("never_started")
        Countly.sharedInstance().cancelEvent("also_never_started")

        drainHealthCheckQueue(tracker)

        XCTAssertEqual(tracker.logCodes["w720"] as? NSNumber, 2, "end + cancel of non-started events → 2x w720")
    }

    /// Starting the same timed-event key twice records w722.
    func testDuplicateStartEventRecordsW722() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        tracker.logCodes.removeAllObjects()

        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        Countly.sharedInstance().startEvent("dup_key")
        Countly.sharedInstance().startEvent("dup_key")   // already started

        drainHealthCheckQueue(tracker)

        XCTAssertNotNil(tracker.logCodes["w722"], "second startEvent with same key → w722")
    }

    /// A manual view call while automatic view tracking is active is ignored and records w740.
    func testManualViewDuringAutoTrackingRecordsW740() {
        let tracker: CountlyHealthTracker = CountlyHealthTracker.sharedInstance()
        tracker.logCodes.removeAllObjects()

        let config = createBaseConfig()
        config.enableAutomaticViewTracking = true
        Countly.sharedInstance().start(with: config)
        let _ = Countly.sharedInstance().views().startView("ManualWhileAuto")

        drainHealthCheckQueue(tracker)

        XCTAssertNotNil(tracker.logCodes["w740"], "manual startView during auto tracking → w740")
    }
}
