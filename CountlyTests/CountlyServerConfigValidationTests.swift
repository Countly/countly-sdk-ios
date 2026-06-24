import XCTest
@testable import Countly

/// Tests for the server-config validation, persistence cleanup,
/// per-category filter conflict resolution, and consent-during-init
/// behaviors introduced alongside the session_immediates changes.
class CountlyServerConfigValidationTests: CountlyBaseTestCase {

    private let persistencyKey = "kCountlyServerConfigPersistencyKey"
    private var localCountlyInstances: [Countly] = []

    override func setUp() {
        super.setUp()
        TestUtils.cleanup()
        localCountlyInstances = []
        UserDefaults.standard.removeObject(forKey: persistencyKey)
        UserDefaults.standard.synchronize()
    }

    override func tearDown() {
        for instance in localCountlyInstances {
            instance.halt(true)
        }
        localCountlyInstances = []
        if Countly.sharedInstance() != nil {
            Countly.sharedInstance().halt(true)
        }
        UserDefaults.standard.removeObject(forKey: persistencyKey)
        UserDefaults.standard.synchronize()
        super.tearDown()
    }

    private func createLocalCountly() -> Countly {
        let instance = Countly()
        localCountlyInstances.append(instance)
        return instance
    }

    private func setStoredServerConfig(_ payload: [String: Any]) {
        UserDefaults.standard.set(payload, forKey: persistencyKey)
        UserDefaults.standard.synchronize()
    }

    private func storedServerConfig() -> [String: Any] {
        return UserDefaults.standard.object(forKey: persistencyKey) as? [String: Any] ?? [:]
    }

    private func storedConfigDictionary() -> [String: Any] {
        return storedServerConfig()["c"] as? [String: Any] ?? [:]
    }

    private func makeServerConfig(_ config: [String: Any]) -> [String: Any] {
        return [
            "v": 1,
            "t": Int(Date().timeIntervalSince1970),
            "c": config
        ]
    }

    // MARK: - Type validation

    /// Invalid types for boolean keys must be stripped from the persisted config
    /// and must not change the corresponding SDK property.
    func test_validation_boolKeyWithInvalidType_isStrippedAndDefaultsKept() {
        setStoredServerConfig(makeServerConfig([
            "tracking": "not a bool",      // wrong type
            "networking": 42,               // wrong type (integer, not bool)
            "crt": true                     // valid bool
        ]))

        let cfg = TestUtils.createBaseConfig()
        cfg.enableServerConfiguration = true
        cfg.manualSessionHandling = true
        let countly = createLocalCountly()
        countly.start(with: cfg)

        // Valid bool was applied; invalid ones fell back to default (YES)
        XCTAssertTrue(CountlyServerConfig.sharedInstance().trackingEnabled())
        XCTAssertTrue(CountlyServerConfig.sharedInstance().networkingEnabled())
        XCTAssertTrue(CountlyServerConfig.sharedInstance().crashReportingEnabled())

        let persisted = storedConfigDictionary()
        XCTAssertNil(persisted["tracking"], "Invalid bool type should be stripped from persistence")
        XCTAssertNil(persisted["networking"], "Invalid bool type should be stripped from persistence")
        XCTAssertEqual(persisted["crt"] as? Bool, true)
    }

    /// Invalid types for integer keys must be stripped from the persisted config.
    func test_validation_integerKeyWithInvalidType_isStripped() {
        setStoredServerConfig(makeServerConfig([
            "eqs": "not a number",          // wrong type
            "rqs": 500                       // valid
        ]))

        let cfg = TestUtils.createBaseConfig()
        cfg.enableServerConfiguration = true
        cfg.manualSessionHandling = true
        let countly = createLocalCountly()
        countly.start(with: cfg)

        XCTAssertEqual(500, CountlyServerConfig.sharedInstance().requestQueueSize())

        let persisted = storedConfigDictionary()
        XCTAssertNil(persisted["eqs"], "Invalid integer type should be stripped")
        XCTAssertEqual(persisted["rqs"] as? Int, 500)
    }

    /// Integer values below the configured minimum must be stripped.
    /// `czi` (contentZoneInterval) requires minValue=16.
    func test_validation_integerBelowMin_isStripped_contentZoneInterval() {
        setStoredServerConfig(makeServerConfig([
            "czi": 5  // below minValue=16
        ]))

        let cfg = TestUtils.createBaseConfig()
        cfg.enableServerConfiguration = true
        cfg.manualSessionHandling = true
        let countly = createLocalCountly()
        countly.start(with: cfg)

        let persisted = storedConfigDictionary()
        XCTAssertNil(persisted["czi"], "czi below min should be stripped from persistence")
    }

