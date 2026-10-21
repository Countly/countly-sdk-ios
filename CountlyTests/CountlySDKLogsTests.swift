import CoreLocation
import XCTest
@testable import Countly
#if os(iOS)
import WebKit
#endif

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
        // halt() resets CountlyCommon and pauses capture until the next start, so capture is resumed the way a start
        // resumes it, which leaves each test in the state a process starts in: undecided, with an empty buffer
        common.resumeSdkLogCaptureForStart()
        clearBuffer()
    }

    override func tearDown() {
        common.updateLogGatheringState(false, levels: "", batch: 0, lgid: "")
        super.tearDown()
    }

    // MARK: - helpers

    /// Runs the body under the SDK's gathering lock: the SDK captures into the same arrays from its own threads, and
    /// mutating or copying them unlocked crashes inside the SDK now and then.
    private func withGatheringLock<T>(_ body: () -> T) -> T {
        let lock = common.value(forKey: "sdkLogsLock") as AnyObject
        objc_sync_enter(lock)
        defer { objc_sync_exit(lock) }
        return body()
    }

    private func clearBuffer() {
        withGatheringLock {
            (common.value(forKey: "sdkLogs") as? NSMutableArray)?.removeAllObjects()
            common.setValue(NSNumber(value: 0), forKey: "sdkLogsChars")
            (common.value(forKey: "sdkLogsAwaitingConsent") as? NSMutableArray)?.removeAllObjects()
            common.setValue(NSNumber(value: 0), forKey: "sdkLogsAwaitingConsentChars")
            common.setValue(NSNumber(value: 0), forKey: "sdkLogsDropCount")
        }
    }

    private func capture(_ count: Int, level: Character = "d", message: String = "harness line") {
        let levelChar = CChar(level.asciiValue!)
        for i in 0..<count {
            common.captureSdkLogLine("\(message) \(i)", level: levelChar)
        }
    }

    private let harnessPrefix = "harness line"

    private var bufferedLines: [[String: Any]] {
        withGatheringLock { (common.value(forKey: "sdkLogs") as? [[String: Any]]) ?? [] }
    }

    /// Only the lines this test injected. Arming gathering logs a line of its own, which is then
    /// gathered like any other, so a raw buffer count is not a count of the test's own lines.
    private var harnessLines: [[String: Any]] {
        bufferedLines.filter(isHarnessLine)
    }

    /// The captured lines that wait for the consent of their feature, kept apart from the buffer.
    private var awaitingConsentLines: [[String: Any]] {
        withGatheringLock { (common.value(forKey: "sdkLogsAwaitingConsent") as? [[String: Any]]) ?? [] }
    }

    /// Whether a captured line is one this test injected.
    private func isHarnessLine(_ line: [String: Any]) -> Bool {
        (line["m"] as? String)?.hasPrefix(harnessPrefix) == true
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
    ///
    /// - Parameter requiresConsent: start with consent required and nothing granted, so the consent gates are under test
    private func startSDK(requiresConsent: Bool = false) {
        let config = createBaseConfig()
        config.requiresConsent = requiresConsent
        config.manualSessionHandling = true
        Countly.sharedInstance().start(with: config)
        TestUtils.sleep(1) {}
    }

    /// The user data the consent tests record, every piece of which a log line quotes verbatim.
    private let userData = ["purchase", "secret-sku", "checkout screen", "someone@example.com"]

    /// Puts gathering back into the state the SDK boots in, after something decided against it.
    private func forceUndecided() {
        withGatheringLock {
            common.setValue(NSNumber(value: stateUndecided), forKey: "sdkLogsState")
            common.setValue(allLevels, forKey: "sdkLogsLevels")
        }
        clearBuffer()
    }

    /// Every queued request carrying an sdk_logs batch, decoded, oldest first.
    private func uploadedBatches() -> [[String: Any]] {
        guard let rq = TestUtils.getCurrentRQ() else { return [] }
        return rq.compactMap { CountlySDKLogsTests.sdkLogsBatch(ofQueryString: $0) }
    }

    /// The sdk_logs batch a request query string carries, decoded, or nil when it carries none.
    fileprivate static func sdkLogsBatch(ofQueryString queryString: String) -> [String: Any]? {
        guard let raw = TestUtils.parseQueryString(queryString)["sdk_logs"] else { return nil }
        if let dict = raw as? [String: Any] {
            return dict
        }
        if let string = raw as? String, let data = string.data(using: .utf8) {
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        return nil
    }

    /// Starts the SDK against a mock server that answers every request with success, so the request queue drains, and
    /// returns what records the log batches that server receives.
    private func startSDKWithAnsweringServer() -> ReceivedLogBatches {
        let received = ReceivedLogBatches(harnessPrefix: harnessPrefix)
        MockURLProtocol.requestHandler = { request in
            let queryString = CountlyServerConfigTests.capturedQueryString(request)
            if let batch = CountlySDKLogsTests.sdkLogsBatch(ofQueryString: queryString) {
                received.append(batch)
            }
            let ok = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)
            return ("{\"result\":\"Success\"}".data(using: .utf8), ok, nil)
        }

        let config = createBaseConfig()
        config.manualSessionHandling = true
        config.disableSDKBehaviorSettingsUpdates = true
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        config.urlSessionConfiguration = sessionConfig
        Countly.sharedInstance().start(with: config)
        return received
    }

    /// The most recent queued request carrying an sdk_logs batch, decoded.
    private func lastUploadedBatch() -> [String: Any]? {
        uploadedBatches().last
    }

    /// The messages of every uploaded line, across all batches.
    private func uploadedMessages() -> [String] {
        uploadedBatches().flatMap { ($0["l"] as? [[String: Any]]) ?? [] }.compactMap { $0["m"] as? String }
    }

    /// Lets the delivery queue, which a full batch or an adoption schedules onto, drain.
    private func settleDelivery() {
        TestUtils.sleep(0.5) {}
    }

    private var serverConfig: CountlyServerConfig { CountlyServerConfig.sharedInstance() }

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

    /// What the app logs between halt and the next start, after a logout for example, belongs to no user the next start
    /// brings, so capture pauses at halt and resumes with the first line of the next start.
    func testLogGathering_haltPausesCaptureUntilTheNextStart() throws {
        startSDK()
        Countly.sharedInstance().halt(true)
        XCTAssertEqual(stateOff, state, "halt pauses capture")

        Countly.sharedInstance().recordEvent("logged_out_event", segmentation: ["card": "4242"])
        capture(2)
        XCTAssertEqual(0, bufferedLines.count + awaitingConsentLines.count, "nothing is held for the next user")
        XCTAssertFalse(CountlyInternalLogIsWanted(CLYInternalLogLevelVerbose), "and nothing is formatted for capture")

        // the settings answer is held, so its failure can not decide against gathering before the checks below
        let releaseSettings = DispatchSemaphore(value: 0)
        MockURLProtocol.requestHandler = { request in
            if request.url?.absoluteString.contains("method=sc") == true {
                _ = releaseSettings.wait(timeout: .now() + 10)
            }
            let failed = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)
            return ("{\"result\":\"fail\"}".data(using: .utf8), failed, nil)
        }
        defer {
            releaseSettings.signal()
            MockURLProtocol.replyEmptyToEveryRequest()
        }
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let config = createBaseConfig()
        config.manualSessionHandling = true
        config.urlSessionConfiguration = sessionConfig
        Countly.sharedInstance().start(with: config)

        let messages = bufferedLines.compactMap { $0["m"] as? String }
        XCTAssertEqual(stateUndecided, state, "the next start captures again")
        XCTAssertTrue(messages.contains { $0.contains("startWithConfig") }, "from its own first lines")
        XCTAssertFalse(messages.contains { $0.contains("logged_out_event") }, "but nothing the app logged while halted")
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

    func testLogGathering_ceilingDropsTheOldestLinesAndCountsThemOnceAGatherAdoptsThem() throws {
        capture(maxBufferedLines + 25, level: "e")

        XCTAssertEqual(maxBufferedLines, bufferedLines.count)
        XCTAssertEqual(0, dropCount, "a loss while undecided belongs to no gather yet")

        // the oldest went first, so the newest line has to still be there
        let last = harnessLines.last?["m"] as? String
        XCTAssertEqual("harness line \(maxBufferedLines + 24)", last)

        common.updateLogGatheringState(true, levels: "e", batch: maxBufferedLines, lgid: "gather_ceiling")

        // the oldest lines are this test's own, and any line the SDK logged meanwhile pushed one more of them out
        XCTAssertGreaterThanOrEqual(dropCount, 25)
        XCTAssertEqual(maxBufferedLines + 25 - harnessLines.count, dropCount, "the loss is reported as 'd' instead of disappearing silently")
    }

    /// Lines dropped while undecided count into 'd' only for the levels the adopting gather asks for, and not at all when
    /// gathering is turned off instead.
    func testLogGathering_undecidedDropsCountOnlyForTheAdoptedLevels() throws {
        capture(maxBufferedLines, level: "v")
        capture(100, level: "e")
        common.updateLogGatheringState(true, levels: "e", batch: maxBufferedLines, lgid: "gather_errors_only")
        XCTAssertEqual(0, dropCount, "the dropped lines were verbose, which this gather never asked for")

        forceUndecided()
        capture(maxBufferedLines, level: "e")
        capture(100, level: "v")
        common.updateLogGatheringState(true, levels: "ew", batch: maxBufferedLines, lgid: "gather_errors_and_warnings")
        XCTAssertEqual(100, dropCount, "the dropped lines were errors, which this gather asked for")

        forceUndecided()
        capture(maxBufferedLines + 30, level: "e")
        common.decideLogGatheringOffIfUndecided("fetch failed")
        common.setValue(NSNumber(value: stateUndecided), forKey: "sdkLogsState")
        capture(1, level: "e")
        common.updateLogGatheringState(true, levels: allLevels, batch: maxBufferedLines, lgid: "gather_after_off")
        XCTAssertEqual(0, dropCount, "turning gathering off forgets what was dropped before it")
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
        capture(minBatchSize - 1, level: "e")

        common.flushSdkLogs()

        let batch = try XCTUnwrap(lastUploadedBatch(), "the batch never reached the request queue")
        XCTAssertEqual("gather_upload", batch["i"] as? String)
        XCTAssertEqual(0, (batch["d"] as? NSNumber)?.intValue)
        let lines = try XCTUnwrap(batch["l"] as? [[String: Any]])
        XCTAssertEqual(minBatchSize - 1, lines.count, "a flush takes the partial batch that is there")
        XCTAssertTrue(lines.allSatisfy { ($0["l"] as? String) == "e" })
        XCTAssertTrue(lines.allSatisfy { ($0["m"] as? String)?.isEmpty == false })
    }

    func testLogGathering_uploadReportsAndResetsTheDropCount() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        let server = startSDKWithAnsweringServer()
        defer { MockURLProtocol.replyEmptyToEveryRequest() }

        forceUndecided()
        // while gathering is on every captured line drains a batch, so the buffer only ever
        // overflows before a directive arrives. Overflow first, then let a gather adopt the rest.
        capture(maxBufferedLines + 12, level: "e")
        XCTAssertEqual(0, dropCount, "a loss while undecided belongs to no gather yet")

        common.updateLogGatheringState(true, levels: "e", batch: minBatchSize, lgid: "gather_dropped")

        // the SDK's own lines, logged meanwhile, can push out a few more of the oldest test lines, so the check is that
        // every captured line either reached the server or was reported as dropped
        let capturedCount = maxBufferedLines + 12
        let gatherBatches: () -> [[String: Any]] = { server.batches.filter { ($0["i"] as? String) == "gather_dropped" } }
        let accountedCount: () -> Int = {
            server.harnessMessages.count + gatherBatches().reduce(0) { $0 + (($1["d"] as? NSNumber)?.intValue ?? 0) }
        }

        // one batch waits in the queue at a time, so the backlog reaches the server batch by batch, and the remainder
        // smaller than a batch waits for the timer, played here whenever the queue is empty
        TestUtils.waitUntil("every held line to reach the server", timeout: 30) {
            if accountedCount() < capturedCount && !CountlyPersistency.sharedInstance().queueContainsSdkLogs() {
                self.common.scheduleSdkLogsFlush()
            }
            return accountedCount() >= capturedCount
        }

        let dropCounts = gatherBatches().map { ($0["d"] as? NSNumber)?.intValue ?? -1 }
        XCTAssertGreaterThanOrEqual(dropCounts.first ?? 0, 12, "adopting the lines adopts their loss, reported with the first batch")
        XCTAssertEqual(1, dropCounts.filter { $0 > 0 }.count, "and only once: \(dropCounts)")
        XCTAssertEqual(capturedCount, accountedCount())
        let delivered = server.harnessMessages
        XCTAssertEqual(((capturedCount - delivered.count)..<capturedCount).map { "\(harnessPrefix) \($0)" }, delivered, "the oldest were dropped, the rest went out once, in capture order")
        XCTAssertEqual(0, dropCount)
    }

    func testLogGathering_fullBatchIsDeliveredOffTheCapturingThread() throws {
        startSDK()
        common.updateLogGatheringState(true, levels: "e", batch: minBatchSize, lgid: "gather_async")
        clearBuffer()

        capture(minBatchSize, level: "e")
        settleDelivery()

        let batch = try XCTUnwrap(lastUploadedBatch(), "a full batch has to go out without a flush")
        XCTAssertEqual(minBatchSize, (batch["l"] as? [Any])?.count)
        XCTAssertEqual(0, harnessLines.count)
    }

    // MARK: - one batch in the queue, and the last batch of a stopped gather

    /// One gathered batch waits in the request queue at a time: the next goes out once the queue has sent it, so a
    /// backlog reaches the server batch by batch, in capture order, with no line lost or sent twice.
    func testLogGathering_nextBatchGoesOutOnceTheWaitingOneIsSent() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        let server = startSDKWithAnsweringServer()
        defer { MockURLProtocol.replyEmptyToEveryRequest() }

        common.updateLogGatheringState(true, levels: "e", batch: minBatchSize, lgid: "gather_backlog")
        clearBuffer()
        capture(minBatchSize * 3, level: "e")

        TestUtils.waitUntil("every held line to reach the server") { server.harnessMessages.count >= self.minBatchSize * 3 }

        let batches = server.batches.filter { ($0["i"] as? String) == "gather_backlog" }
        XCTAssertEqual(3, batches.count, "one batch per round trip of the queue")
        XCTAssertTrue(batches.allSatisfy { (($0["l"] as? [Any])?.count ?? 0) <= minBatchSize }, "no batch is larger than the batch size")
        XCTAssertEqual((0..<minBatchSize * 3).map { "\(harnessPrefix) \($0)" }, server.harnessMessages)
        XCTAssertEqual(0, harnessLines.count)
    }

    /// While requests fail only one gathered batch waits in the request queue: the batch size and the timer hold the rest
    /// in the capped buffer instead of crowding the queue, and going to the background still gets every held line out.
    func testLogGathering_onlyOneBatchWaitsInTheQueueWhileRequestsFail() throws {
        startSDK()
        common.updateLogGatheringState(true, levels: "e", batch: minBatchSize, lgid: "gather_offline")
        clearBuffer()

        capture(minBatchSize * 3 + 5, level: "e")
        settleDelivery()
        common.scheduleSdkLogsFlush()
        settleDelivery()

        XCTAssertEqual(1, uploadedBatches().count, "a second batch would only wait behind the first")
        XCTAssertEqual(minBatchSize * 2 + 5, harnessLines.count, "the rest stays held")
        XCTAssertEqual(0, dropCount)

        #if os(iOS) || os(tvOS) || os(visionOS)
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        #else
        // the other platforms have no background notification the SDK observes, this is the flush it would run
        common.flushSdkLogs()
        #endif

        XCTAssertEqual((0..<minBatchSize * 3 + 5).map { "\(harnessPrefix) \($0)" }, uploadedMessages().filter { $0.hasPrefix(harnessPrefix) }, "the background flush drains every held line, in order")
        XCTAssertEqual(0, harnessLines.count)
    }

    /// A device ID change without merge gets every held line out under the old device ID, past the batch waiting in the queue.
    func testLogGathering_deviceIDChangeWithoutMerge_drainsEveryHeldBatchUnderTheOldID() throws {
        startSDK()
        let oldDeviceID = Countly.sharedInstance().deviceID()
        common.updateLogGatheringState(true, levels: "e", batch: minBatchSize, lgid: "gather_old_user_backlog")
        clearBuffer()
        capture(minBatchSize * 2 + 5, level: "e")
        settleDelivery()
        XCTAssertEqual(1, uploadedBatches().count)

        Countly.sharedInstance().changeDeviceIDWithoutMerge("new_user")

        let logRequests = (TestUtils.getCurrentRQ() ?? []).map { TestUtils.parseQueryString($0) }.filter { $0["sdk_logs"] != nil }
        XCTAssertTrue(logRequests.allSatisfy { ($0["device_id"] as? String) == oldDeviceID }, "every gathered line belongs to the old user")
        XCTAssertEqual((0..<minBatchSize * 2 + 5).map { "\(harnessPrefix) \($0)" }, uploadedMessages().filter { $0.hasPrefix(harnessPrefix) })
        XCTAssertEqual(stateOff, state)
    }

    /// A gather the server stops gets its held lines out once, under its own id and with the loss the buffer ceiling
    /// caused, and nothing goes out after that.
    func testLogGathering_stoppedGatherUploadsItsHeldLinesOnceUnderItsId() throws {
        startSDK()
        common.updateLogGatheringState(true, levels: "e", batch: minBatchSize, lgid: "gather_tail")
        clearBuffer()
        capture(minBatchSize, level: "e")
        settleDelivery()
        XCTAssertEqual(1, uploadedBatches().count, "the first batch waits in the queue")

        // held behind the waiting batch until the buffer ceiling drops the oldest
        capture(maxBufferedLines + 40, level: "e")
        XCTAssertEqual(maxBufferedLines, bufferedLines.count)

        common.updateLogGatheringState(false, levels: "", batch: 0, lgid: "")

        let batches = uploadedBatches()
        XCTAssertEqual(2, batches.count, "the held lines go out as one last batch")
        let tail = try XCTUnwrap(batches.last)
        XCTAssertEqual("gather_tail", tail["i"] as? String, "under the id of the gather that stopped")
        let tailHarnessLines = ((tail["l"] as? [[String: Any]]) ?? []).filter(isHarnessLine).count
        let tailDropCount = (tail["d"] as? NSNumber)?.intValue ?? -1
        XCTAssertGreaterThanOrEqual(tailDropCount, 40, "with the loss the ceiling caused")
        XCTAssertEqual(maxBufferedLines + 40, tailHarnessLines + tailDropCount, "every captured line is either in the last batch or counted as dropped")
        XCTAssertEqual(stateOff, state)
        XCTAssertEqual(0, bufferedLines.count)

        capture(minBatchSize, level: "e")
        common.flushSdkLogs()
        XCTAssertEqual(2, uploadedBatches().count, "a stopped gather sends nothing more")
    }

    /// Only a running gather that stops sends a last batch: lines held while undecided and the lines of a gather the
    /// server replaced belong to no gather that can still take them.
    func testLogGathering_onlyARunningGatherSendsALastBatch() throws {
        startSDK()
        forceUndecided()
        capture(5, level: "e")
        common.updateLogGatheringState(false, levels: "", batch: 0, lgid: "")
        XCTAssertEqual(0, uploadedBatches().count, "lines held while undecided belong to no gather")

        common.updateLogGatheringState(true, levels: "e", batch: defaultBatchSize, lgid: "gather_replaced")
        clearBuffer()
        capture(5, level: "e")
        common.updateLogGatheringState(true, levels: "e", batch: defaultBatchSize, lgid: "gather_replacement")
        XCTAssertEqual(0, uploadedBatches().count, "the server rejects the lines of a gather it replaced")
        XCTAssertEqual(0, harnessLines.count)
    }

    // MARK: - holding back

    func testLogGathering_linesAreHeldWhileTrackingIsOff() throws {
        startSDK()
        common.updateLogGatheringState(true, levels: "e", batch: minBatchSize, lgid: "gather_tracking")
        clearBuffer()
        serverConfig.setValue(false, forKey: "trackingEnabled")
        defer { serverConfig.setValue(true, forKey: "trackingEnabled") }

        capture(minBatchSize, level: "e")
        common.flushSdkLogs()
        settleDelivery()

        XCTAssertEqual(0, uploadedBatches().count, "the queue drops everything while tracking is off, the lines would be lost")
        XCTAssertEqual(minBatchSize, harnessLines.count, "so they stay held")

        serverConfig.setValue(true, forKey: "trackingEnabled")
        common.flushSdkLogs()

        XCTAssertEqual(1, uploadedBatches().count)
        XCTAssertEqual(minBatchSize, (lastUploadedBatch()?["l"] as? [Any])?.count)
    }

    func testLogGathering_linesAreHeldUntilEventsAndUserDetailsConsentAreGiven() throws {
        startSDK(requiresConsent: true)

        common.updateLogGatheringState(true, levels: "e", batch: minBatchSize, lgid: "gather_consent")
        clearBuffer()
        capture(minBatchSize, level: "e")
        common.flushSdkLogs()
        settleDelivery()

        XCTAssertEqual(0, uploadedBatches().count, "a line of no single feature needs the events and the user details consent")
        XCTAssertEqual(minBatchSize, awaitingConsentLines.filter(isHarnessLine).count)

        Countly.sharedInstance().giveConsent(forFeatures: [CLYConsent.sessions])
        common.flushSdkLogs()
        settleDelivery()

        XCTAssertEqual(0, uploadedBatches().count, "sessions consent says nothing about the event and profile data a line can carry")

        Countly.sharedInstance().giveConsent(forFeatures: [CLYConsent.events])
        common.flushSdkLogs()
        settleDelivery()

        XCTAssertEqual(0, uploadedBatches().count, "a line may still quote a user property, which events consent does not cover")

        Countly.sharedInstance().giveConsent(forFeatures: [CLYConsent.userDetails])
        common.flushSdkLogs()
        settleDelivery()

        XCTAssertEqual(1, uploadedBatches().count, "with both given, anything a line can carry is consented")
        XCTAssertEqual("gather_consent", lastUploadedBatch()?["i"] as? String)
        XCTAssertEqual(minBatchSize, (lastUploadedBatch()?["l"] as? [Any])?.count)
    }

    /// The user details consent alone is not enough either: a full batch stays held without the events consent.
    func testLogGathering_userDetailsConsentWithoutEventsKeepsTheLinesHeld() throws {
        startSDK(requiresConsent: true)
        Countly.sharedInstance().giveConsent(forFeatures: [CLYConsent.userDetails])

        common.updateLogGatheringState(true, levels: "e", batch: minBatchSize, lgid: "gather_user_details_only")
        clearBuffer()
        capture(minBatchSize, level: "e")
        common.flushSdkLogs()
        settleDelivery()

        XCTAssertEqual(0, uploadedBatches().count, "a line may still quote an event key, which user details consent does not cover")
        XCTAssertEqual(minBatchSize, awaitingConsentLines.filter(isHarnessLine).count)
    }

    /// Each line waits for the consent of the feature that wrote it: an event line goes out with the events consent
    /// alone, and a user property line only once the user details consent is given too.
    func testLogGathering_eachLineWaitsForTheConsentOfItsOwnFeature() throws {
        startSDK(requiresConsent: true)
        Countly.sharedInstance().giveConsent(forFeatures: [CLYConsent.events])

        common.updateLogGatheringState(true, levels: allLevels, batch: defaultBatchSize, lgid: "gather_per_feature")
        clearBuffer()

        Countly.sharedInstance().recordEvent("purchase")
        Countly.user().set("email", value: "someone@example.com")
        common.flushSdkLogs()
        settleDelivery()

        XCTAssertTrue(uploadedMessages().contains { $0.contains("purchase") }, "the events consent covers the event line")
        XCTAssertFalse(uploadedMessages().contains { $0.contains("someone@example.com") }, "a user property line waits for the user details consent")

        Countly.sharedInstance().giveConsent(forFeatures: [CLYConsent.userDetails])
        common.flushSdkLogs()
        settleDelivery()

        XCTAssertTrue(uploadedMessages().contains { $0.contains("someone@example.com") }, "the consent releases the line that waited for it")
    }

    /// Every way a line opens maps to the consent of its owner: instance, class and block methods, Countly's methods by
    /// selector, the bracket prefix, and lines no single feature owns, which need the events and user details consent.
    func testLogGathering_lineOwnersMapToTheConsentOfTheirFeature() throws {
        startSDK(requiresConsent: true)
        Countly.sharedInstance().giveConsent(forFeatures: [CLYConsent.viewTracking])
        common.updateLogGatheringState(true, levels: allLevels, batch: maxBufferedLines, lgid: "gather_owners")
        clearBuffer()

        let viewLines = ["-[CountlyViewTrackingInternal startView:segmentation:] owner probe",
                         "__56-[CountlyViewTrackingInternal startViewInternal:customSegmentation:]_block_invoke owner probe",
                         "+[CountlyViewData new] owner probe",
                         "-[UIViewController(CountlyViewTracking) Countly_viewDidAppear:] owner probe"]
        let eventLines = ["-[Countly recordEvent:segmentation:count:sum:duration:] owner probe",
                          "__29-[Countly journeyTriggerCallback]_block_invoke owner probe"]
        let locationLines = ["-[Countly recordLocation:city:ISOCountryCode:IP:] owner probe"]
        let userLines = ["[CountlyUserDetails] owner probe"]
        let crashLines = ["CountlyExceptionHandler crash recorded, isFatal: [YES] owner probe"]
        let pushLines = ["-[NSObject(CountlyPushNotifications) Countly_application:didRegisterForRemoteNotificationsWithDeviceToken:] owner probe"]
        let unownedLines = ["-[Countly startWithConfig:] owner probe", "[CountlyServerConfig] owner probe", "__-[CountlyViewData new] owner probe", "owner probe without an owner", "CountlyJSONFromObject owner probe"]
        for line in viewLines + eventLines + locationLines + userLines + crashLines + pushLines + unownedLines {
            common.captureSdkLogLine(line, level: CChar(Character("d").asciiValue!))
        }

        let isHeld: ([String]) -> Bool = { lines in lines.allSatisfy { line in self.bufferedLines.contains { $0["m"] as? String == line } } }
        let isWaiting: ([String]) -> Bool = { lines in lines.allSatisfy { line in self.awaitingConsentLines.contains { $0["m"] as? String == line } } }

        XCTAssertTrue(isHeld(viewLines), "the views consent covers view tracking lines in every opening form, the swizzled callbacks included")
        XCTAssertTrue(isWaiting(eventLines + locationLines + userLines + crashLines + pushLines + unownedLines))

        Countly.sharedInstance().giveConsent(forFeatures: [CLYConsent.events])
        XCTAssertTrue(isHeld(eventLines), "Countly's own methods are attributed by selector")
        XCTAssertTrue(isWaiting(locationLines + userLines + crashLines + pushLines + unownedLines), "a line no feature owns needs the user details consent too")

        Countly.sharedInstance().giveConsent(forFeatures: [CLYConsent.userDetails])
        XCTAssertTrue(isHeld(userLines + unownedLines))
        XCTAssertTrue(isWaiting(locationLines + crashLines + pushLines), "the location, crash and push lines still wait for their own consent")

        Countly.sharedInstance().giveConsent(forFeatures: [CLYConsent.crashReporting, CLYConsent.pushNotifications])
        XCTAssertTrue(isHeld(crashLines + pushLines), "the crash handler's lines answer to the crashes consent, the swizzled push callback's to the push consent")
        XCTAssertTrue(isWaiting(locationLines))
    }

    /// While a gather asks for some levels only, log calls of the levels it leaves out are not even formatted.
    func testLogGathering_levelsAGatherLeavesOutAreNotWanted() throws {
        XCTAssertTrue(CountlyInternalLogIsWanted(CLYInternalLogLevelVerbose), "every level is wanted while undecided")

        common.updateLogGatheringState(true, levels: "e", batch: defaultBatchSize, lgid: "gather_errors")
        XCTAssertTrue(CountlyInternalLogIsWanted(CLYInternalLogLevelError))
        XCTAssertFalse(CountlyInternalLogIsWanted(CLYInternalLogLevelDebug), "a debug line would be formatted only to be dropped")

        common.updateLogGatheringState(false, levels: "", batch: 0, lgid: "")
        XCTAssertFalse(CountlyInternalLogIsWanted(CLYInternalLogLevelError), "with the console off nothing wants a line once gathering is off")
    }

    /// A line captured while init runs is decided when init finishes, and goes out without the consent it was checked against.
    func testLogGathering_initLinesAreDecidedWhenInitFinishesAndUploadAsPlainLines() throws {
        common.updateLogGatheringState(true, levels: allLevels, batch: maxBufferedLines, lgid: "gather_init")
        startSDK()

        let uploadedLines = uploadedBatches().flatMap { ($0["l"] as? [[String: Any]]) ?? [] }
        XCTAssertFalse(uploadedLines.isEmpty, "init finishing flushes the init lines")
        XCTAssertTrue(uploadedLines.allSatisfy { Set($0.keys) == ["t", "l", "m"] }, "the consent a line was checked against never reaches a batch")
    }

    /// With consent required and nothing given, the lines captured while init runs wait for their consent instead of uploading.
    func testLogGathering_initLinesWaitForTheirConsentWhenInitFinishes() throws {
        common.updateLogGatheringState(true, levels: allLevels, batch: maxBufferedLines, lgid: "gather_init")
        startSDK(requiresConsent: true)

        XCTAssertEqual(0, uploadedBatches().count)
        XCTAssertFalse(awaitingConsentLines.isEmpty)
    }

    /// A device ID change without merge uploads the held lines under the old device ID, then stops gathering for the new user.
    func testLogGathering_deviceIDChangeWithoutMerge_uploadsUnderTheOldIDAndStops() throws {
        startSDK()
        let oldDeviceID = Countly.sharedInstance().deviceID()

        common.updateLogGatheringState(true, levels: "e", batch: minBatchSize, lgid: "gather_old_user")
        clearBuffer()
        capture(3, level: "e")

        Countly.sharedInstance().changeDeviceIDWithoutMerge("new_user")
        settleDelivery()

        let logRequests = (TestUtils.getCurrentRQ() ?? []).map { TestUtils.parseQueryString($0) }.filter { $0["sdk_logs"] != nil }
        XCTAssertFalse(logRequests.isEmpty, "the held partial batch goes out before the switch")
        XCTAssertTrue(logRequests.allSatisfy { ($0["device_id"] as? String) == oldDeviceID }, "every gathered line belongs to the old user")
        XCTAssertEqual(stateOff, state)
        XCTAssertEqual(0, bufferedLines.count)

        let uploadedBeforeNewUser = uploadedBatches().count
        capture(minBatchSize, level: "e")
        common.flushSdkLogs()
        settleDelivery()

        XCTAssertEqual(uploadedBeforeNewUser, uploadedBatches().count, "the new user is not part of the old user's gather")
    }

    /// The last batch of the previous user's gather does not carry the next user's device ID, so one user's logs never name
    /// the user after them.
    func testLogGathering_deviceIDChangeWithoutMerge_lastBatchDoesNotCarryTheNewDeviceID() throws {
        startSDK()
        let newDeviceID = "next_user_identifier"

        common.updateLogGatheringState(true, levels: allLevels, batch: maxBufferedLines, lgid: "gather_old_user")
        clearBuffer()
        capture(3, level: "e")

        Countly.sharedInstance().changeDeviceIDWithoutMerge(newDeviceID)
        settleDelivery()

        XCTAssertFalse(uploadedBatches().isEmpty, "the held lines go out before the switch")
        XCTAssertFalse(uploadedMessages().contains { $0.contains(newDeviceID) }, "the old user's lines never name the next user")
    }

    /// A config response requested for the previous device ID can not arm gathering again once the device ID changed without merge.
    func testLogGathering_deviceIDChangeWithoutMerge_ignoresTheDirectiveRequestedForTheOldID() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        let answerAfterTheChange = DispatchSemaphore(value: 0)
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            guard request.url?.absoluteString.contains("method=sc") == true else {
                return ("{}".data(using: .utf8), response, nil)
            }
            _ = answerAfterTheChange.wait(timeout: .now() + 5)
            let armed = "{\"v\":1,\"t\":1234,\"c\":{\"rqs\":1500},\"lg\":{\"e\":true,\"i\":\"gather_old_user\",\"l\":\"ewidv\",\"b\":100}}"
            return (armed.data(using: .utf8), response, nil)
        }
        defer { MockURLProtocol.requestHandler = nil }

        let config = createBaseConfig()
        config.manualSessionHandling = true
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        config.urlSessionConfiguration = sessionConfig
        Countly.sharedInstance().start(with: config)

        Countly.sharedInstance().changeDeviceIDWithoutMerge("new_user")
        answerAfterTheChange.signal()
        TestUtils.sleep(1) {}

        XCTAssertEqual(stateOff, state, "the directive belongs to the previous user")
        XCTAssertEqual(1500, (serverConfig.value(forKey: "requestQueueSize") as? NSNumber)?.intValue, "the rest of the answer still applies")
    }

    /// Lines held back by consent are dropped on a device ID change without merge, so the next user's consent never releases them.
    func testLogGathering_deviceIDChangeWithoutMerge_dropsLinesHeldByConsent() throws {
        startSDK(requiresConsent: true)
        Countly.sharedInstance().giveConsent(forFeatures: [CLYConsent.sessions])

        common.updateLogGatheringState(true, levels: "e", batch: minBatchSize, lgid: "gather_old_user")
        clearBuffer()
        capture(minBatchSize, level: "e")
        settleDelivery()
        XCTAssertEqual(0, uploadedBatches().count)

        Countly.sharedInstance().changeDeviceIDWithoutMerge("new_user")
        Countly.sharedInstance().giveConsent(forFeatures: [CLYConsent.events, CLYConsent.userDetails])
        common.flushSdkLogs()
        settleDelivery()

        XCTAssertEqual(0, uploadedBatches().count, "the old user's lines never go out under the new user's consent")
        XCTAssertEqual(stateOff, state)
    }

    func testLogGathering_withoutConsentNoUserDataIsUploadedAndLocalLoggingIsUnchanged() throws {
        startSDK(requiresConsent: true)
        Countly.sharedInstance().giveConsent(forFeatures: [CLYConsent.sessions])

        let logger = RecordingLogger()
        common.loggerDelegate = logger
        defer { common.loggerDelegate = nil }

        common.updateLogGatheringState(true, levels: allLevels, batch: minBatchSize, lgid: "gather_no_data")
        clearBuffer()

        Countly.sharedInstance().recordEvent("purchase", segmentation: ["sku": "secret-sku"])
        _ = Countly.sharedInstance().views().startView("checkout screen")
        Countly.user().set("email", value: "someone@example.com")
        common.flushSdkLogs()
        settleDelivery()

        let uploaded = uploadedMessages()
        let awaiting = awaitingConsentLines.compactMap { $0["m"] as? String }
        for secret in userData {
            XCTAssertFalse(uploaded.contains { $0.contains(secret) }, "[\(secret)] reached the server without the consent it belongs to")
            XCTAssertTrue(awaiting.contains { $0.contains(secret) }, "[\(secret)] waits for its consent instead of being dropped")
        }

        // the gated copy is the uploaded one: a developer watching the console still sees every call
        for secret in userData {
            XCTAssertTrue(logger.lines.contains { $0.contains(secret) }, "local logging lost [\(secret)]")
        }
    }

    // MARK: - consent, merge, delivery and filters

    /// A merge keeps the user, so the log gathering directive of a fetch made before it still applies.
    func testLogGathering_deviceIDChangeWithMerge_keepsTheDirectiveRequestedBeforeIt() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        let answerAfterTheChange = DispatchSemaphore(value: 0)
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            guard request.url?.absoluteString.contains("method=sc") == true else {
                return ("{}".data(using: .utf8), response, nil)
            }
            _ = answerAfterTheChange.wait(timeout: .now() + 5)
            let armed = "{\"v\":1,\"t\":1234,\"c\":{\"rqs\":1500},\"lg\":{\"e\":true,\"i\":\"gather_merged_user\",\"l\":\"ewidv\",\"b\":100}}"
            return (armed.data(using: .utf8), response, nil)
        }
        defer { MockURLProtocol.replyEmptyToEveryRequest() }

        let config = createBaseConfig()
        config.manualSessionHandling = true
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        config.urlSessionConfiguration = sessionConfig
        Countly.sharedInstance().start(with: config)

        Countly.sharedInstance().changeDeviceID(withMerge: "merged_user")
        answerAfterTheChange.signal()
        TestUtils.waitUntil("the directive to be applied") { self.state == self.stateGathering }

        XCTAssertEqual(stateGathering, state, "a merge keeps the user, so the directive still applies")
        XCTAssertEqual("gather_merged_user", common.value(forKey: "sdkLogsGatheringId") as? String)
    }

    /// A consent withdrawn after its lines were gathered sends them back to wait, they are not uploaded until it is given again.
    func testLogGathering_withdrawnConsentSendsBufferedLinesBackToWait() throws {
        startSDK(requiresConsent: true)
        // no user details consent, so lines that quote whole requests stay held and only the two features are under test
        Countly.sharedInstance().giveConsent(forFeatures: [CLYConsent.events, CLYConsent.location])
        common.updateLogGatheringState(true, levels: allLevels, batch: maxBufferedLines, lgid: "gather_withdrawal")
        clearBuffer()

        Countly.sharedInstance().recordLocation(CLLocationCoordinate2D(latitude: 41.0082, longitude: 28.9784), city: "Istanbul", isoCountryCode: "TR", ip: nil)
        Countly.sharedInstance().recordEvent("purchase")
        XCTAssertTrue(bufferedLines.contains { ($0["m"] as? String)?.contains("Istanbul") == true }, "with location consent the line is gathered")

        Countly.sharedInstance().cancelConsent(forFeature: CLYConsent.location)
        XCTAssertFalse(bufferedLines.contains { ($0["m"] as? String)?.contains("Istanbul") == true })
        XCTAssertTrue(awaitingConsentLines.contains { ($0["m"] as? String)?.contains("Istanbul") == true }, "withdrawing location consent sends its line back to wait")

        common.flushSdkLogs()
        settleDelivery()
        XCTAssertFalse(uploadedMessages().contains { $0.contains("Istanbul") }, "a withdrawn consent holds its lines back again")
        XCTAssertTrue(uploadedMessages().contains { $0.contains("purchase") }, "lines of other features still go out")

        Countly.sharedInstance().giveConsent(forFeature: CLYConsent.location)
        common.flushSdkLogs()
        settleDelivery()
        XCTAssertTrue(uploadedMessages().contains { $0.contains("Istanbul") }, "giving the consent back releases the line")
        XCTAssertFalse(uploadedBatches().contains { batch in
            ((batch["l"] as? [[String: Any]]) ?? []).contains { $0["consent"] != nil }
        }, "the consent a line needs never goes on the wire")
    }

    /// Long lines reach the character ceiling long before a large batch fills, so the buffer goes out as a partial batch instead of dropping lines.
    func testLogGathering_longLinesAreDeliveredBeforeALargeBatchFills() throws {
        startSDK()
        common.updateLogGatheringState(true, levels: "d", batch: maxBufferedLines, lgid: "gather_long_lines")
        clearBuffer()

        capture(30, level: "d", message: harnessPrefix + " " + String(repeating: "x", count: 4000))
        settleDelivery()

        let batch = try XCTUnwrap(lastUploadedBatch(), "a buffer close to its character ceiling goes out without waiting for the batch size")
        let lineCount = (batch["l"] as? [Any])?.count ?? 0
        XCTAssertGreaterThan(lineCount, 0)
        XCTAssertLessThan(lineCount, maxBufferedLines)
        XCTAssertEqual(0, (batch["d"] as? NSNumber)?.intValue, "nothing was dropped on the way")
    }

    /// A full queue drops gathered log uploads before anything else, refuses new ones, and counts their lines as dropped.
    func testLogGathering_fullRequestQueueDropsLogUploadsFirstAndCountsTheirLines() throws {
        startSDK()
        let persistency = try XCTUnwrap(CountlyPersistency.sharedInstance())
        (persistency.value(forKey: "queuedRequests") as? NSMutableArray)?.removeAllObjects()
        persistency.storedRequestsLimit = 4

        common.updateLogGatheringState(true, levels: "d", batch: minBatchSize, lgid: "gather_full_queue")
        clearBuffer()
        capture(minBatchSize)
        settleDelivery()
        capture(minBatchSize)
        settleDelivery()
        let queuedLogUploads = uploadedBatches()
        XCTAssertEqual(1, queuedLogUploads.count, "one log upload waits in the queue at a time")
        XCTAssertEqual(minBatchSize, harnessLines.count, "the next batch is held until the waiting one is sent")
        let queuedLogLines = queuedLogUploads.reduce(0) { total, batch in
            total + ((batch["l"] as? [Any])?.count ?? 0) + ((batch["d"] as? NSNumber)?.intValue ?? 0)
        }

        for index in 1...4 {
            Countly.sharedInstance().addDirectRequest(["analytics": "request_\(index)"])
        }
        XCTAssertEqual(4, TestUtils.getCurrentRQ()?.filter { $0.contains("analytics=request_") }.count, "every other request is kept")
        XCTAssertEqual(0, uploadedBatches().count, "log uploads are dropped before any other request")
        // a delivery the SDK's own lines start holds the count in its batch until the full queue refuses the batch
        TestUtils.waitUntil("the dropped lines to be counted") { self.dropCount >= queuedLogLines }
        XCTAssertGreaterThanOrEqual(dropCount, queuedLogLines, "the dropped uploads' lines are reported as dropped")

        capture(minBatchSize)
        common.flushSdkLogs()
        XCTAssertEqual(4, TestUtils.getCurrentRQ()?.filter { $0.contains("analytics=request_") }.count, "a new log upload does not push a request out of a full queue")
        XCTAssertEqual(0, uploadedBatches().count)
        XCTAssertGreaterThanOrEqual(harnessLines.count, minBatchSize, "the refused lines are held again")
    }

    /// Values the behavior settings filter out are never quoted in a gathered line, values they let through still are.
    func testLogGathering_valuesFilteredOutByBehaviorSettingsAreNotQuoted() throws {
        UserDefaults.standard.set(ServerConfigBuilder()
            .segmentationBlacklist(["secret_key"])
            .locationTracking(false)
            .userPropertyBlacklist(["hidden_property"])
            .buildJson(), forKey: "kCountlyServerConfigPersistencyKey")
        startSDK()
        common.updateLogGatheringState(true, levels: allLevels, batch: maxBufferedLines, lgid: "gather_filtered_values")
        clearBuffer()

        Countly.sharedInstance().recordEvent("purchase", segmentation: ["secret_key": "S3CR3T-VALUE", "visible_key": "VISIBLE-VALUE"])
        Countly.sharedInstance().recordLocation(CLLocationCoordinate2D(latitude: 12.3456, longitude: 65.4321), city: "Hiddenville", isoCountryCode: "HV", ip: "10.1.2.3")
        Countly.sharedInstance().userProfile().setProperty("hidden_property", value: "HIDDEN-VALUE")
        Countly.sharedInstance().userProfile().setProperty("shown_property", value: "SHOWN-VALUE")
        // by selector, so the property the server filters out gets a value of a type the SDK rejects
        _ = Countly.sharedInstance().userProfile().perform(NSSelectorFromString("multiply:value:"), with: "hidden_property", with: NSDate(timeIntervalSince1970: 0))

        let captured = (bufferedLines + awaitingConsentLines).compactMap { $0["m"] as? String }
        for value in ["S3CR3T-VALUE", "12.3456", "Hiddenville", "10.1.2.3", "HIDDEN-VALUE", "1970-01-01"] {
            XCTAssertFalse(captured.contains { $0.contains(value) }, "[\(value)] is filtered out by the server, so no gathered line may quote it")
        }
        for value in ["VISIBLE-VALUE", "SHOWN-VALUE"] {
            XCTAssertTrue(captured.contains { $0.contains(value) }, "[\(value)] passes the filters, so it is still logged")
        }
    }

    /// The values of an event the behavior settings drop, because custom event tracking is off, are never quoted in a gathered line.
    func testLogGathering_eventsDroppedByBehaviorSettingsAreNotQuoted() throws {
        UserDefaults.standard.set(ServerConfigBuilder().customEventTracking(false).buildJson(), forKey: "kCountlyServerConfigPersistencyKey")
        startSDK()
        common.updateLogGatheringState(true, levels: allLevels, batch: maxBufferedLines, lgid: "gather_dropped_events")
        clearBuffer()

        Countly.sharedInstance().recordEvent("purchase", segmentation: ["sku": "DROPPED-EVENT-VALUE"])

        let captured = (bufferedLines + awaitingConsentLines).compactMap { $0["m"] as? String }
        XCTAssertTrue(captured.contains { $0.contains("purchase") }, "the call itself is still logged")
        XCTAssertFalse(captured.contains { $0.contains("DROPPED-EVENT-VALUE") }, "the values of a dropped event are never quoted")
    }

    /// Custom request header values, often credentials, are never quoted in a gathered line, their names still are.
    func testLogGathering_customHeaderValuesAreNotQuoted() throws {
        let config = createBaseConfig()
        config.manualSessionHandling = true
        // headers are only taken when a URL session configuration was given at start
        config.urlSessionConfiguration = URLSessionConfiguration.ephemeral
        Countly.sharedInstance().start(with: config)
        TestUtils.sleep(1) {}
        common.updateLogGatheringState(true, levels: allLevels, batch: maxBufferedLines, lgid: "gather_custom_headers")
        clearBuffer()

        Countly.sharedInstance().addCustomNetworkRequestHeaders(["Authorization": "Bearer S3CR3T-TOKEN", "X-Tenant": "TENANT-VALUE"])

        let captured = (bufferedLines + awaitingConsentLines).compactMap { $0["m"] as? String }
        XCTAssertTrue(captured.contains { $0.contains("Authorization") && $0.contains("X-Tenant") }, "the header names are still logged")
        for value in ["S3CR3T-TOKEN", "TENANT-VALUE"] {
            XCTAssertFalse(captured.contains { $0.contains(value) }, "[\(value)] is a header value, so no gathered line may quote it")
        }
        XCTAssertEqual("Bearer S3CR3T-TOKEN", CountlyConnectionManager.sharedInstance().urlSessionConfiguration?.httpAdditionalHeaders?["Authorization"] as? String, "the header itself is still applied")
    }

    /// A segmentation value or a user property the behavior settings filter out never reaches the server, so no gathered
    /// line quotes it either: not the line of a timed event's end, and not the line of the user properties given at start.
    func testLogGathering_valuesTheBehaviorSettingsFilterOutAreNotQuoted() throws {
        let config = createBaseConfig()
        config.manualSessionHandling = true
        config.disableSDKBehaviorSettingsUpdates = true
        config.sdkBehaviorSettings = ServerConfigBuilder().segmentationBlacklist(["secret_key"]).userPropertyBlacklist(["secret_property"]).build()
        config.providedUserProperties = ["secret_property": "PROPERTY-VALUE", "kept_property": "KEPT-PROPERTY"]
        // armed before start, since start decides against gathering while undecided once updates are disabled
        common.updateLogGatheringState(true, levels: allLevels, batch: maxBufferedLines, lgid: "gather_filtered_values")
        Countly.sharedInstance().start(with: config)

        Countly.sharedInstance().startEvent("timed_event")
        Countly.sharedInstance().endEvent("timed_event", segmentation: ["secret_key": "SEGMENT-VALUE", "kept_key": "KEPT-SEGMENT"], count: 1, sum: 0)

        // the init lines already went out with the batch init end sends, the later ones are still held
        settleDelivery()
        let captured = (bufferedLines + awaitingConsentLines).compactMap { $0["m"] as? String } + uploadedMessages()
        XCTAssertTrue(captured.contains { $0.contains("KEPT-SEGMENT") }, "a value the settings let through is still logged")
        XCTAssertTrue(captured.contains { $0.contains("KEPT-PROPERTY") }, "and so is a user property they let through")
        XCTAssertFalse(captured.contains { $0.contains("SEGMENT-VALUE") }, "a segmentation value the settings filter out is not quoted")
        XCTAssertFalse(captured.contains { $0.contains("PROPERTY-VALUE") }, "and neither is a filtered user property")
    }

