import XCTest
@testable import Countly

/// Tests for the server armed connection test: the trigger on a live 'ct', the probe battery, grading,
/// the combined rows, the report shape and its caps, and what must never happen (persisting 'ct',
/// probing while networking is off, two batteries at once).
class CountlyConnectionTestTests: CountlyBaseTestCase {

    private let expectedFeatures = ["core", "core-write", "sc", "rc", "ab", "feedback", "feedback-widget", "feedback-submit", "content", "feedback-page", "feedback-assets", "content-page"]
    private let expectedProbePaths = [
        "/o/ping", "/i", "/o/sdk?method=rc", "/o/sdk?method=ab_fetch_variants", "/o/sdk?method=feedback",
        "/o/surveys/nps/widget", "/o/surveys/survey/widget", "/o/feedback/widget", "/i/feedback/inputs", "/o/sdk/content",
        "/feedback/nps", "/feedback/survey", "/feedback/rating",
        "/surveys/images/ct-probe.png", "/star-rating/images/ct-probe.png", "/_external/content/"
    ]

    private var probeRequests: [URLRequest] = []
    private let probeLock = NSLock()

    override func setUp() {
        super.setUp()
        TestUtils.cleanup()
        resetRecordedProbes()
        UserDefaults.standard.removeObject(forKey: "kCountlyServerConfigPersistencyKey")
    }

