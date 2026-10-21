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

    // MARK: - Replaced, not merged, settings

    /// Drives the SDK's server-config fetch through a mocked URL session so
    /// that `replaceBehaviorSettings` runs with a controlled response payload.
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

    /// Like `mockURLSessionConfig(returning:)`, but the settings request is
    /// answered only once the returned semaphore is signalled, so the test can
    /// check the state the stored settings set at start first.
    private func heldMockURLSessionConfig(returning configDict: [String: Any]) -> (URLSessionConfiguration, DispatchSemaphore) {
        let release = DispatchSemaphore(value: 0)
        let response = makeServerConfig(configDict)
        let data = try! JSONSerialization.data(withJSONObject: response)
        MockURLProtocol.requestHandler = { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("method=sc") {
                _ = release.wait(timeout: .now() + 5)
                return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil), nil)
            }
            return ("{\"result\":\"fail\"}".data(using: .utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil), nil)
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return (config, release)
    }

    /// Answers the settings request with the given body, status code or
    /// network error as they are, so a test can send an answer the SDK must
    /// not accept. The returned closure tells how many settings requests were
    /// answered.
    private func rawMockURLSessionConfig(body: [String: Any]?, statusCode: Int = 200, error: Error? = nil) -> (URLSessionConfiguration, () -> Int) {
        let lock = NSLock()
        var answeredCount = 0
        let data = body.map { try! JSONSerialization.data(withJSONObject: $0) }
        MockURLProtocol.requestHandler = { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("method=sc") {
                lock.lock()
                answeredCount += 1
                lock.unlock()
                if let error = error {
                    return (nil, nil, error)
                }
                return (data, HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil), nil)
            }
            return ("{\"result\":\"fail\"}".data(using: .utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil), nil)
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return (config, {
            lock.lock()
            defer { lock.unlock() }
            return answeredCount
        })
    }

    /// Starts the SDK with stored settings that turn tracking off and set the
    /// event queue size to 3, lets the given settings answer arrive, and checks
    /// that the stored settings and the values they set are unchanged.
    private func assertStoredSettingsKept(after answer: (URLSessionConfiguration, () -> Int), file: StaticString = #filePath, line: UInt = #line) {
        setStoredServerConfig(makeServerConfig([
            "tracking": false,
            "eqs": 3
        ]))

        let cfg = TestUtils.createBaseConfig()
        cfg.manualSessionHandling = true
        cfg.eventSendThreshold = 7
        cfg.urlSessionConfiguration = answer.0

        let countly = createLocalCountly()
        countly.start(with: cfg)

        TestUtils.sleep(2) {
            XCTAssertGreaterThan(answer.1(), 0, "the settings request was answered", file: file, line: line)
            XCTAssertFalse(CountlyServerConfig.sharedInstance().trackingEnabled(), "the stored tracking setting still applies", file: file, line: line)
            XCTAssertEqual(3, CountlyPersistency.sharedInstance().eventSendThreshold, "the stored event queue size still applies", file: file, line: line)
            let persisted = self.storedConfigDictionary()
            XCTAssertEqual(2, persisted.count, "the stored settings are not replaced", file: file, line: line)
            XCTAssertEqual(persisted["tracking"] as? Bool, false, file: file, line: line)
            XCTAssertEqual(persisted["eqs"] as? Int, 3, file: file, line: line)
        }
    }

    /// The next answer replaces the stored settings as a whole: a filter the
    /// server no longer sends is removed, also from a category the answer does
    /// not mention, and the user property filter is turned off.
    func test_nextAnswer_replacesTheStoredSettings() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        // Seed persisted config with both an event blacklist and a user
        // property blacklist already present.
        setStoredServerConfig(makeServerConfig([
            "eb": ["blocked_event"],
            "upb": ["blocked_prop"]
        ]))

        // Mock a server response that only carries an event whitelist (`ew`).
        let cfg = TestUtils.createBaseConfig()
        cfg.manualSessionHandling = true
        cfg.urlSessionConfiguration = mockURLSessionConfig(returning: [
            "ew": ["allowed_event"]
        ])

        let countly = createLocalCountly()
        countly.start(with: cfg)

        TestUtils.sleep(2) {
            let persisted = self.storedConfigDictionary()
            XCTAssertEqual(["ew"], Array(persisted.keys), "only the keys of the last answer are stored")
            XCTAssertEqual(persisted["ew"] as? [String], ["allowed_event"])
            XCTAssertTrue(CountlyServerConfig.sharedInstance().shouldRecordUserProperty("blocked_prop"),
                          "the user property blacklist the server stopped sending is turned off")
        }
    }

    /// The answer replaces the stored settings in every category: the stored
    /// segmentation whitelist and user property blacklist are gone, the new
    /// segmentation blacklist and user property whitelist are kept.
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
            XCTAssertNil(persisted["sw"], "sw is removed because the answer does not carry it")
            XCTAssertEqual(persisted["sb"] as? [String], ["s_blocked"])
            XCTAssertNil(persisted["upb"], "upb is removed because the answer does not carry it")
            XCTAssertEqual(persisted["upw"] as? [String], ["u_allowed"])
        }
    }

    /// A setting the server stops sending goes back to the developer's value,
    /// or to the SDK default when the developer set none, instead of keeping
    /// the last server value.
    func test_removedSetting_goesBackToTheDeveloperValue() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        setStoredServerConfig(makeServerConfig([
            "tracking": false,
            "eqs": 3
        ]))

        let cfg = TestUtils.createBaseConfig()
        cfg.manualSessionHandling = true
        cfg.eventSendThreshold = 7
        let (sessionConfig, release) = heldMockURLSessionConfig(returning: [
            "networking": true
        ])
        cfg.urlSessionConfiguration = sessionConfig

        let countly = createLocalCountly()
        countly.start(with: cfg)
        XCTAssertEqual(3, CountlyPersistency.sharedInstance().eventSendThreshold, "the stored settings apply at start")
        XCTAssertFalse(CountlyServerConfig.sharedInstance().trackingEnabled())
        release.signal()

        TestUtils.sleep(2) {
            XCTAssertTrue(CountlyServerConfig.sharedInstance().trackingEnabled(), "tracking was removed and goes back to the default")
            XCTAssertEqual(7, CountlyPersistency.sharedInstance().eventSendThreshold, "the event queue size was removed and goes back to the developer's value")
            XCTAssertEqual(["networking"], Array(self.storedConfigDictionary().keys))
        }
    }

    /// An answer with no settings, which the server sends once every setting
    /// is removed from SDK Manager, brings back all developer values,
    /// including the developer's consent requirement.
    func test_emptySettings_bringBackAllDeveloperValues() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        setStoredServerConfig(makeServerConfig([
            "tracking": false,
            "rqs": 50,
            "cr": true
        ]))

        let cfg = TestUtils.createBaseConfig()
        cfg.manualSessionHandling = true
        cfg.requiresConsent = false
        cfg.storedRequestsLimit = 500
        let (sessionConfig, release) = heldMockURLSessionConfig(returning: [:])
        cfg.urlSessionConfiguration = sessionConfig

        let countly = createLocalCountly()
        countly.start(with: cfg)
        XCTAssertTrue(CountlyConsentManager.sharedInstance().requiresConsent, "the stored settings require consent at start")
        XCTAssertEqual(50, CountlyPersistency.sharedInstance().storedRequestsLimit)
        release.signal()

        TestUtils.sleep(2) {
            XCTAssertTrue(CountlyServerConfig.sharedInstance().trackingEnabled())
            XCTAssertEqual(500, CountlyPersistency.sharedInstance().storedRequestsLimit)
            XCTAssertFalse(CountlyConsentManager.sharedInstance().requiresConsent, "without 'cr' the developer's choice applies again")
            XCTAssertEqual(0, self.storedConfigDictionary().count)
        }
    }

    /// An answer with an error status is not applied, even when its body
    /// carries settings.
    func test_answerWithAnErrorStatus_keepsTheStoredSettings() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        assertStoredSettingsKept(after: rawMockURLSessionConfig(body: makeServerConfig([
            "tracking": true,
            "eqs": 50
        ]), statusCode: 500))
    }

    /// A settings request that fails without an answer keeps the stored settings.
    func test_failedSettingsRequest_keepsTheStoredSettings() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        assertStoredSettingsKept(after: rawMockURLSessionConfig(body: nil, error: URLError(.notConnectedToInternet)))
    }

    /// An answer whose 'c' is not an object is not valid and keeps the stored settings.
    func test_answerWhoseSettingsAreNotAnObject_keepsTheStoredSettings() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        assertStoredSettingsKept(after: rawMockURLSessionConfig(body: [
            "v": 1,
            "t": Int(Date().timeIntervalSince1970),
            "c": ["tracking"]
        ]))
    }

    /// An answer without a version is not valid and keeps the stored settings.
    func test_answerWithoutAVersion_keepsTheStoredSettings() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        assertStoredSettingsKept(after: rawMockURLSessionConfig(body: [
            "t": Int(Date().timeIntervalSince1970),
            "c": ["tracking": true, "eqs": 50] as [String: Any]
        ]))
    }

    /// An answer whose version is null is not valid and keeps the stored settings, instead of crashing
    /// every start while the server keeps sending it.
    func test_answerWithANullVersion_keepsTheStoredSettings() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        assertStoredSettingsKept(after: rawMockURLSessionConfig(body: [
            "v": NSNull(),
            "t": Int(Date().timeIntervalSince1970),
            "c": ["tracking": true, "eqs": 50] as [String: Any]
        ]))
    }

    /// An answer whose timestamp is null is not valid either.
    func test_answerWithANullTimestamp_keepsTheStoredSettings() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        assertStoredSettingsKept(after: rawMockURLSessionConfig(body: [
            "v": 1,
            "t": NSNull(),
            "c": ["tracking": true, "eqs": 50] as [String: Any]
        ]))
    }

    /// Nulls inside a list or a dictionary of an answer are left out of what is stored, which the
    /// standard user defaults could not store, and the rest of the setting applies.
    func test_nullsInsideAnAnswersSettings_areLeftOut() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        let cfg = TestUtils.createBaseConfig()
        cfg.manualSessionHandling = true
        cfg.urlSessionConfiguration = rawMockURLSessionConfig(body: makeServerConfig([
            "eb": ["blocked_event", NSNull()],
            "esb": ["checkout": ["card", NSNull()]]
        ])).0
        createLocalCountly().start(with: cfg)

        TestUtils.sleep(2) {
            let stored = self.storedConfigDictionary()
            XCTAssertEqual(["blocked_event"], stored["eb"] as? [String], "the null is left out of the stored list")
            XCTAssertEqual(["checkout": ["card"]], stored["esb"] as? [String: [String]],
                           "and out of a list inside a dictionary")
            XCTAssertFalse(CountlyServerConfig.sharedInstance().shouldRecordEvent("blocked_event"),
                           "the rest of the setting applies")
        }
    }

    /// The developer's disableBackoffMechanism holds for the whole run: neither the start without stored settings, nor
    /// an answer without 'bom', nor one with 'bom' true turns the backoff back on.
    func test_disableBackoffMechanism_holdsForEveryAnswer() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        let cfg = TestUtils.createBaseConfig()
        cfg.manualSessionHandling = true
        cfg.disableBackoffMechanism = true
        let (sessionConfig, release) = heldMockURLSessionConfig(returning: [
            "bom": true
        ])
        cfg.urlSessionConfiguration = sessionConfig
        createLocalCountly().start(with: cfg)
        XCTAssertFalse(CountlyServerConfig.sharedInstance().backoffMechanism(), "the backoff is off from start")

        release.signal()
        TestUtils.sleep(2) {
            XCTAssertTrue(self.storedConfigDictionary()["bom"] as? Bool == true,
                          "the answer turning the backoff on is applied")
            XCTAssertFalse(CountlyServerConfig.sharedInstance().backoffMechanism(), "and the backoff stays off")
        }
    }

    /// Built in settings are checked like an answer, so a null in them can not crash every start either.
    func test_builtInSettingsWithANullVersion_areIgnored() {
        let cfg = TestUtils.createBaseConfig()
        cfg.manualSessionHandling = true
        cfg.disableSDKBehaviorSettingsUpdates = true
        cfg.sdkBehaviorSettings = "{\"v\":null,\"t\":1,\"c\":{\"tracking\":false}}"
        createLocalCountly().start(with: cfg)
        XCTAssertTrue(CountlyServerConfig.sharedInstance().trackingEnabled(),
                      "settings without a usable version are not applied")
        XCTAssertTrue(storedConfigDictionary().isEmpty, "and nothing is stored")
    }

    /// Only the values in an acceptable format replace the stored settings: a
    /// setting sent with a wrong type, below its minimum or out of its range
    /// is left out, so it goes back to the developer's value or the SDK default.
    func test_valuesInAnUnacceptableFormat_areLeftOutOfTheReplacement() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        setStoredServerConfig(makeServerConfig([
            "tracking": false,
            "eqs": 3,
            "eb": ["blocked_event"]
        ]))

        let cfg = TestUtils.createBaseConfig()
        cfg.manualSessionHandling = true
        cfg.eventSendThreshold = 7
        let (sessionConfig, answered) = rawMockURLSessionConfig(body: makeServerConfig([
            "cet": false,
            "tracking": "no",
            "eqs": "3",
            "rqs": 0,
            "bom_rqp": 2.0,
            "eb": "blocked_event"
        ]))
        cfg.urlSessionConfiguration = sessionConfig

        let countly = createLocalCountly()
        countly.start(with: cfg)

        TestUtils.sleep(2) {
            XCTAssertGreaterThan(answered(), 0, "the settings request was answered")
            XCTAssertEqual(["cet"], Array(self.storedConfigDictionary().keys), "only the value in an acceptable format is stored")
            XCTAssertFalse(CountlyServerConfig.sharedInstance().customEventTrackingEnabled(), "the value in an acceptable format is applied")
            XCTAssertTrue(CountlyServerConfig.sharedInstance().trackingEnabled(), "a tracking value that is not a boolean is left out, the SDK default applies")
            XCTAssertEqual(7, CountlyPersistency.sharedInstance().eventSendThreshold, "an event queue size that is not a number is left out, the developer's value applies")
            XCTAssertTrue(CountlyServerConfig.sharedInstance().shouldRecordEvent("blocked_event"), "an event blacklist that is not a list is left out, the stored one is gone")
        }
    }

    /// The server can not lift a consent requirement the developer set, neither from the stored settings
    /// nor from a live answer, while a 'cr' true it sends turns the requirement on for a developer who
    /// did not set it.
    func test_serverCanOnlyTurnTheConsentRequirementOn() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        setStoredServerConfig(makeServerConfig([
            "cr": false
        ]))

        let cfg = TestUtils.createBaseConfig()
        cfg.manualSessionHandling = true
        cfg.requiresConsent = true
        let (sessionConfig, release) = heldMockURLSessionConfig(returning: [
            "cr": false
        ])
        cfg.urlSessionConfiguration = sessionConfig

        let countly = createLocalCountly()
        countly.start(with: cfg)
        XCTAssertTrue(CountlyConsentManager.sharedInstance().requiresConsent,
                      "a stored 'cr' false does not lift the developer's requirement")
        release.signal()

        TestUtils.sleep(2) {
            XCTAssertTrue(CountlyConsentManager.sharedInstance().requiresConsent, "and neither does a live one")
        }

        countly.halt(true)
        setStoredServerConfig(makeServerConfig([
            "cr": true
        ]))
        let next = TestUtils.createBaseConfig()
        next.manualSessionHandling = true
        next.requiresConsent = false
        next.disableSDKBehaviorSettingsUpdates = true
        createLocalCountly().start(with: next)
        XCTAssertTrue(CountlyConsentManager.sharedInstance().requiresConsent,
                      "a 'cr' true requires consent the developer did not require")
    }

    /// A setting the server sends wins over the developer's value also when
    /// it is false or 0: logging the developer turned on goes off, and a
    /// request drop age the developer set is turned off.
    func test_settingSentAsOffOrZero_winsOverTheDeveloperValue() {
        setStoredServerConfig(makeServerConfig([
            "log": false,
            "dort": 0
        ]))

        let cfg = TestUtils.createBaseConfig()
        cfg.manualSessionHandling = true
        cfg.enableDebug = true
        cfg.requestDropAgeHours = 48
        let countly = createLocalCountly()
        countly.start(with: cfg)

        XCTAssertFalse(CountlyCommon.sharedInstance().enableDebug, "the server's log=false turns the developer's logging off")
        XCTAssertEqual(0, CountlyPersistency.sharedInstance().requestDropAgeHours, "the server's dort=0 turns the developer's drop age off")
    }

    // MARK: - Consent during init

    /// When server config requires consent and the user config does not,
    /// consent must be sent exactly once during init (not twice).
    func test_consent_sentOnceDuringInit_whenServerConfigEnablesConsent() {
        setStoredServerConfig(makeServerConfig([
            "cr": true
        ]))

        let cfg = TestUtils.createBaseConfig()
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

    /// With pinned certificates the immediate session checks them like the request queue, without pins it keeps the system trust.
    func test_immediateURLSession_checksPinnedCertificatesLikeTheRequestQueue() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        // answered in process, so no TLS challenge ever looks up the pinned certificate file, which does not exist
        MockURLProtocol.replyEmptyToEveryRequest()

        let cfg = TestUtils.createBaseConfig()
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        cfg.urlSessionConfiguration = sessionConfig
        cfg.manualSessionHandling = true
        cfg.pinnedCertificates = ["pinned.cer"]
        Countly.sharedInstance().start(with: cfg)

        let connectionManager = try XCTUnwrap(CountlyConnectionManager.sharedInstance())
        let pinnedSession = CountlyCommon.sharedInstance().immediateURLSession()
        XCTAssertTrue(pinnedSession.delegate === connectionManager,
                      "with pinned certificates the connection manager must answer the trust challenge")
        XCTAssertEqual(60.0, pinnedSession.configuration.timeoutIntervalForRequest, accuracy: 0.001,
                       "pinning must not change the immediate session timeout")
        XCTAssertTrue(CountlyCommon.sharedInstance().immediateURLSession() === pinnedSession,
                      "a session with a delegate lives until it is invalidated, so every immediate request shares one")

        connectionManager.pinnedCertificates = nil
        XCTAssertNil(CountlyCommon.sharedInstance().immediateURLSession().delegate,
                     "without pinned certificates the system trust evaluation applies")
    }

    /**
     * <pre>
     * With pinned certificates the immediate session is kept between requests, so it has to be rebuilt when the
     * custom headers change, or a header added after start would never reach an immediate request.
     *
     * 1- Start with pinned certificates and a header given at start, which builds the kept session
     * 2- Add a header after start and download remote config, an immediate request
     * 3- Verify the request carried both headers and the new session still answers the trust challenge
     * </pre>
     */
    func test_immediateURLSession_pinnedSessionCarriesHeadersAddedAfterStart() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        // answered in process, so no TLS challenge ever looks up the pinned certificate file, which does not exist
        TestURLProtocol.reset()
        let cfg = TestUtils.createBaseConfig()
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [TestURLProtocol.self]
        sessionConfig.httpAdditionalHeaders = ["X-At-Start": "start_value"]
        cfg.urlSessionConfiguration = sessionConfig
        cfg.manualSessionHandling = true
        cfg.pinnedCertificates = ["pinned.cer"]
        Countly.sharedInstance().start(with: cfg)

        let connectionManager = try XCTUnwrap(CountlyConnectionManager.sharedInstance())
        let sessionBeforeHeaders = CountlyCommon.sharedInstance().immediateURLSession()
        Countly.sharedInstance().addCustomNetworkRequestHeaders(["Authorization": "Bearer 123"])

        let downloaded = XCTestExpectation(description: "the remote config download")
        Countly.sharedInstance().remoteConfig().downloadKeys { _, _, _, _ in downloaded.fulfill() }
        wait(for: [downloaded], timeout: TestUtils.asyncTimeout)

        let headers = try XCTUnwrap(TestURLProtocol.capturedHeaders(forRequestContaining: "method=rc"), "the download must be intercepted")
        XCTAssertEqual("Bearer 123", headers["Authorization"], "a header added after start must reach an immediate request")
        XCTAssertEqual("start_value", headers["X-At-Start"], "the header given at start must still be sent")

        let sessionAfterHeaders = CountlyCommon.sharedInstance().immediateURLSession()
        XCTAssertFalse(sessionAfterHeaders === sessionBeforeHeaders, "the session kept before the header change must not be reused")
        XCTAssertTrue(sessionAfterHeaders.delegate === connectionManager, "the rebuilt session must still answer the trust challenge")
        XCTAssertTrue(CountlyCommon.sharedInstance().immediateURLSession() === sessionAfterHeaders, "the rebuilt session is kept until the next change")
    }

    /// Starts with pinned certificates and an in-process mock, so the immediate session is the kept delegate session and
    /// no TLS challenge ever looks up the pinned certificate file, which does not exist. Logging is off, since formatting
    /// log lines would space out the calls a race needs to overlap.
    private func startWithPinnedCertificatesAndNoLogging() {
        MockURLProtocol.replyEmptyToEveryRequest()
        let cfg = TestUtils.createBaseConfig()
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        cfg.urlSessionConfiguration = sessionConfig
        cfg.manualSessionHandling = true
        cfg.pinnedCertificates = ["pinned.cer"]
        cfg.enableDebug = false
        Countly.sharedInstance().start(with: cfg)
        CountlyCommon.sharedInstance().decideLogGatheringOffIfUndecided("the test runs without logging")
    }