#if os(iOS)
    /// The web view that shows content and feedback widgets logs the names of the response headers, never their values,
    /// since a response header can carry a session cookie.
    func testLogGathering_webViewResponseHeaderValuesAreNotQuoted() throws {
        startSDK()
        common.updateLogGatheringState(true, levels: allLevels, batch: maxBufferedLines, lgid: "gather_web_view_headers")
        clearBuffer()

        let url = try XCTUnwrap(URL(string: "https://content.example/page"))
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Set-Cookie": "session=C00KIE-VALUE", "X-Trace": "TRACE-VALUE"]))
        // never released: WKNavigationResponse frees WebKit state in dealloc that a response WebKit did not create lacks
        let navigationResponse = Unmanaged.passRetained(NavigationResponseStub(response: response)).takeUnretainedValue()
        var policy: WKNavigationResponsePolicy?
        let navigationDelegate: WKNavigationDelegate = CountlyWebViewManager()
        navigationDelegate.webView?(WKWebView(), decidePolicyFor: navigationResponse) { policy = $0 }

        XCTAssertEqual(.allow, policy, "a successful page is shown")
        let captured = (bufferedLines + awaitingConsentLines).compactMap { $0["m"] as? String }
        XCTAssertTrue(captured.contains { $0.contains("Set-Cookie") && $0.contains("X-Trace") }, "the header names are still logged")
        for value in ["C00KIE-VALUE", "TRACE-VALUE"] {
            XCTAssertFalse(captured.contains { $0.contains(value) }, "[\(value)] is a header value, so no gathered line may quote it")
        }
    }