    override func tearDown() {
        // requests still in flight after the test must not trip the protocol's missing handler check
        MockURLProtocol.requestHandler = { request in
            ("{}".data(using: .utf8), HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil), nil)
        }
        Countly.sharedInstance().halt(true)
        UserDefaults.standard.removeObject(forKey: "kCountlyServerConfigPersistencyKey")
        super.tearDown()
    }

    // MARK: - helpers

    /// Path plus query of a probe, without the marker and cache buster the SDK appends.
    private func probePath(_ request: URLRequest) -> String {
        guard let url = request.url, let host = url.host, let hostRange = url.absoluteString.range(of: host) else { return "" }
        // taken from the raw string, URL.path would drop the trailing slash of '/_external/content/'
        var path = String(url.absoluteString[hostRange.upperBound...])
        if let queryStart = path.firstIndex(of: "?") {
            let query = String(path[path.index(after: queryStart)...])
            path = String(path[..<queryStart])
            let kept = query.split(separator: "&").filter { !$0.hasPrefix("ct=") && !$0.hasPrefix("_=") }
            if !kept.isEmpty { path += "?" + kept.joined(separator: "&") }
        }
        return path
    }

    /// The probes recorded so far. The battery runs on its own queue, so every access is locked.
    private func recordedProbes() -> [URLRequest] {
        probeLock.lock()
        defer { probeLock.unlock() }
        return probeRequests
    }

    private func recordProbe(_ request: URLRequest) {
        probeLock.lock()
        defer { probeLock.unlock() }
        probeRequests.append(request)
    }

    private func resetRecordedProbes() {
        probeLock.lock()
        defer { probeLock.unlock() }
        probeRequests = []
    }

    private func isProbe(_ request: URLRequest) -> Bool {
        (request.url?.query ?? "").contains("ct=1") && !(request.url?.query ?? "").contains("app_key=")
    }

    /// Answers the behavior settings fetch with the given response, records probes and answers them
    /// from the status table (400 by default), and fails every queued request so it stays in the queue.
    /// With 'holdSettingsUntil', the settings reply, and so the battery, waits until the test signals it.
    private func installHandler(scResponse: String, probeStatus: [String: Int] = [:], probeError: [String: Error] = [:], probeDelay: TimeInterval = 0, holdSettingsUntil: DispatchSemaphore? = nil) {
        MockURLProtocol.requestHandler = { [self] request in
            let urlString = request.url?.absoluteString ?? ""
            if urlString.contains("method=sc") && urlString.contains("app_key=") {
                _ = holdSettingsUntil?.wait(timeout: .now() + 5)
                return (scResponse.data(using: .utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil), nil)
            }
            if isProbe(request) {
                recordProbe(request)
                if probeDelay > 0 { Thread.sleep(forTimeInterval: probeDelay) }
                let path = probePath(request)
                if let error = probeError[path] {
                    return (nil, nil, error)
                }
                let status = probeStatus[path] ?? (path == "/o/ping" || path.hasSuffix(".png") || path.hasPrefix("/_external") ? 200 : 400)
                return ("{}".data(using: .utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil), nil)
            }
            return ("{\"result\":\"fail\"}".data(using: .utf8), HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil), nil)
        }
    }

    private func armedResponse(networking: Bool = true) -> String {
        var json = ServerConfigBuilder().networking(networking).buildJson()
        json["ct"] = 1
        let data = try! JSONSerialization.data(withJSONObject: json)
        return String(data: data, encoding: .utf8)!
    }

    private func startSDK(customHeaders: [String: String]? = nil) {
        let config = createBaseConfig()
        config.requiresConsent = false
        config.manualSessionHandling = true
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        config.urlSessionConfiguration = sessionConfig
        Countly.sharedInstance().start(with: config)
        if let headers = customHeaders {
            Countly.sharedInstance().addCustomNetworkRequestHeaders(headers)
        }
    }

    /// The decoded 'ct_results' reports in the request queue, in order.
    private func queuedReports() -> [[String: Any]] {
        guard let rq = TestUtils.getCurrentRQ() else { return [] }
        return rq.compactMap { request in
            let parsed = TestUtils.parseQueryString(request)
            guard let raw = parsed["ct_results"] else { return nil }
            if let dict = raw as? [String: Any] { return dict }
            if let string = raw as? String, let data = string.data(using: .utf8) {
                return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            return nil
        }
    }

    private func waitForReport(timeout: TimeInterval = TestUtils.asyncTimeout) -> [String: Any]? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let report = queuedReports().first { return report }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return queuedReports().first
    }

    private func rows(_ report: [String: Any]) -> [[String: Any]] {
        report["results"] as? [[String: Any]] ?? []
    }

    private func row(_ report: [String: Any], _ feature: String) -> [String: Any]? {
        rows(report).first { ($0["f"] as? String) == feature }
    }

    private var connectionTest: CountlyConnectionTest { CountlyConnectionTest.sharedInstance() }

    // MARK: - battery and report

    func test_armedLiveResponse_probesEveryRowAndQueuesOneReportInOrder() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        installHandler(scResponse: armedResponse())
        startSDK()

        let report = try XCTUnwrap(waitForReport(), "no ct_results reached the request queue")

        // one report, every row, in spec order
        XCTAssertEqual(1, queuedReports().count)
        XCTAssertEqual(expectedFeatures, rows(report).compactMap { $0["f"] as? String })
        XCTAssertEqual(TestUtils.SDK_NAME, (report["sdk"] as? [String: Any])?["name"] as? String)
        XCTAssertEqual(TestUtils.SDK_VERSION, (report["sdk"] as? [String: Any])?["version"] as? String)
        XCTAssertGreaterThan((report["ts"] as? NSNumber)?.int64Value ?? 0, 1_600_000_000_000)

        // 16 parameterless requests, marker and cache buster on each, host path joined once
        let probes = recordedProbes()
        XCTAssertEqual(expectedProbePaths, probes.map(probePath))
        for probe in probes {
            let url = probe.url!.absoluteString
            XCTAssertEqual("GET", probe.httpMethod)
            XCTAssertNil(probe.httpBody)
            XCTAssertFalse(url.contains("app_key="), url)
            XCTAssertFalse(url.contains("device_id="), url)
            XCTAssertTrue(url.contains("ct=1"), url)
            XCTAssertTrue(url.contains("&_="), url)
            XCTAssertTrue(url.hasPrefix("https://testing.count.ly/"), url)
            XCTAssertFalse(url.contains("ly//"), url)
        }

        // healthy grading: 400 is reachable, the two strict rows saw their 200
        for row in rows(report) {
            XCTAssertEqual(true, row["ok"] as? Bool, "\(row)")
            XCTAssertNil(row["e"], "\(row)")
        }
        XCTAssertEqual(200, row(report, "core")?["st"] as? Int)
        XCTAssertEqual(400, row(report, "core-write")?["st"] as? Int)
        XCTAssertEqual(200, row(report, "feedback-assets")?["st"] as? Int)

        // the sc row carries the latency of the fetch that delivered the flag
        let sc = try XCTUnwrap(row(report, "sc"))
        XCTAssertEqual(200, sc["st"] as? Int)
        XCTAssertGreaterThanOrEqual((sc["ms"] as? NSNumber)?.int64Value ?? -1, 0)

        // path counts only on the combined rows
        XCTAssertEqual(3, row(report, "feedback-widget")?["n"] as? Int)
        XCTAssertEqual(3, row(report, "feedback-page")?["n"] as? Int)
        XCTAssertEqual(2, row(report, "feedback-assets")?["n"] as? Int)
        XCTAssertNil(row(report, "core")?["n"])
        XCTAssertNil(row(report, "rc")?["n"])
    }

    func test_faultyEndpoints_areGradedPerSpec() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        installHandler(scResponse: armedResponse(),
                       probeStatus: [
                        "/o/ping": 404,                       // strict row, a 404 is the DB being down
                        "/o/sdk?method=rc": 403,              // proxy allowlist
                        "/o/sdk/content": 302,                // captive portal
                        "/o/surveys/survey/widget": 500,      // second path of a combined row
                        "/o/feedback/widget": 404,            // widget not found is still the application answering
                        "/star-rating/images/ct-probe.png": 404,
                       ],
                       probeError: [
                        "/o/sdk?method=ab_fetch_variants": NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut),
                        "/i/feedback/inputs": NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost),
                       ])
        startSDK()

        let report = try XCTUnwrap(waitForReport())

        let core = try XCTUnwrap(row(report, "core"))
        XCTAssertEqual(false, core["ok"] as? Bool)
        XCTAssertEqual(404, core["st"] as? Int)
        XCTAssertEqual("HTTP 404", core["e"] as? String)

        XCTAssertEqual("HTTP 403", row(report, "rc")?["e"] as? String)
        XCTAssertEqual(403, row(report, "rc")?["st"] as? Int)

        XCTAssertEqual("redirected", row(report, "content")?["e"] as? String)
        XCTAssertEqual(302, row(report, "content")?["st"] as? Int)

        let ab = try XCTUnwrap(row(report, "ab"))
        XCTAssertEqual("timeout", ab["e"] as? String)
        XCTAssertEqual(0, ab["st"] as? Int)
        XCTAssertEqual(false, ab["ok"] as? Bool)

        XCTAssertEqual("transport error", row(report, "feedback-submit")?["e"] as? String)
        XCTAssertEqual(0, row(report, "feedback-submit")?["st"] as? Int)

        // combined row: first failing path decides status and reason, the 404 on the third path is fine
        let widget = try XCTUnwrap(row(report, "feedback-widget"))
        XCTAssertEqual(false, widget["ok"] as? Bool)
        XCTAssertEqual(500, widget["st"] as? Int)
        XCTAssertEqual("HTTP 500", widget["e"] as? String)
        XCTAssertEqual(3, widget["n"] as? Int)

        // strict combined row: anything but 2xx on any path fails it
        let assets = try XCTUnwrap(row(report, "feedback-assets"))
        XCTAssertEqual(false, assets["ok"] as? Bool)
        XCTAssertEqual(404, assets["st"] as? Int)
        XCTAssertEqual("HTTP 404", assets["e"] as? String)

        // untouched rows stay green
        XCTAssertEqual(true, row(report, "feedback")?["ok"] as? Bool)
        XCTAssertEqual(true, row(report, "content-page")?["ok"] as? Bool)
    }

    func test_ctIsStrippedBeforeCachingAndNeverReadFromStorage() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        installHandler(scResponse: armedResponse())
        startSDK()
        _ = try XCTUnwrap(waitForReport())

        let stored = UserDefaults.standard.dictionary(forKey: "kCountlyServerConfigPersistencyKey")
        XCTAssertNotNil(stored?["c"], "the config itself must still be cached")
        XCTAssertNil(stored?["ct"], "the flag must never survive into storage")

        // a stored flag, even if one got there somehow, must not arm anything on the next start. The storage
        // is cleared so the report of this run, which a halt keeping the storage would keep queued, is not
        // counted as the next one's
        Countly.sharedInstance().halt(true)
        var poisoned = ServerConfigBuilder().buildJson()
        poisoned["ct"] = 1
        UserDefaults.standard.set(poisoned, forKey: "kCountlyServerConfigPersistencyKey")
        resetRecordedProbes()
        installHandler(scResponse: ServerConfigBuilder().build())
        startSDK()
        TestUtils.sleep(2) {}

        let probes = recordedProbes()
        XCTAssertEqual(0, probes.count, "the battery ran from stored config")
        XCTAssertEqual(0, queuedReports().count)
    }

    func test_networkingDisabledByServerConfig_skipsTheBattery() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        installHandler(scResponse: armedResponse(networking: false))
        startSDK()
        TestUtils.sleep(2) {}

        let probes = recordedProbes()
        XCTAssertEqual(0, probes.count, "the operator's own kill switch outranks the test")
        XCTAssertEqual(0, queuedReports().count)
    }

    func test_secondDeliveryWhileABatteryRuns_isIgnored() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        installHandler(scResponse: armedResponse(), probeDelay: 0.15)
        startSDK()

        // the battery takes about 2.5 s with the delay, arm again in the middle of it
        TestUtils.sleep(0.5) {}
        XCTAssertTrue(connectionTest.isBatteryRunning)
        connectionTest.startBattery(withServerConfigLatency: 5)
        connectionTest.startBattery(withServerConfigLatency: 5)

        _ = try XCTUnwrap(waitForReport())
        TestUtils.sleep(1) {}

        XCTAssertEqual(1, queuedReports().count, "each delivery during a running battery must be dropped, not queued")
        let probes = recordedProbes()
        XCTAssertEqual(expectedProbePaths.count, probes.count)
        XCTAssertFalse(connectionTest.isBatteryRunning)
    }

    func test_probesCarryTheSdkCustomHeaders() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        let headersAdded = DispatchSemaphore(value: 0)
        installHandler(scResponse: armedResponse(), holdSettingsUntil: headersAdded)
        startSDK(customHeaders: ["X-Gateway-Token": "abc123"])
        headersAdded.signal()
        _ = try XCTUnwrap(waitForReport())

        let probes = recordedProbes()
        XCTAssertFalse(probes.isEmpty)
        for probe in probes {
            XCTAssertEqual("abc123", probe.allHTTPHeaderFields?["X-Gateway-Token"], "a header checking gateway would report a healthy server as unreachable")
        }
    }

    /// While the server turns tracking off the queue refuses every request, so the battery is not run at all.
    func test_trackingDisabledByServerConfig_skipsTheBattery() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        var json = ServerConfigBuilder().tracking(false).buildJson()
        json["ct"] = 1
        let reply = String(data: try JSONSerialization.data(withJSONObject: json), encoding: .utf8)!
        installHandler(scResponse: reply)
        startSDK()
        TestUtils.sleep(1) {}

        XCTAssertTrue(recordedProbes().isEmpty, "no probe traffic for a report that could never be queued")
        XCTAssertFalse(connectionTest.isBatteryRunning)
        XCTAssertTrue(queuedReports().isEmpty)
    }

    /**
     * <pre>
     * A battery the app goes to the background during is not reported, its probes stalled, and it runs again
     * in full once the app is active, without waiting for the server to deliver the request again.
     *
     * 1- Arm the test with slow probes and wait for the first probe
     * 2- Send the app to the background, verify the battery stops early and nothing is reported
     * 3- Bring the app back, verify a complete battery runs and exactly one report is queued
     * </pre>
     */
    func test_appGoingToBackgroundDuringTheBattery_discardsItAndRunsItAgainWhenActive() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        installHandler(scResponse: armedResponse(), probeDelay: 0.1)
        startSDK()
        TestUtils.waitUntil("the battery to start probing") { !self.recordedProbes().isEmpty }

        connectionTest.noteAppSuspended()
        TestUtils.waitUntil("the interrupted battery to stop") { !self.connectionTest.isBatteryRunning }
        XCTAssertFalse(connectionTest.isBatteryRunning)
        XCTAssertLessThan(recordedProbes().count, expectedProbePaths.count, "the interrupted battery stops probing")
        XCTAssertTrue(queuedReports().isEmpty, "a battery the app went to the background during is not reported")

        resetRecordedProbes()
        connectionTest.noteAppResumed()
        let report = try XCTUnwrap(waitForReport())
        XCTAssertEqual(expectedFeatures, rows(report).compactMap { $0["f"] as? String })
        XCTAssertEqual(expectedProbePaths.count, recordedProbes().count, "the battery runs again in full")
        XCTAssertEqual(1, queuedReports().count)
    }

    /**
     * <pre>
     * The report of a battery that runs while the device ID changes without merge goes out under the device ID
     * the test was armed for, the only user the server accepts it from. A report is never queued without an app key.
     *
     * 1- Arm the test with slow probes and change the device ID without merge while it runs
     * 2- Verify the report carries the armed device ID while the SDK moved on to the new one
     * 3- Clear the app key, queue a report, and verify it is dropped
     * </pre>
     */
    func test_report_forAUserReplacedWithoutMerge_goesOutUnderTheArmedDeviceID() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        installHandler(scResponse: armedResponse(), probeDelay: 0.1)
        startSDK()
        let armedDeviceID = CountlyDeviceInfo.sharedInstance().deviceID
        TestUtils.waitUntil("the battery to start probing") { !self.recordedProbes().isEmpty }

        Countly.sharedInstance().changeDeviceIDWithoutMerge("replacement_user")
        _ = try XCTUnwrap(waitForReport())

        let reportRequest = try XCTUnwrap(TestUtils.getCurrentRQ()?.first { $0.contains("ct_results=") })
        XCTAssertEqual(armedDeviceID, TestUtils.parseQueryString(reportRequest)["device_id"] as? String)
        XCTAssertEqual("replacement_user", CountlyDeviceInfo.sharedInstance().deviceID)

        let manager = CountlyConnectionManager.sharedInstance()!
        let appKey = manager.appKey
        manager.appKey = ""
        manager.sendConnectionTestResults("{}", deviceID: "any_user", deviceIDType: 0)
        manager.appKey = appKey
        XCTAssertEqual(1, queuedReports().count, "a report without an app key is dropped")
    }

    /**
     * <pre>
     * A battery armed while the app is in the background waits for the foreground, where its probes do not stall.
     *
     * 1- Hold the armed settings reply, send the app to the background, then release the reply
     * 2- Verify no probe runs and no report is queued while the app stays in the background
     * 3- Bring the app back, verify a complete battery runs and one report is queued
     * </pre>
     */
    func test_batteryArmedWhileTheAppIsInTheBackground_waitsForTheForeground() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        let releaseSettings = DispatchSemaphore(value: 0)
        installHandler(scResponse: armedResponse(), holdSettingsUntil: releaseSettings)
        startSDK()

        connectionTest.noteAppSuspended()
        releaseSettings.signal()
        TestUtils.sleep(1) {}
        XCTAssertTrue(recordedProbes().isEmpty, "no probe runs while the app is in the background")
        XCTAssertFalse(connectionTest.isBatteryRunning)
        XCTAssertTrue(queuedReports().isEmpty)

        connectionTest.noteAppResumed()
        let report = try XCTUnwrap(waitForReport())
        XCTAssertEqual(expectedFeatures, rows(report).compactMap { $0["f"] as? String })
        XCTAssertEqual(expectedProbePaths.count, recordedProbes().count, "the battery runs in full once the app is active")
        XCTAssertEqual(1, queuedReports().count)
    }

    /**
     * <pre>
     * The server arms the test for the user whose settings fetch asked for it, so a device ID change without merge while
     * that fetch is in flight does not move the report to the new user.
     *
     * 1- Hold the armed settings reply and change the device ID without merge
     * 2- Release the reply and verify the first report carries the device ID the fetch was made for
     * </pre>
     */
    func test_report_forAUserReplacedWithoutMergeDuringTheSettingsFetch_goesOutUnderTheArmedDeviceID() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        let releaseSettings = DispatchSemaphore(value: 0)
        installHandler(scResponse: armedResponse(), holdSettingsUntil: releaseSettings)
        startSDK()
        let armedDeviceID = CountlyDeviceInfo.sharedInstance().deviceID

        Countly.sharedInstance().changeDeviceIDWithoutMerge("replacement_user")
        releaseSettings.signal()
        _ = try XCTUnwrap(waitForReport())

        let reportRequest = try XCTUnwrap(TestUtils.getCurrentRQ()?.first { $0.contains("ct_results=") })
        XCTAssertEqual(armedDeviceID, TestUtils.parseQueryString(reportRequest)["device_id"] as? String)
        XCTAssertEqual("replacement_user", CountlyDeviceInfo.sharedInstance().deviceID)
    }

    /**
     * <pre>
     * A merge cancels the run the server armed for the merged user, so a merge while the arming fetch is on its way
     * leaves the battery unrun.
     *
     * 1- Hold the armed settings reply and change the device ID with merge
     * 2- Release the reply and verify no probe runs and no report is queued
     * </pre>
     */
    func test_mergeDuringTheArmingFetch_skipsTheBattery() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        let releaseSettings = DispatchSemaphore(value: 0)
        installHandler(scResponse: armedResponse(), holdSettingsUntil: releaseSettings)
        startSDK()

        Countly.sharedInstance().changeDeviceID(withMerge: "merged_user")
        releaseSettings.signal()
        TestUtils.sleep(1) {}

        XCTAssertTrue(recordedProbes().isEmpty, "the server cancelled the run, so nothing is probed")
        XCTAssertFalse(connectionTest.isBatteryRunning)
        XCTAssertTrue(queuedReports().isEmpty)
    }

    /**
     * <pre>
     * A merge while the battery runs drops its report: the server rejects it under the merged ID, and under the old ID it
     * would create the merged away user again.
     *
     * 1- Arm the test with slow probes and change the device ID with merge while it runs
     * 2- Verify the battery finishes and no report is queued under either device ID
     * </pre>
     */
    func test_mergeDuringTheBattery_dropsTheReport() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        installHandler(scResponse: armedResponse(), probeDelay: 0.1)
        startSDK()
        TestUtils.waitUntil("the battery to start probing") { !self.recordedProbes().isEmpty }

        Countly.sharedInstance().changeDeviceID(withMerge: "merged_user")
        TestUtils.waitUntil("the battery to finish", timeout: 15) { !self.connectionTest.isBatteryRunning }

        XCTAssertFalse(connectionTest.isBatteryRunning)
        XCTAssertEqual(expectedProbePaths.count, recordedProbes().count, "the battery itself runs to the end")
        XCTAssertTrue(queuedReports().isEmpty, "the report of a run the merge cancelled is dropped")
    }

    // MARK: - pure pieces

    func test_grading() {
        XCTAssertNil(CountlyConnectionTest.gradeStatus(200, failure: nil, requiresSuccessStatus: false))
        XCTAssertNil(CountlyConnectionTest.gradeStatus(400, failure: nil, requiresSuccessStatus: false))
        XCTAssertNil(CountlyConnectionTest.gradeStatus(404, failure: nil, requiresSuccessStatus: false))
        XCTAssertEqual("HTTP 403", CountlyConnectionTest.gradeStatus(403, failure: nil, requiresSuccessStatus: false))
        XCTAssertEqual("HTTP 502", CountlyConnectionTest.gradeStatus(502, failure: nil, requiresSuccessStatus: false))
        XCTAssertEqual("redirected", CountlyConnectionTest.gradeStatus(301, failure: nil, requiresSuccessStatus: false))
        XCTAssertEqual("timeout", CountlyConnectionTest.gradeStatus(0, failure: "timeout", requiresSuccessStatus: false))
        XCTAssertEqual("transport error", CountlyConnectionTest.gradeStatus(0, failure: nil, requiresSuccessStatus: false))
        // strict rows
        XCTAssertNil(CountlyConnectionTest.gradeStatus(204, failure: nil, requiresSuccessStatus: true))
        XCTAssertEqual("HTTP 400", CountlyConnectionTest.gradeStatus(400, failure: nil, requiresSuccessStatus: true))
        XCTAssertEqual("HTTP 404", CountlyConnectionTest.gradeStatus(404, failure: nil, requiresSuccessStatus: true))
    }

    func test_probeURL_resolvesAgainstThePathPrefixAndAppendsTheMarker() {
        let ping = CountlyConnectionTest.probeURL(forPath: "/o/ping", serverURL: "https://x.com/countly//")
        XCTAssertTrue(ping.hasPrefix("https://x.com/countly/o/ping?ct=1&_="), ping)

        let rc = CountlyConnectionTest.probeURL(forPath: "/o/sdk?method=rc", serverURL: "https://x.com")
        XCTAssertTrue(rc.hasPrefix("https://x.com/o/sdk?method=rc&ct=1&_="), rc)

        let noSlash = CountlyConnectionTest.probeURL(forPath: "i", serverURL: "https://x.com/")
        XCTAssertTrue(noSlash.hasPrefix("https://x.com/i?ct=1&_="), noSlash)
    }

    func test_report_enforcesRowByteAndErrorCaps() throws {
        var rows: [[String: Any]] = []
        for i in 0..<40 {
            rows.append(["f": "row\(i)", "ok": false, "st": 403, "ms": 12, "e": String(repeating: "x", count: 300)])
        }
        rows[3]["e"] = "opaque"

        let json = connectionTest.buildReport(rows)
        let report = try XCTUnwrap(try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as? [String: Any])
        let results = try XCTUnwrap(report["results"] as? [[String: Any]])

        XCTAssertLessThanOrEqual(results.count, 32)
        XCTAssertLessThanOrEqual(json.utf8.count, 8 * 1024)
        // 32 rows with 256 char reasons overflow the byte cap, so the reasons went, except the opaque qualifier
        XCTAssertEqual("opaque", results[3]["e"] as? String, "dropping the qualifier would upgrade a low confidence row")
        for (index, row) in results.enumerated() where index != 3 {
            XCTAssertNil(row["e"], "\(row)")
        }

        // under the byte cap a long reason is only truncated
        let single = connectionTest.buildReport([["f": "core", "ok": false, "st": 500, "ms": 1, "e": String(repeating: "y", count: 300)]])
        let singleReport = try XCTUnwrap(try JSONSerialization.jsonObject(with: single.data(using: .utf8)!) as? [String: Any])
        let singleRow = try XCTUnwrap((singleReport["results"] as? [[String: Any]])?.first)
        XCTAssertEqual(256, (singleRow["e"] as? String)?.count)
    }
}
