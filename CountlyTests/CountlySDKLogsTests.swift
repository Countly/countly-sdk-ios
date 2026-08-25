import XCTest
@testable import Countly

/// Tests for per user SDK log gathering: the tri-state the SDK starts in, the speculative buffer
/// that makes init logs available, adoption and discard, the directive sanitising, the buffer
/// ceiling, and the shape of the uploaded batch.
class CountlySDKLogsTests: CountlyBaseTestCase {

    // mirrors the constants in CountlyCommon.m, on purpose: a test that read them from the
    // implementation would pass even if the value changed to something wrong
    private let allLevels = "ewidv"
    private let defaultBatchSize = 100
    private let minBatchSize = 10
    private let maxBufferedLines = 500
    private let maxMessageLength = 4096

    // CLYSDKLogsState, which is a private enum, so the raw values are asserted directly
    private let stateUndecided = 0
    private let stateGathering = 1
    private let stateOff = 2

    private var common: CountlyCommon { CountlyCommon.sharedInstance() }

    override func setUp() {
        super.setUp()
        TestUtils.cleanup()
        // halt() resets CountlyCommon, so gathering starts each test in its natural state:
        // undecided, with an empty buffer. Only the lines halt itself logged need clearing.
        clearBuffer()
    }

    override func tearDown() {
        common.updateLogGatheringState(false, levels: "", batch: 0, lgid: "")
        super.tearDown()
    }

    // MARK: - helpers

    private func clearBuffer() {
        (common.value(forKey: "sdkLogs") as? NSMutableArray)?.removeAllObjects()
        common.setValue(NSNumber(value: 0), forKey: "sdkLogsDropCount")
    }

    private func capture(_ count: Int, level: Character = "d", message: String = "harness line") {
        let levelChar = CChar(level.asciiValue!)
        for i in 0..<count {
            common.captureSdkLogLine("\(message) \(i)", level: levelChar)
        }
    }

    private let harnessPrefix = "harness line"

    private var bufferedLines: [[String: Any]] {
        (common.value(forKey: "sdkLogs") as? [[String: Any]]) ?? []
    }

    /// Only the lines this test injected. Arming gathering logs a line of its own, which is then
    /// gathered like any other, so a raw buffer count is not a count of the test's own lines.
    private var harnessLines: [[String: Any]] {
        bufferedLines.filter { ($0["m"] as? String)?.hasPrefix(harnessPrefix) == true }
    }

    private var state: Int { (common.value(forKey: "sdkLogsState") as? NSNumber)?.intValue ?? -1 }
    private var levels: String { (common.value(forKey: "sdkLogsLevels") as? String) ?? "" }
    private var batchSize: Int { (common.value(forKey: "sdkLogsBatchSize") as? NSNumber)?.intValue ?? -1 }
    private var dropCount: Int { (common.value(forKey: "sdkLogsDropCount") as? NSNumber)?.intValue ?? -1 }

    /// Brings up the SDK so the request queue exists, and waits out the behavior settings fetch.
    ///
    /// CountlyPersistency has no instance after halt(), so reading the queue without this traps.
    /// The fetch fails against the test host, and that failure decides against gathering, so it has
    /// to land before the test arms anything or it turns gathering off underneath it.
    private func startSDK() {
        let config = createBaseConfig()
        config.requiresConsent = false
        config.manualSessionHandling = true
        Countly.sharedInstance().start(with: config)
        TestUtils.sleep(1) {}
    }

    /// Puts gathering back into the state the SDK boots in, after something decided against it.
    private func forceUndecided() {
        common.setValue(NSNumber(value: stateUndecided), forKey: "sdkLogsState")
        common.setValue(allLevels, forKey: "sdkLogsLevels")
        clearBuffer()
    }