#endif

    /// A delivery checks the consent of every line it takes, so a line whose consent was just withdrawn stays waiting.
    func testLogGathering_deliveryChecksTheConsentOfEveryLineItTakes() throws {
        startSDK(requiresConsent: true)
        Countly.sharedInstance().giveConsent(forFeatures: [CLYConsent.events, CLYConsent.location])
        common.updateLogGatheringState(true, levels: allLevels, batch: maxBufferedLines, lgid: "gather_consent_at_upload")
        clearBuffer()

        Countly.sharedInstance().recordLocation(CLLocationCoordinate2D(latitude: 41.0082, longitude: 28.9784), city: "Istanbul", isoCountryCode: "TR", ip: nil)
        XCTAssertTrue(bufferedLines.contains { ($0["m"] as? String)?.contains("Istanbul") == true })

        // flips the flag through its setter alone, the way a withdrawal does before it decides the held lines again
        let consentManager = try XCTUnwrap((NSClassFromString("CountlyConsentManager") as AnyObject).value(forKey: "sharedInstance") as? NSObject)
        consentManager.setValue(false, forKey: "consentForLocation")
        common.flushSdkLogs()
        settleDelivery()

        XCTAssertFalse(uploadedMessages().contains { $0.contains("Istanbul") }, "a line whose consent is gone by the upload is not sent")
        XCTAssertTrue(awaitingConsentLines.contains { ($0["m"] as? String)?.contains("Istanbul") == true }, "it waits for its consent again")
    }

    // MARK: - deciding without a response

    func testLogGathering_noResponseDecidesOffOnlyWhileUndecided() throws {
        capture(3)
        XCTAssertEqual(stateUndecided, state)

        common.decideLogGatheringOffIfUndecided("fetch failed")

        XCTAssertEqual(stateOff, state, "nothing can adopt the lines this run, holding them is pointless")
        XCTAssertEqual(0, bufferedLines.count)

        common.updateLogGatheringState(true, levels: allLevels, batch: defaultBatchSize, lgid: "gather_keep")
        clearBuffer()
        capture(3)

        common.decideLogGatheringOffIfUndecided("fetch failed")

        XCTAssertEqual(stateGathering, state, "a running gather survives a transient failure of the periodic refetch")
        XCTAssertEqual(3, harnessLines.count)
    }

    func testLogGathering_temporaryDeviceIdDecidesOff() throws {
        let config = createBaseConfig()
        config.requiresConsent = false
        config.manualSessionHandling = true
        config.enableTemporaryDeviceIDMode()
        Countly.sharedInstance().start(with: config)

        XCTAssertEqual(stateOff, state, "no behavior settings are fetched in temporary mode, so no directive can arrive")
    }

    func testLogGathering_disabledBehaviorSettingsUpdatesDecideOff() throws {
        let config = createBaseConfig()
        config.requiresConsent = false
        config.manualSessionHandling = true
        config.disableSDKBehaviorSettingsUpdates = true
        Countly.sharedInstance().start(with: config)

        XCTAssertEqual(stateOff, state)
    }

    // MARK: - the character ceiling and level sanitising

    func testLogGathering_characterCeilingDropsTheOldestLines() throws {
        // short of the message cap, so the counter suffix the helper appends survives
        let long = String(repeating: "c", count: maxMessageLength - 100)
        capture(40, message: long)

        // 40 x 4000 is past 128 KB, so the oldest went, and they count once a gather adopts the rest
        XCTAssertLessThanOrEqual(bufferedLines.count, 32)
        XCTAssertLessThanOrEqual(bufferedLines.reduce(0) { $0 + (($1["m"] as? String)?.count ?? 0) }, 128 * 1024)
        XCTAssertEqual(long + " 39", bufferedLines.last?["m"] as? String)

        common.updateLogGatheringState(true, levels: "d", batch: maxBufferedLines, lgid: "gather_long_lines_ceiling")
        XCTAssertGreaterThanOrEqual(dropCount, 8)
    }

    func testLogGathering_levelsAreLowercasedAndDeduplicated() throws {
        common.updateLogGatheringState(true, levels: "EeWwE", batch: defaultBatchSize, lgid: "gather_levels")

        XCTAssertEqual("ew", levels)
    }

    func testLogGathering_transportWorkOnTheCallingThreadIsNotGathered() throws {
        common.updateLogGatheringState(true, levels: allLevels, batch: defaultBatchSize, lgid: "gather_thread")
        clearBuffer()

        common.setSdkLogsTransportWork(true)
        capture(3)
        common.setSdkLogsTransportWork(false)
        capture(2)

        XCTAssertEqual(2, harnessLines.count, "the request path logs the batch it sends, gathering that would re-upload it every tick")
    }

    func testLogGathering_ownTransportLinesAreNotGathered() throws {
        startSDK()

        common.updateLogGatheringState(true, levels: allLevels, batch: minBatchSize, lgid: "gather_transport")
        clearBuffer()
        capture(minBatchSize)

        common.flushSdkLogs()
        settleDelivery()

        // uploading a batch is itself a request, and the request path logs the request in full.
        // Gathering that line would nest each batch inside the next one.
        let held = bufferedLines.compactMap { $0["m"] as? String }
        XCTAssertTrue(held.allSatisfy { !$0.contains("sdk_logs") }, "held a line describing the upload: \(held)")
    }

    func testLogGathering_realLogLinesCarryNoLevelPrefixInTheMessage() throws {
        startSDK()
        common.updateLogGatheringState(true, levels: allLevels, batch: defaultBatchSize, lgid: "gather_prefix")
        clearBuffer()

        // real lines, through CountlyInternalLog, not the capture funnel directly
        Countly.sharedInstance().recordEvent("prefix_probe")
        Countly.sharedInstance().views().startAutoStoppedView("prefix_probe_view")

        let messages = bufferedLines.compactMap { $0["m"] as? String }
        XCTAssertFalse(messages.isEmpty, "the SDK logged nothing to check")

        // the level travels in the line's own field, and the dashboard renders it from there, so a
        // prefix in the message would be the same level a second time
        let prefixes = ["[Error]", "[Warning]", "[Info]", "[Debug]", "[Verbose]"]
        let offenders = messages.filter { message in prefixes.contains { message.hasPrefix($0) } }
        XCTAssertTrue(offenders.isEmpty, "level prefix duplicated into the message: \(offenders.prefix(3))")

        XCTAssertTrue(bufferedLines.allSatisfy { allLevels.contains(($0["l"] as? String) ?? "") },
                      "and every line still carries its level in its own field")
    }

    func testLogGathering_capturedLineCarryingTheTransportMarkerIsIgnored() throws {
        common.updateLogGatheringState(true, levels: allLevels, batch: defaultBatchSize, lgid: "gather_marker")
        clearBuffer()

        common.captureSdkLogLine("request started &sdk_logs={\"i\":\"x\"}", level: CChar(Character("d").asciiValue!))

        XCTAssertEqual(0, bufferedLines.count)
    }
}