    /// Integer values at/above the minimum should be accepted and persisted.
    func test_validation_integerAtMin_isAccepted_contentZoneInterval() {
        setStoredServerConfig(makeServerConfig([
            "czi": 16
        ]))

        let cfg = TestUtils.createBaseConfig()
        cfg.enableServerConfiguration = true
        cfg.manualSessionHandling = true
        let countly = createLocalCountly()
        countly.start(with: cfg)

        let persisted = storedConfigDictionary()
        XCTAssertEqual(persisted["czi"] as? Int, 16)
    }

    /// `dort` (dropOldRequestTime) has minValue=0 — zero is valid and must remain.
    func test_validation_integerZero_isAccepted_dropOldRequestTime() {
        setStoredServerConfig(makeServerConfig([
            "dort": 0
        ]))

        let cfg = TestUtils.createBaseConfig()
        cfg.enableServerConfiguration = true
        cfg.manualSessionHandling = true
        let countly = createLocalCountly()
        countly.start(with: cfg)

        let persisted = storedConfigDictionary()
        XCTAssertEqual(persisted["dort"] as? Int, 0)
    }

    /// Unknown keys in the config object must be stripped from persistence.
    func test_validation_unknownKeys_areStripped() {
        setStoredServerConfig(makeServerConfig([
            "tracking": true,             // known
            "totally_unknown_key": "abc", // unknown
            "another_unknown": 123        // unknown
        ]))

        let cfg = TestUtils.createBaseConfig()
        cfg.enableServerConfiguration = true
        cfg.manualSessionHandling = true
        let countly = createLocalCountly()
        countly.start(with: cfg)

        let persisted = storedConfigDictionary()
        XCTAssertEqual(persisted["tracking"] as? Bool, true)
        XCTAssertNil(persisted["totally_unknown_key"])
        XCTAssertNil(persisted["another_unknown"])
    }

    // MARK: - User-provided SDK limits preservation

    /// When server config returns valid keys but does not include a particular
    /// limit, the user-provided SDK limit must not be overridden by a stale default.
    func test_userLimits_preserved_whenServerConfigOmitsThem() {
        // Server config provides a valid SC payload that excludes eventQueueSize
        // and contentZoneInterval, but includes another valid key so that
        // notifySdkConfigChange is invoked.
        setStoredServerConfig(makeServerConfig([
            "tracking": true
        ]))

        let cfg = TestUtils.createBaseConfig()
        cfg.enableServerConfiguration = true
        cfg.manualSessionHandling = true
        cfg.eventSendThreshold = 7      // user-provided
        cfg.storedRequestsLimit = 555    // user-provided
        let countly = createLocalCountly()
        countly.start(with: cfg)

        XCTAssertEqual(7, CountlyPersistency.sharedInstance().eventSendThreshold,
                       "User-provided eventSendThreshold must not be overridden when server config omits eqs")
        XCTAssertEqual(555, CountlyPersistency.sharedInstance().storedRequestsLimit,
                       "User-provided storedRequestsLimit must not be overridden when server config omits rqs")
    }

    // MARK: - Per-category filter conflict resolution