    /// The most recent queued request carrying an sdk_logs batch, decoded.
    private func lastUploadedBatch() -> [String: Any]? {
        guard let rq = TestUtils.getCurrentRQ() else { return nil }
        for request in rq.reversed() {
            let parsed = TestUtils.parseQueryString(request)
            guard let raw = parsed["sdk_logs"] else { continue }
            if let dict = raw as? [String: Any] {
                return dict
            }
            if let string = raw as? String,
               let data = string.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return dict
            }
        }
        return nil
    }

    // MARK: - the state the SDK starts in

    func testLogGathering_startsUndecidedAndCapturesSpeculatively() throws {
        XCTAssertEqual(stateUndecided, state, "the SDK has to gather before a directive exists, or init logs are unreachable")

        capture(5)

        XCTAssertEqual(5, harnessLines.count)
    }

    func testLogGathering_capturesWhileConsoleLoggingIsOff() throws {
        common.enableDebug = false
        common.loggerDelegate = nil
        clearBuffer()

        capture(3)

        XCTAssertEqual(3, harnessLines.count, "capture sits above the console logging gates")
    }

    func testLogGathering_capturesEveryLevelWhileUndecided() throws {
        for level in allLevels {
            capture(1, level: level)
        }

        // which levels the operator wants arrives with the directive, so nothing can be filtered yet
        XCTAssertEqual(allLevels.count, harnessLines.count)
    }

    // MARK: - adoption and discard

    func testLogGathering_adoptsSpeculativeLinesWhenTurnedOn() throws {
        capture(7)

        common.updateLogGatheringState(true, levels: allLevels, batch: defaultBatchSize, lgid: "gather_1")

        XCTAssertEqual(stateGathering, state)
        XCTAssertEqual(7, harnessLines.count, "the init lines are the reason speculative capture exists")
    }

    func testLogGathering_dropsSpeculativeLinesWhenNotGathering() throws {
        capture(7)

        common.updateLogGatheringState(false, levels: "", batch: 0, lgid: "")

        XCTAssertEqual(stateOff, state)
        XCTAssertEqual(0, bufferedLines.count)
        XCTAssertEqual(0, dropCount, "lines nobody asked for are not a reportable loss")
    }

    func testLogGathering_filtersAdoptedLinesToTheRequestedLevels() throws {
        capture(2, level: "e")
        capture(3, level: "d")
        capture(1, level: "v")

        common.updateLogGatheringState(true, levels: "e", batch: defaultBatchSize, lgid: "gather_2")

        let kept = harnessLines
        XCTAssertEqual(2, kept.count)
        XCTAssertTrue(kept.allSatisfy { ($0["l"] as? String) == "e" })
        XCTAssertEqual(0, dropCount, "a level filter is not a buffer overflow")
    }

    func testLogGathering_discardsLinesBelongingToAPreviousGather() throws {
        common.updateLogGatheringState(true, levels: allLevels, batch: defaultBatchSize, lgid: "gather_old")
        clearBuffer()
        capture(4)
        XCTAssertEqual(4, harnessLines.count)

        common.updateLogGatheringState(true, levels: allLevels, batch: defaultBatchSize, lgid: "gather_new")

        XCTAssertEqual(0, harnessLines.count, "the server rejects a batch attributed to a gather that ended")
    }

    func testLogGathering_keepsLinesWhenTheSameGatherIsConfirmedAgain() throws {
        common.updateLogGatheringState(true, levels: allLevels, batch: defaultBatchSize, lgid: "gather_same")
        clearBuffer()
        capture(4)

        common.updateLogGatheringState(true, levels: allLevels, batch: defaultBatchSize, lgid: "gather_same")

        XCTAssertEqual(4, harnessLines.count, "every config fetch repeats the directive, that must not lose lines")
    }

    func testLogGathering_stopsCapturingOnceTurnedOff() throws {
        common.updateLogGatheringState(false, levels: "", batch: 0, lgid: "")

        capture(5)

        XCTAssertEqual(0, harnessLines.count)
    }

    // MARK: - directive sanitising

    func testLogGathering_enabledWithoutAGatherIdDoesNotGather() throws {
        common.updateLogGatheringState(true, levels: allLevels, batch: defaultBatchSize, lgid: "")

        XCTAssertEqual(stateOff, state, "a batch with no gather id can not be attributed and the server rejects it")
    }

    func testLogGathering_unusableLevelStringFallsBackToEveryLevel() throws {
        common.updateLogGatheringState(true, levels: "!!zz", batch: defaultBatchSize, lgid: "gather_3")

        XCTAssertEqual(allLevels, levels, "an armed gather that captures nothing looks like a broken feature")
    }

    func testLogGathering_unknownLevelCharactersAreStripped() throws {
        common.updateLogGatheringState(true, levels: "e!w", batch: defaultBatchSize, lgid: "gather_4")

        XCTAssertEqual("ew", levels)
    }

    func testLogGathering_nilLevelStringFallsBackToEveryLevel() throws {
        // a directive that omits 'l' arrives here as nil, and strchr on nil would crash
        common.updateLogGatheringState(true, levels: nil, batch: defaultBatchSize, lgid: "gather_5")

        XCTAssertEqual(allLevels, levels)
        capture(1)
        XCTAssertEqual(1, harnessLines.count)
    }

    func testLogGathering_batchSizeIsClampedIntoRange() throws {
        common.updateLogGatheringState(true, levels: allLevels, batch: 1, lgid: "gather_6")
        XCTAssertEqual(minBatchSize, batchSize, "a batch of one would upload a request per log line")

        common.updateLogGatheringState(true, levels: allLevels, batch: 100_000, lgid: "gather_6")
        XCTAssertEqual(maxBufferedLines, batchSize, "a batch bigger than the buffer would never fill")

        common.updateLogGatheringState(true, levels: allLevels, batch: 0, lgid: "gather_6")
        XCTAssertEqual(defaultBatchSize, batchSize)

        common.updateLogGatheringState(true, levels: allLevels, batch: -5, lgid: "gather_6")
        XCTAssertEqual(defaultBatchSize, batchSize)
    }

    // MARK: - the buffer ceiling

    func testLogGathering_ceilingDropsTheOldestLinesAndCountsThem() throws {
        capture(maxBufferedLines + 25)

        XCTAssertEqual(maxBufferedLines, bufferedLines.count)
        XCTAssertEqual(25, dropCount, "the loss is reported as 'd' instead of disappearing silently")

        // the oldest went first, so the newest line has to still be there
        let last = bufferedLines.last?["m"] as? String
        XCTAssertEqual("harness line \(maxBufferedLines + 24)", last)
    }

    func testLogGathering_longMessagesAreTruncated() throws {
        capture(1, message: "xxx" + String(repeating: "x", count: maxMessageLength + 500))

        let stored = bufferedLines.compactMap { $0["m"] as? String }.first { $0.hasPrefix("xxx") }
        XCTAssertEqual(maxMessageLength, stored?.count, "a longer line is cut, not dropped")
    }

    func testLogGathering_lineCarriesMillisecondTimestampAndSingleCharLevel() throws {
        capture(1, level: "e")

        let line = try XCTUnwrap(harnessLines.first)
        XCTAssertEqual("e", line["l"] as? String, "a boxed char would go on the wire as 101")
        let timestamp = try XCTUnwrap((line["t"] as? NSNumber)?.int64Value)
        XCTAssertGreaterThan(timestamp, 1_600_000_000_000, "milliseconds since epoch, not seconds")
    }

    // MARK: - upload

    func testLogGathering_flushDoesNothingWhileUndecided() throws {
        startSDK()
        forceUndecided()
        capture(defaultBatchSize * 2)
        let before = TestUtils.getCurrentRQ()?.count ?? 0

        common.flushSdkLogs()

        XCTAssertEqual(before, TestUtils.getCurrentRQ()?.count ?? 0, "there is nothing to attribute a batch to yet")
        XCTAssertEqual(defaultBatchSize * 2, harnessLines.count, "and the lines stay held")
    }

    func testLogGathering_flushDoesNothingWhenNotGathering() throws {
        startSDK()
        common.updateLogGatheringState(false, levels: "", batch: 0, lgid: "")
        let before = TestUtils.getCurrentRQ()?.count ?? 0

        common.flushSdkLogs()

        XCTAssertEqual(before, TestUtils.getCurrentRQ()?.count ?? 0)
    }

    func testLogGathering_uploadedBatchCarriesTheExpectedShape() throws {
        startSDK()

        common.updateLogGatheringState(true, levels: "e", batch: minBatchSize, lgid: "gather_upload")
        clearBuffer()
        capture(minBatchSize, level: "e")

        common.flushSdkLogs()

        let batch = try XCTUnwrap(lastUploadedBatch(), "the batch never reached the request queue")
        XCTAssertEqual("gather_upload", batch["i"] as? String)
        XCTAssertEqual(0, (batch["d"] as? NSNumber)?.intValue)
        let lines = try XCTUnwrap(batch["l"] as? [[String: Any]])
        XCTAssertEqual(minBatchSize, lines.count, "a flush takes exactly one batch, not the whole buffer")
        XCTAssertTrue(lines.allSatisfy { ($0["l"] as? String) == "e" })
        XCTAssertTrue(lines.allSatisfy { ($0["m"] as? String)?.isEmpty == false })
    }

    func testLogGathering_uploadReportsAndResetsTheDropCount() throws {
        startSDK()

        forceUndecided()
        // while gathering is on every captured line drains a batch, so the buffer only ever
        // overflows before a directive arrives. Overflow first, then let a gather adopt the rest.
        capture(maxBufferedLines + 12, level: "e")
        XCTAssertEqual(12, dropCount)

        common.updateLogGatheringState(true, levels: "e", batch: minBatchSize, lgid: "gather_dropped")
        common.flushSdkLogs()

        let batch = try XCTUnwrap(lastUploadedBatch())
        XCTAssertEqual(12, (batch["d"] as? NSNumber)?.intValue, "the gap has to reach the operator")
        XCTAssertEqual(0, dropCount, "and must not be counted twice on the next batch")
    }

    func testLogGathering_ownTransportLinesAreNotGathered() throws {
        startSDK()

        common.updateLogGatheringState(true, levels: allLevels, batch: minBatchSize, lgid: "gather_transport")
        clearBuffer()
        capture(minBatchSize)

        common.flushSdkLogs()

        // uploading a batch is itself a request, and the request path logs the request in full.
        // Gathering that line would nest each batch inside the next one.
        let held = bufferedLines.compactMap { $0["m"] as? String }
        XCTAssertTrue(held.allSatisfy { !$0.contains("sdk_logs") }, "held a line describing the upload: \(held)")
    }

    func testLogGathering_capturedLineCarryingTheTransportMarkerIsIgnored() throws {
        common.updateLogGatheringState(true, levels: allLevels, batch: defaultBatchSize, lgid: "gather_marker")
        clearBuffer()

        common.captureSdkLogLine("request started &sdk_logs={\"i\":\"x\"}", level: CChar(Character("d").asciiValue!))

        XCTAssertEqual(0, bufferedLines.count)
    }
}
