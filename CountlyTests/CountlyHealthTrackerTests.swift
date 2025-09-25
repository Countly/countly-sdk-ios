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
        
        // Reader operations
        group.enter()
        readerQueue.async {
            for _ in 0..<iterations {
                autoreleasepool {
                    readerBlock()
                    if readerDelay > 0 { usleep(readerDelay) }
                }
            }
            group.leave()
        }
        
        // Additional mixed operations for maximum contention
        for threadIndex in 0..<extraThreads {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                for i in 0..<(iterations / 2) {
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
        XCTAssertEqual(result, .success, "Concurrent stress test did not complete within \(timeout) seconds", file: file, line: line)
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
            ("special_chars", String(repeating: "line\n\ttab\r", count: 100))
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
            iterations: 10_000,
            writerDelay: 50,
            readerDelay: 50,
            writerBlock: { _ in
                let err = String(repeating: UUID().uuidString, count: 1000) // ~36KB string
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
        
        let iterations = 20_000
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
        for _ in 0..<4 {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                for _ in 0..<iterations {
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
            ("unicode_boundary", String(repeating: "🎯", count: 250)), // 4-byte unicode
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
                        if i % 10 == 0 {
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
            let iterations = 10_000
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
            
            let result = group.wait(timeout: .now() + 10)
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
                                .logFailedNetworkRequest(withStatusCode: 500, 
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
}