#if os(iOS)
/// A navigation response the web view delegate can be handed without loading a page.
private final class NavigationResponseStub: WKNavigationResponse {
    private let stubbedResponse: URLResponse

    /// A navigation response that hands the delegate the given response.
    init(response: URLResponse) {
        stubbedResponse = response
        super.init()
    }

    override var response: URLResponse { stubbedResponse }
}
#endif

/// The sdk_logs batches a mock server received, in arrival order. Filled on the URL loading threads, read by the test.
private final class ReceivedLogBatches {
    private let lock = NSLock()
    private var received: [[String: Any]] = []
    private let harnessPrefix: String

    /// Records batches, telling the test's own lines apart by the given message prefix.
    init(harnessPrefix: String) {
        self.harnessPrefix = harnessPrefix
    }

    /// Records one received batch.
    func append(_ batch: [String: Any]) {
        lock.lock()
        received.append(batch)
        lock.unlock()
    }

    /// Every batch received so far.
    var batches: [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return received
    }

    /// The messages of the test's own lines across every received batch, in arrival order.
    var harnessMessages: [String] {
        batches.flatMap { ($0["l"] as? [[String: Any]]) ?? [] }.compactMap { $0["m"] as? String }.filter { $0.hasPrefix(harnessPrefix) }
    }
}

/// Collects everything the SDK hands to a host app's logger, so a test can tell the local log apart from the uploaded one.
private class RecordingLogger: NSObject, CountlyLoggerDelegate {
    private let lock = NSLock()
    private var recorded: [String] = []

    /// The lines received so far. The SDK logs from any of its threads, so the list is read and written under a lock.
    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func internalLog(_ log: String, with level: CLYInternalLogLevel) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(log)
    }
}