    /// Drives the SDK's server-config fetch through a mocked URL session so
    /// that `mergeBehaviorSettings` runs with a controlled response payload.
    private func mockURLSessionConfig(returning configDict: [String: Any]) -> URLSessionConfiguration {
        let response = makeServerConfig(configDict)
        let data = try! JSONSerialization.data(withJSONObject: response)
        MockURLProtocol.requestHandler = { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("method=sc") {
                return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil), nil)
            }
            return ("{\"result\":\"fail\"}".data(using: .utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil), nil)
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return config
    }

    /// When a new merged config provides a whitelist for one category, the
    /// stored blacklist for that same category must be removed — but the
    /// filter for an unrelated category must be preserved.
    func test_perCategoryFilterConflict_doesNotClearUnrelatedCategories() {
        // Seed persisted config with both an event blacklist and a user
        // property blacklist already present.
        setStoredServerConfig(makeServerConfig([
            "eb": ["blocked_event"],
            "upb": ["blocked_prop"]
        ]))

        // Mock a server response that only introduces an event whitelist (`ew`).
        let cfg = TestUtils.createBaseConfig()
        cfg.manualSessionHandling = true
        cfg.urlSessionConfiguration = mockURLSessionConfig(returning: [
            "ew": ["allowed_event"]
        ])

        let countly = createLocalCountly()
        countly.start(with: cfg)

        TestUtils.sleep(2) {
            let persisted = self.storedConfigDictionary()
            XCTAssertNil(persisted["eb"], "eb must be removed because new config provided ew")
            XCTAssertEqual(persisted["ew"] as? [String], ["allowed_event"])
            XCTAssertEqual(persisted["upb"] as? [String], ["blocked_prop"],
                           "upb must be preserved — the new config did not touch the user-property category")
        }
    }

    /// Conflict resolution must work independently per category — providing
    /// both a segmentation blacklist and a user-property whitelist must
    /// remove only their same-category counterparts.
    func test_perCategoryFilterConflict_independentAcrossCategories() {
        setStoredServerConfig(makeServerConfig([
            "sw": ["s_keep"],
            "upb": ["u_blocked"]
        ]))

        let cfg = TestUtils.createBaseConfig()
        cfg.manualSessionHandling = true
        cfg.urlSessionConfiguration = mockURLSessionConfig(returning: [
            "sb": ["s_blocked"],
            "upw": ["u_allowed"]
        ])

        let countly = createLocalCountly()
        countly.start(with: cfg)

        TestUtils.sleep(2) {
            let persisted = self.storedConfigDictionary()
            XCTAssertNil(persisted["sw"], "sw must be removed because new config provided sb")
            XCTAssertEqual(persisted["sb"] as? [String], ["s_blocked"])
            XCTAssertNil(persisted["upb"], "upb must be removed because new config provided upw")
            XCTAssertEqual(persisted["upw"] as? [String], ["u_allowed"])
        }
    }

    // MARK: - Consent during init

    /// When server config requires consent and the user config does not,
    /// consent must be sent exactly once during init (not twice).
    func test_consent_sentOnceDuringInit_whenServerConfigEnablesConsent() {
        setStoredServerConfig(makeServerConfig([
            "cr": true
        ]))

        let cfg = TestUtils.createBaseConfig()
        cfg.enableServerConfiguration = true
        cfg.manualSessionHandling = true
        // Do NOT set requiresConsent on the user config — only the server config requires it.
        let countly = createLocalCountly()
        countly.start(with: cfg)

        TestUtils.sleep(1) {
            let rq = TestUtils.getCurrentRQ() ?? []
            let consentRequests = rq.filter { $0.contains("consent=") }
            XCTAssertEqual(1, consentRequests.count,
                           "Consent should be queued exactly once during init, got requests: \(rq)")
        }
    }

    // MARK: - ImmediateURLSession

    /// The new ImmediateURLSession must propagate any HTTP additional headers
    /// configured on the URLSessionConfiguration.
    func test_immediateURLSession_propagatesAdditionalHeaders() {
        let cfg = TestUtils.createBaseConfig()
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.httpAdditionalHeaders = ["X-Immediate-Test": "value1"]
        cfg.urlSessionConfiguration = sessionConfig
        cfg.manualSessionHandling = true

        Countly.sharedInstance().start(with: cfg)

        let immediate = CountlyCommon.sharedInstance().immediateURLSession()
        let headers = immediate.configuration.httpAdditionalHeaders as? [String: String]
        XCTAssertEqual(headers?["X-Immediate-Test"], "value1",
                       "ImmediateURLSession must inherit configured HTTPAdditionalHeaders")
    }

    /// ImmediateURLSession must also propagate `protocolClasses` so that
    /// callers (e.g. tests using a mock protocol) and pinned certs continue
    /// to work for non-queued requests.
    func test_immediateURLSession_propagatesProtocolClasses() {
        // Provide a noop handler so background traffic during SDK init does
        // not trigger MockURLProtocol's "handler not set" XCTFail.
        MockURLProtocol.requestHandler = { request in
            return (
                "{\"result\":\"ok\"}".data(using: .utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil),
                nil
            )
        }

        let cfg = TestUtils.createBaseConfig()
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        cfg.urlSessionConfiguration = sessionConfig
        cfg.manualSessionHandling = true

        Countly.sharedInstance().start(with: cfg)

        let immediate = CountlyCommon.sharedInstance().immediateURLSession()
        let names = (immediate.configuration.protocolClasses ?? []).map { String(describing: $0) }
        XCTAssertTrue(names.contains("MockURLProtocol"),
                      "ImmediateURLSession must propagate user-provided protocolClasses, got: \(names)")
    }

    /// ImmediateURLSession must not be constrained by the SDK's configured
    /// request timeout. The timeout on the returned session should match the
    /// system default (60s), regardless of whatever the queued URLSession was
    /// set to.
    func test_immediateURLSession_doesNotInheritSdkRequestTimeout() {
        let cfg = TestUtils.createBaseConfig()
        cfg.manualSessionHandling = true
        cfg.requestTimeoutDuration = 5  // SDK timeout small enough to detect

        Countly.sharedInstance().start(with: cfg)

        let immediate = CountlyCommon.sharedInstance().immediateURLSession()
        XCTAssertEqual(60.0, immediate.configuration.timeoutIntervalForRequest, accuracy: 0.001,
                       "ImmediateURLSession should not adopt the SDK's request timeout — that's the bug being mitigated")
    }

    // MARK: - Server config persistence is the cleaned dictionary

    /// After populate, the persisted config must reflect the cleaned version
    /// of the dictionary (no invalid types, no unknown keys, no out-of-range
    /// values). Stale entries from a previous launch must not leak through.
    func test_serverConfig_persistedDictionaryReflectsCleaning() {
        setStoredServerConfig(makeServerConfig([
            "tracking": true,                  // kept
            "networking": "not a bool",        // stripped (type)
            "czi": 5,                          // stripped (below min 16)
            "unknown_x": [1, 2, 3]             // stripped (unknown)
        ]))

        let cfg = TestUtils.createBaseConfig()
        cfg.enableServerConfiguration = true
        cfg.manualSessionHandling = true
        let countly = createLocalCountly()
        countly.start(with: cfg)

        let persisted = storedConfigDictionary()
        XCTAssertEqual(persisted["tracking"] as? Bool, true)
        XCTAssertNil(persisted["networking"])
        XCTAssertNil(persisted["czi"])
        XCTAssertNil(persisted["unknown_x"])
    }

    // MARK: - Consent gated by hasFinishedInit

    /// hasFinishedInit must be NO before start completes and YES afterwards.
    /// This is what gates the early consent-send path in populateServerConfig.
    func test_hasFinishedInit_flipsToTrueAfterStartCompletes() {
        XCTAssertFalse(CountlyCommon.sharedInstance().hasFinishedInit,
                       "hasFinishedInit must start NO before init")

        let cfg = TestUtils.createBaseConfig()
        cfg.manualSessionHandling = true
        Countly.sharedInstance().start(with: cfg)

        XCTAssertTrue(CountlyCommon.sharedInstance().hasFinishedInit,
                      "hasFinishedInit must be YES after start completes")

        Countly.sharedInstance().halt(true)
        XCTAssertFalse(CountlyCommon.sharedInstance().hasFinishedInit,
                       "hasFinishedInit must reset to NO on halt")
    }

    // MARK: - Connection manager queue-concurrency guard

    /// Calling `proceedOnQueue` rapidly when a request is in flight must not
    /// double-send the same request. The atomic `isProcessingQueue` flag
    /// guards against re-entrancy.
    ///
    /// This test counts outbound hits for a uniquely-marked request and
    /// asserts at most one is sent even when proceedOnQueue is invoked
    /// concurrently from many threads.
    func test_proceedOnQueue_doesNotDoubleSendHeadRequest() {
        let lock = NSLock()
        var markerHits = 0
        MockURLProtocol.requestHandler = { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("unique_marker=x") {
                lock.lock()
                markerHits += 1
                lock.unlock()
            }
            return (
                "{\"result\":\"ok\"}".data(using: .utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil),
                nil
            )
        }

        let cfg = TestUtils.createBaseConfig()
        cfg.manualSessionHandling = true
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        cfg.urlSessionConfiguration = sessionConfig

        Countly.sharedInstance().start(with: cfg)

        // Queue a single uniquely-marked request and pound proceedOnQueue from many threads.
        Countly.sharedInstance().addDirectRequest(["unique_marker": "x"])
        let group = DispatchGroup()
        for _ in 0..<32 {
            group.enter()
            DispatchQueue.global().async {
                CountlyConnectionManager.sharedInstance().proceedOnQueue()
                group.leave()
            }
        }
        group.wait()

        TestUtils.sleep(2) {
            lock.lock()
            let hits = markerHits
            lock.unlock()
            XCTAssertEqual(1, hits,
                           "The marker request must be sent exactly once even with 32 concurrent proceedOnQueue calls; got \(hits)")
        }
    }
}