#if os(iOS)
    /**
     * <pre>
     * With pinned certificates a header change drops the kept immediate session, possibly while a request is being built
     * for it. A task created on a dropped session raises and ends the app, so the session is taken once the request is
     * built.
     *
     * 1- Start with pinned certificates and hold the feedback widget list fetch while it builds its request
     * 2- Change a header meanwhile, which drops the kept session, then let the fetch go on
     * 3- Verify the fetch completes
     * </pre>
     */
    func test_immediateURLSession_headerChangeWhileARequestIsBuiltDoesNotCrash() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        startWithPinnedCertificatesAndNoLogging()
        _ = CountlyCommon.sharedInstance().immediateURLSession()

        let builder = try XCTUnwrap(class_getInstanceMethod(CountlyFeedbacksInternal.self, NSSelectorFromString("feedbacksRequest")))
        typealias BuildRequest = @convention(c) (AnyObject, Selector) -> AnyObject
        let originalIMP = method_getImplementation(builder)
        let buildRequest = unsafeBitCast(originalIMP, to: BuildRequest.self)
        let building = DispatchSemaphore(value: 0)
        let resume = DispatchSemaphore(value: 0)
        let heldBuild: @convention(block) (AnyObject) -> AnyObject = { feedbacks in
            building.signal()
            _ = resume.wait(timeout: .now() + 10)
            return buildRequest(feedbacks, NSSelectorFromString("feedbacksRequest"))
        }
        method_setImplementation(builder, imp_implementationWithBlock(heldBuild))
        defer { method_setImplementation(builder, originalIMP) }

        let fetched = XCTestExpectation(description: "the feedback widget list fetch")
        DispatchQueue.global().async {
            Countly.sharedInstance().feedback().getAvailableFeedbackWidgets { _, _ in fetched.fulfill() }
        }
        XCTAssertEqual(.success, building.wait(timeout: .now() + 5), "the fetch is building its request")
        Countly.sharedInstance().addCustomNetworkRequestHeaders(["Authorization": "Bearer 123"])
        // a session refuses new tasks once its queue has processed the invalidation, not as soon as it is asked
        TestUtils.sleep(0.5) {}
        resume.signal()

        wait(for: [fetched], timeout: TestUtils.asyncTimeout)
    }
#endif

    /**
     * <pre>
     * With pinned certificates a header change that lands while the kept immediate session is being created is not lost:
     * the session kept afterwards carries the new header.
     *
     * 1- Start with pinned certificates
     * 2- In each round drop the kept session, then create it on one thread while another changes a header
     * 3- Verify the session kept after each round carries that round's header
     * </pre>
     */
    func test_immediateURLSession_headerChangeRacingTheSessionCreationIsKept() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        startWithPinnedCertificatesAndNoLogging()

        var staleRounds: [Int] = []
        for round in 0..<1000 {
            CountlyCommon.sharedInstance().invalidatePinnedImmediateURLSession()
            DispatchQueue.concurrentPerform(iterations: 2) { worker in
                if worker == 0 {
                    _ = CountlyCommon.sharedInstance().immediateURLSession()
                } else {
                    Countly.sharedInstance().addCustomNetworkRequestHeaders(["X-Round": "\(round)"])
                }
            }
            let keptHeader = CountlyCommon.sharedInstance().immediateURLSession().configuration.httpAdditionalHeaders?["X-Round"] as? String
            if keptHeader != "\(round)" {
                staleRounds.append(round)
            }
        }

        XCTAssertEqual([], staleRounds, "the kept session must carry the header of its round")
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
    func test_proceedOnQueue_doesNotDoubleSendHeadRequest() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
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
