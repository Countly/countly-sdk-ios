import XCTest
@testable import Countly

class CountlyServerConfigTests: CountlyBaseTestCase {
    
    class CountTracker {
        var counts: [Int] = [0, 0, 0, 0, 0]
    }

    override func setUp() async throws {
        TestUtils.cleanup()
    }
    // MARK: - Basic Configuration Tests
    
    /**
     * Test default configuration when server config is disabled and storage is empty
     */
    func test_defaultConfig_whenServerConfigDisabledAndStorageEmpty() {
        let config = TestUtils.createBaseConfig()
        
        Countly.sharedInstance().start(with: config)
        
        let serverConfig = retrieveServerConfig()
        
        XCTAssertTrue(serverConfig.isEmpty)
        assertDefaultConfigValues(Countly.sharedInstance());
    }
    
    /**
     * Test default configuration when server config is enabled and storage is empty
     */
    func test_defaultConfig_whenServerConfigEnabledAndStorageEmpty() {
        let config = TestUtils.createBaseConfig()
        config.enableServerConfiguration = true
        let countly = Countly()
        countly.start(with: config)
        
        XCTAssertNotNil(retrieveServerConfig())
        assertDefaultConfigValues(countly)
    }
    
    // MARK: - Server Configuration Tests
    
    /**
     * Test configuration when server config is enabled and all properties are allowing
     */
    func test_serverConfig_whenEnabledAndAllPropertiesAllowing() throws {
        setServerConfig(createStorageConfig(tracking: true, networking: true, crashes: true))
        let config = TestUtils.createBaseConfig()
        config.enableServerConfiguration = true;
        let countly = Countly()
        countly.start(with: config)
        
        XCTAssertNotNil(CountlyPersistency.sharedInstance().retrieveServerConfig())
        assertDefaultConfigValues(countly)
    }
    
    /**
     * Test configuration when server config is enabled and all properties are forbidding
     */
    func test_serverConfig_whenEnabledAndAllPropertiesForbidding() {
        setServerConfig(createStorageConfig(tracking: false, networking: false, crashes: false))
        let config = TestUtils.createBaseConfig()
        config.enableServerConfiguration = true
        config.enableDebug = false
        
        Countly.sharedInstance().start(with: config)
        
        TestUtils.sleep(2, {
            XCTAssertFalse(retrieveServerConfig().isEmpty)
            XCTAssertFalse(CountlyServerConfig.sharedInstance().networkingEnabled())
            XCTAssertFalse(CountlyServerConfig.sharedInstance().trackingEnabled())
            XCTAssertFalse(CountlyServerConfig.sharedInstance().crashReportingEnabled())
        })
    }
    
    /**
     * Test configuration when server config is disabled and all properties are allowing
     */
    func test_serverConfig_whenDisabledAndAllPropertiesAllowing() throws {
        
        setServerConfig(createStorageConfig(tracking: true, networking: true, crashes: true))
        let config = TestUtils.createBaseConfig()
        let countly = Countly()
        countly.start(with: config)
        
        XCTAssertNotNil(CountlyPersistency.sharedInstance().retrieveServerConfig())
        assertDefaultConfigValues(countly)
    }
    
    // MARK: - Server Configuration Validation Tests
    
    /**
     * Tests that default server configuration values are correctly applied when no custom configuration is provided.
     * Verifies that all default values match the expected configuration.
     */
    func test_serverConfig_defaultValues() throws {
        
        let config = TestUtils.createBaseConfig()
        config.enableDebug = false
        Countly.sharedInstance().start(with: config)
        TestUtils.sleep(2, {ServerConfigBuilder().defaults().validateAgainst()})
    }
    
    /**
     * Tests that custom server configuration values are correctly applied when provided directly.
     * Verifies that the configuration is properly parsed and applied to the SDK.
     */
    func test_serverConfig_providedValues() throws {
        
        try initServerConfigWithValues { config, serverConfig in
            config.sdkBehaviorSettings = serverConfig
        }
    }
    
    /**
     * Tests that server configuration values are correctly applied when using an immediate request generator.
     * Verifies that the configuration is properly handled when received through the request generator.
     */
    func test_serverConfig_withImmediateRequestGenerator() throws {
        
        try initServerConfigWithValues { config, serverConfig in
            config.urlSessionConfiguration = createUrlSessionConfigForResponse(serverConfig)
        }
    }
    
    /**
     * Tests that all features work correctly with default server configuration.
     * Verifies that all SDK features (sessions, events, views, crashes, etc.) function as expected
     * when using default configuration values.
     */
    func test_serverConfig_defaults_allFeatures() throws {
        
        try baseAllFeatures({ _ in }, hc: 0, fc: 1, rc: 1, cc: 2, scc: 1)
    }
    
    /**
     * Tests that all features are properly disabled when explicitly configured to be disabled.
     * Verifies that no requests are generated and no data is collected when all features are disabled.
     */
    func test_disable_allFeatures() {
        
        let sc = ServerConfigBuilder()
        sc.networking(false)
            .sessionTracking(false)
            .customEventTracking(false)
            .viewTracking(false)
            .crashReporting(false)
            .locationTracking(false)
            .contentZone(false)
            .refreshContentZone(false)
            .tracking(false)
            .consentRequired(true)
        
        let tracker = setupTestAllFeatures(sc.buildJson())
        
        XCTAssertEqual(0, TestUtils.getCurrentRQ()?.count)
        XCTAssertEqual(0, TestUtils.getCurrentEQ()?.count)
        
        flowAllFeatures()
        XCTAssertEqual(0, TestUtils.getCurrentRQ()?.count)
        
        immediateFlowAllFeatures()
        XCTAssertEqual(0, TestUtils.getCurrentEQ()?.count)

        feedbackFlowAllFeatures()
        XCTAssertEqual(0, TestUtils.getCurrentRQ()?.count)
        XCTAssertEqual(0, TestUtils.getCurrentEQ()?.count)
        
        validateCounts(tracker.counts, hc: 0, fc: 0, rc: 0, cc: 0, sc: 1)
    }
    
    /**
     * Tests that consent requirement is properly handled when enabled.
     * Verifies that:
     * 1. Initial consent request is sent
     * 2. No data is collected until consent is given
     * 3. Location is properly handled with empty value
     */
    func test_consentEnabled_allFeatures() {
        let sc = ServerConfigBuilder()
        sc.consentRequired(true)
        
        let tracker = setupTestAllFeatures(sc.buildJson())
        
        XCTAssertEqual(0, TestUtils.getCurrentRQ()?.count)
        XCTAssertEqual(0, TestUtils.getCurrentEQ()?.count)
        
        flowAllFeatures()
        immediateFlowAllFeatures()
        XCTAssertEqual(0, TestUtils.getCurrentEQ()?.count)
        feedbackFlowAllFeatures()
        
        XCTAssertEqual(2, TestUtils.getCurrentRQ()?.count)
        XCTAssertEqual(0, TestUtils.getCurrentEQ()?.count)
        let consents: [String: Any?] = [
            "push": 0,
            "content": 0,
            "crashes": 0,
            "events": 0,
            "users": 0,
            "feedback": 0,
            "apm": 0,
            "location": 0,
            "remote-config": 0,
            "sessions": 0,
            "attribution": 0,
            "views": 0
        ]
        TestUtils.validateRequest(["consent": consents], 0)
        TestUtils.validateRequest(["begin_session": "1"], 1)

        validateCounts(tracker.counts, hc: 0, fc: 0, rc: 0, cc: 0, sc: 1)
    }
    
    /**
     * Tests that session tracking is properly disabled when configured.
     * Verifies that:
     * 1. No session requests are generated
     * 2. Other features (events, views, crashes) continue to work
     * 3. Request counts and order are maintained correctly
     */
    func test_sessionsDisabled_allFeatures() throws {
        let sc = ServerConfigBuilder()
        sc.sessionTracking(false)
        let tracker = setupTestAllFeatures(sc.buildJson())
        
        XCTAssertEqual(0, TestUtils.getCurrentRQ()?.count)
        XCTAssertEqual(0, TestUtils.getCurrentEQ()?.count)
        
        let stackTrace = flowAllFeatures()
        
        //ModuleCrashTests.validateCrash(stackTrace, "", false, false, 7, 0, [:], 0, [:], [])
        try TestUtils.validateEventInRQ("test_event", [:], 1, 7, 0, 2)
        try TestUtils.validateEventInRQ("[CLY]_view", ["name": "test_view", "segment": "iOS", "visit": "1"], 1, 7, 1, 2)
        TestUtils.validateRequest([:], 2, { request in
            let userDetails = request["user_details"] as! [String: Any]
            XCTAssertTrue(TestUtils.compareDictionaries(userDetails["custom"] as! [String: Any], ["test_property": "test_value"]))
        })
        TestUtils.validateRequest(["location": "33.689500,139.691700"], 3)
        TestUtils.validateRequest([:], 4, { request in
            let apm = request["apm"] as! [String: Any]
            XCTAssertEqual("test_trace", apm["name"] as! String)
            XCTAssertEqual("network", apm["type"] as! String)
            XCTAssertTrue(TestUtils.compareDictionaries(apm["apm_metrics"] as! [String: Any],
                                                        ["response_time": 1111,
                                                         "response_code": 400,
                                                         "request_payload_size": 2000,
                                                         "response_payload_size": 2000]))
        })
        TestUtils.validateRequest(["attribution_data": "test_data"], 5)
        TestUtils.validateRequest(["key": "value"], 6)
        
        XCTAssertEqual(7, TestUtils.getCurrentRQ()?.count)
        immediateFlowAllFeatures()
        
        XCTAssertEqual(0, TestUtils.getCurrentEQ()?.count)
        feedbackFlowAllFeatures()
        XCTAssertEqual(0, TestUtils.getCurrentEQ()?.count)

        try TestUtils.validateEventInRQ("[CLY]_star_rating", [
            "platform": "iOS",
            "app_version": CountlyDeviceInfo.appVersion()!,
            "rating": "5",
            "widget_id": "test",
            "contactMe": "1",
            "email": "test",
            "comment": "test"
        ], 7, 8, 0, 2)
        
        try TestUtils.validateEventInRQ("[CLY]_nps", [
            "app_version": CountlyDeviceInfo.appVersion()!,
            "widget_id": "test",
            "closed": "1",
            "platform": "iOS"
        ], 7, 8, 1, 2)
        
        XCTAssertEqual(8, TestUtils.getCurrentRQ()?.count)

        validateCounts(tracker.counts, hc: 0, fc: 1, rc: 1, cc: 2, sc: 1)
    }
    
    // MARK: - Queue Size Tests
    
    /**
     * Tests that the event queue size limit is properly enforced.
     * Verifies that:
     * 1. Events are queued until the size limit is reached
     * 2. When limit is reached, events are sent in a batch
     * 3. New events are queued after the batch is sent
     * 4. Event order is maintained in the queue
     */
    func test_eventQueueSize() throws {
        let countlyConfig = TestUtils.createBaseConfig()
        countlyConfig.manualSessionHandling = true
        countlyConfig.urlSessionConfiguration = createUrlSessionConfigForResponse(ServerConfigBuilder().eventQueueSize(3).build())
        Countly.sharedInstance().start(with: countlyConfig)
        
        TestUtils.sleep(3){}
        
        XCTAssertEqual(0, TestUtils.getCurrentRQ()?.count)
        XCTAssertEqual(0, TestUtils.getCurrentRQ()?.count)
        
        Countly.sharedInstance().recordEvent("test_event")
        XCTAssertEqual(0, TestUtils.getCurrentRQ()?.count)
        XCTAssertEqual(1, TestUtils.getCurrentEQ()?.count)
        
        Countly.sharedInstance().recordEvent("test_event_1")
        XCTAssertEqual(0, TestUtils.getCurrentRQ()?.count)
        XCTAssertEqual(2, TestUtils.getCurrentEQ()?.count)
        
        Countly.sharedInstance().recordEvent("test_event_2")
        XCTAssertEqual(1, TestUtils.getCurrentRQ()?.count)
        XCTAssertEqual(0, TestUtils.getCurrentEQ()?.count)
        
        Countly.sharedInstance().recordEvent("test_event_3")
        XCTAssertEqual(1, TestUtils.getCurrentRQ()?.count)
        XCTAssertEqual(1, TestUtils.getCurrentEQ()?.count)
        
        try TestUtils.validateEventInRQ("test_event", [:], 0, 1, 0, 3)
        try TestUtils.validateEventInRQ("test_event_1", [:], 0, 1, 1, 3)
        try TestUtils.validateEventInRQ("test_event_2", [:], 0, 1, 2, 3)
    }
    
    /**
     * Tests that the request queue size limit is properly enforced.
     * Verifies that:
     * 1. Requests are queued until the size limit is reached
     * 2. When limit is reached, new requests are rejected
     * 3. Different types of requests (sessions, attribution, location) are counted towards the limit
     */
    func test_requestQueueSize() throws {
        
        let countlyConfig = TestUtils.createBaseConfig()
        countlyConfig.manualSessionHandling = true
        countlyConfig.urlSessionConfiguration = createUrlSessionConfigForResponse(ServerConfigBuilder().requestQueueSize(3).build())
        Countly.sharedInstance().start(with: countlyConfig)
        
        Countly.sharedInstance().beginSession()
        XCTAssertTrue(TestUtils.getCurrentRQ()![0].contains("begin_session"))
        
        Countly.sharedInstance().recordDirectAttribution(withCampaignType: "_special_test", andCampaignData: "_special_test")
        XCTAssertEqual(2, TestUtils.getCurrentRQ()?.count)
        
        Countly.sharedInstance().recordLocation(CLLocationCoordinate2D(latitude:33.6895, longitude:139.6917), city:"Tokyo", isoCountryCode:"JP", ip:"255.255.255.255");
        XCTAssertEqual(3, TestUtils.getCurrentRQ()?.count)
        
        let params = ["key": "value"]
        Countly.sharedInstance().addDirectRequest(params)
        

        XCTAssertFalse(TestUtils.getCurrentRQ()![0].contains("begin_session"))
    }
    
    func test_validateServerConfigParsing_invalid(){
        XCTAssertTrue(retrieveServerConfig().isEmpty)
        // Test various invalid configurations
        initAndValidateConfigParsingResult("", false)
        initAndValidateConfigParsingResult("{}", false)
        initAndValidateConfigParsingResult("{'t':2,'c':{'aa':'bb'}}", false)
        initAndValidateConfigParsingResult("{'v':1,'c':{'aa':'bb'}}", false)
        initAndValidateConfigParsingResult("{'v':1,'t':2}", false)
        initAndValidateConfigParsingResult("{'v':1,'t':2,'c':123}", false)
        initAndValidateConfigParsingResult("{'v':1,'t':2,'c':false}", false)
        initAndValidateConfigParsingResult("{'v':1,'t':2,'c':'fdf'}", false)
    }
    
    func test_serverConfig_missingOrInvalidKeys() {
        let invalidConfigs: [String] = [
            "{}",
            "{\"v\":1}", // Missing "t" and "c"
            "{\"v\":1,\"t\":2}", // Missing "c"
            "{\"v\":1,\"t\":2,\"c\":123}", // Invalid "c" type
            "{\"v\":1,\"t\":2,\"c\":false}", // Invalid "c" type
            "{\"v\":1,\"t\":2,\"c\":\"invalid\"}" // Invalid "c" type
        ]
        
        for config in invalidConfigs {
            let countly = initAndValidateConfigParsingResult(config, false)
            XCTAssertTrue(retrieveServerConfig().isEmpty)
            assertDefaultConfigValues(countly)
        }
    }
    
    func test_serverConfig_emptyConfig() {
        setServerConfig([:])
        let config = TestUtils.createBaseConfig()
        config.enableServerConfiguration = true
        let countly = Countly()
        countly.start(with: config)
        
        XCTAssertTrue(retrieveServerConfig().isEmpty)
        assertDefaultConfigValues(countly)
    }
    
    func test_serverConfig_overrideDefaultValues() {
        let customConfig = createStorageConfig(tracking: false, networking: false, crashes: false)
        setServerConfig(customConfig)
        
        let config = TestUtils.createBaseConfig()
        config.enableServerConfiguration = true
        let countly = Countly()
        countly.start(with: config)
        
        XCTAssertFalse(CountlyServerConfig.sharedInstance().trackingEnabled())
        XCTAssertFalse(CountlyServerConfig.sharedInstance().networkingEnabled())
        XCTAssertFalse(CountlyServerConfig.sharedInstance().crashReportingEnabled())
    }
    
    func test_serverConfig_consentRequirement() {
        let customConfig = ServerConfigBuilder()
            .consentRequired(true)
            .buildJson()
        setServerConfig(customConfig)
        
        let config = TestUtils.createBaseConfig()
        config.enableServerConfiguration = true
        let countly = Countly()
        countly.start(with: config)
        
        XCTAssertTrue(CountlyServerConfig.sharedInstance().consentRequired())
    }
    
    func test_serverConfig_loggingEnabled() {
        let customConfig = ServerConfigBuilder()
            .logging(true)
            .buildJson()
        setServerConfig(customConfig)
        
        let config = TestUtils.createBaseConfig()
        config.enableServerConfiguration = true
        let countly = Countly()
        countly.start(with: config)
        
        XCTAssertTrue(CountlyServerConfig.sharedInstance().loggingEnabled())
    }
    
    func test_serverConfig_queueSizeLimits() {
        let customConfig = ServerConfigBuilder()
            .eventQueueSize(5)
            .requestQueueSize(10)
            .buildJson()
        setServerConfig(customConfig)
        
        let config = TestUtils.createBaseConfig()
        config.enableServerConfiguration = true
        let countly = Countly()
        countly.start(with: config)
        
        XCTAssertEqual(CountlyServerConfig.sharedInstance().eventQueueSize(), 5)
        XCTAssertEqual(CountlyServerConfig.sharedInstance().requestQueueSize(), 10)
    }
    
    /**
         * Tests that event tracking is properly disabled when configured.
         * Verifies that:
         * 1. No event requests are generated
         * 2. Other features (sessions, views, crashes) continue to work
         * 3. Request counts and order are maintained correctly
         */
        func test_eventsDisabled_allFeatures() throws {
            let sc = ServerConfigBuilder()
                .customEventTracking(false)
            let tracker = setupTestAllFeatures(sc.buildJson())
            
            XCTAssertEqual(0, TestUtils.getCurrentRQ()?.count)
            XCTAssertEqual(0, TestUtils.getCurrentEQ()?.count)
            
            let stackTrace = flowAllFeatures()
            
            XCTAssertTrue(TestUtils.getCurrentRQ()![0].contains("begin_session"))
            // Events should not be tracked
            XCTAssertFalse(containsEventWithKey(TestUtils.getCurrentRQ()!, "test_event"))
            
            // But other features should work
            try TestUtils.validateEventInRQ("[CLY]_view", ["name": "test_view", "segment": "iOS", "visit": "1", "start": "1"], 2, 7, 0, 1)
            TestUtils.validateRequest([:], 3, { request in
                let userDetails = request["user_details"] as! [String: Any]
                XCTAssertTrue(TestUtils.compareDictionaries(userDetails["custom"] as! [String: Any], ["test_property": "test_value"]))
            })
            
            XCTAssertEqual(8, TestUtils.getCurrentRQ()?.count)
            XCTAssertFalse(containsEventWithKey(TestUtils.getCurrentRQ()!, "test_event"))
            XCTAssertTrue(TestUtils.getCurrentEQ()!.isEmpty)
            validateCounts(tracker.counts, hc: 0, fc: 1, rc: 1, cc: 2, sc: 1)
        }
    
    /**
         * Tests that crashes are properly disabled when configured.
         * Verifies that:
         * 1. No crash reports are sent
         * 2. Other features (sessions, events, views) continue to work
         */
        func test_crashesDisabled_allFeatures() throws {
            let sc = ServerConfigBuilder()
                .crashReporting(false)
            let tracker = setupTestAllFeatures(sc.buildJson())
            
            XCTAssertEqual(0, TestUtils.getCurrentRQ()?.count)
            
            let stackTrace = flowAllFeatures()
            
            // Verify that crash is not recorded
            for request in TestUtils.getCurrentRQ()! {
                XCTAssertFalse(request.contains("crash="))
            }
            
            // But other features should work
            XCTAssertTrue(TestUtils.getCurrentRQ()![0].contains("begin_session"))
            try TestUtils.validateEventInRQ("test_event", [:], 2, 7, 0, 2)
            
            validateCounts(tracker.counts, hc: 0, fc: 1, rc: 1, cc: 2, sc: 1)
        }
        
        /**
         * Tests the behavior when multiple features are disabled simultaneously.
         * Verifies correct handling when sessions, events, and views are all disabled.
         */
        func test_multipleDisabledFeatures_allFeatures() throws {
            let sc = ServerConfigBuilder()
                .sessionTracking(false)
                .customEventTracking(false)
                .viewTracking(false)
            let tracker = setupTestAllFeatures(sc.buildJson())
            
            XCTAssertEqual(0, TestUtils.getCurrentRQ()?.count)
            
            let stackTrace = flowAllFeatures()
            
            // Verify no sessions, events, or views are recorded
            for request in TestUtils.getCurrentRQ()! {
                XCTAssertFalse(request.contains("begin_session"))
                XCTAssertFalse(containsEventWithKey(TestUtils.getCurrentRQ()!, "test_event"))
                XCTAssertFalse(containsEventWithKey(TestUtils.getCurrentRQ()!, "[CLY]_view"))
            }
            
            XCTAssertEqual(6, TestUtils.getCurrentRQ()?.count)
            
            TestUtils.validateRequest([:], 0, { request in
                XCTAssertTrue(request.contains(where: { (key: String, value: Any) in
                    return key.elementsEqual("crash")
                }))
            })
            TestUtils.validateRequest([:], 1, { request in
                let userDetails = request["user_details"] as! [String: Any]
                XCTAssertTrue(TestUtils.compareDictionaries(userDetails["custom"] as! [String: Any], ["test_property": "test_value"]))
            })
            TestUtils.validateRequest(["location": "33.689500,139.691700"], 2)

            
            validateCounts(tracker.counts, hc: 0, fc: 1, rc: 1, cc: 2, sc: 1)
        }
        
    /**
     * Tests the behavior when server configuration changes between app launches.
     * Verifies that the SDK correctly applies the new configuration when starting.
     */
    func test_configChangesBetweenLaunches() {
        // First "launch" with default config
        let initialConfig = ServerConfigBuilder().buildJson()
        setServerConfig(initialConfig)
        
        let config1 = TestUtils.createBaseConfig()
        let countly1 = Countly()
        countly1.start(with: config1)
        
        // Record an event to verify it works
        Countly.sharedInstance().recordEvent("test_event_launch_1")
        
        TestUtils.sleep(2) {
            XCTAssertEqual(1, TestUtils.getCurrentEQ()?.count)
        }
        
        // Clean up for "second launch"
        TestUtils.cleanup()
        
        // Change config to disable events before "second launch"
        let updatedConfig = ServerConfigBuilder()
            .customEventTracking(false)
            .buildJson()
        setServerConfig(updatedConfig)
        
        // "Second launch"
        let config2 = TestUtils.createBaseConfig()
        let countly2 = Countly()
        countly2.start(with: config2)
        
        // Try to record an event
        Countly.sharedInstance().recordEvent("test_event_launch_2")
        
        TestUtils.sleep(2) {
            // Event shouldn't be recorded since custom events are disabled
            XCTAssertEqual(0, TestUtils.getCurrentEQ()?.count)
        }
    }
        
        /**
         * Tests the behavior when key length and value size limits are enforced.
         * Verifies that:
         * 1. Keys exceeding the length limit are truncated
         * 2. Values exceeding the size limit are truncated
         * 3. The number of segmentation values is limited as specified
         */
        func test_keyLengthAndValueSizeLimits() throws {
            let sc = ServerConfigBuilder()
                .limitKeyLength(5)  // Limit key length to 5 characters
                .limitValueSize(10) // Limit value size to 10 characters
                .limitSegmentationValues(2) // Limit segmentation values to 2
            let tracker = setupTestAllFeatures(sc.buildJson())
            
            // Record event with long key and values
            let longKey = "veryLongEventKey"
            let segmentation = [
                "key1": "value1",
                "key2": "value2",
                "key3": "value3VeryLong",
                "veryLongKey": "value4"
            ]
            
            Countly.sharedInstance().recordEvent(longKey, segmentation: segmentation)
            
            TestUtils.sleep(2) {
                let eq = TestUtils.getCurrentEQ()!
                let event = eq[0]

                // Verify key is truncated to 5 chars
                XCTAssertEqual(event.key, "veryL")
                
                // Verify only 2 segmentation values
                let segmentationCount = event.segmentation.count
                XCTAssertEqual(2, segmentationCount)
                
                // Verify value is truncated
                if let segmentation = event.segmentation,
                   let longValue = segmentation["key3"] as? String {
                    XCTAssertEqual(10, longValue.count)
                }
            }
            
            validateCounts(tracker.counts, hc: 0, fc: 0, rc: 0, cc: 0, sc: 1)
        }
    // MARK: - Helper Methods
    
    private func containsEventWithKey(_ requests: [String], _ key: String) -> Bool {
        return getEventWithKey(requests, key) != nil
    }
    
    private func getEventWithKey(_ requests: [String], _ key: String) -> [String: Any]? {
        for request in requests {
            if let data = request.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let events = json["events"] as? [[String: Any]] {
                for event in events {
                    if let eventKey = event["key"] as? String, eventKey == key {
                        return event
                    }
                }
            }
        }
        return nil
    }
    
    private func assertDefaultConfigValues(_ countly: Countly) {
        XCTAssertTrue(CountlyServerConfig.sharedInstance().networkingEnabled())
        XCTAssertTrue(CountlyServerConfig.sharedInstance().trackingEnabled())
        XCTAssertTrue(CountlyServerConfig.sharedInstance().crashReportingEnabled())
    }
    
    private func createStorageConfig(tracking: Bool, networking: Bool, crashes: Bool) -> [String : Any] {
        let builder = ServerConfigBuilder()
        builder.tracking(tracking)
        builder.networking(networking)
        builder.crashReporting(crashes)
        return builder.buildJson()
    }
    
    private func initAndValidateConfigParsingResult(_ targetResponse: String, _ responseAccepted: Bool) -> Countly {
        let config = TestUtils.createBaseConfig()
        config.enableServerConfiguration = true
        config.urlSessionConfiguration = createUrlSessionConfigForResponse(targetResponse)
        
        let countly = Countly()
        countly.start(with: config)
        
        TestUtils.sleep(2){
            let serverConfig = retrieveServerConfig()
            
            if !responseAccepted {
                XCTAssertTrue(serverConfig.isEmpty)
                assertDefaultConfigValues(countly)
            } else {
                XCTAssertFalse(serverConfig.isEmpty)
            }
        }
        
        return countly
    }
    
    private func createUrlSessionConfigForResponse(_ targetResponse: String) -> URLSessionConfiguration {
        
        MockURLProtocol.requestHandler = { request in
            let requestString = request.url?.absoluteString ?? ""
            var response = HTTPURLResponse(url: request.url!,
                                          statusCode: 200,
                                          httpVersion: nil,
                                          headerFields: nil)
            if(requestString.contains("method=sc")){
                return (targetResponse.data(using: .utf8), response , nil)
            }
            
            response = HTTPURLResponse(url: request.url!,
                                          statusCode: 400,
                                          httpVersion: nil,
                                          headerFields: nil)
            return ("{\"result\":\"fail\"}".data(using: .utf8), response , nil)
        }

        // Create a URLSession using the mock protocol
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        
        return config
    }
    
    private func initServerConfigWithValues(_ configSetter: (CountlyConfig, String) -> Void) throws {
        let builder = ServerConfigBuilder()
            // Feature flags
            .tracking(false)
            .networking(false)
            .crashReporting(false)
            .viewTracking(false)
            .sessionTracking(false)
            .customEventTracking(false)
            .contentZone(true)
            .locationTracking(false)
            .refreshContentZone(false)
            
            // Intervals and sizes
            .serverConfigUpdateInterval(8)
            .requestQueueSize(2000)
            .eventQueueSize(200)
            .logging(true)
            .sessionUpdateInterval(120)
            .contentZoneInterval(60)
            .consentRequired(true)
            .dropOldRequestTime(1)
            .limitKeyLength(89)
            .limitValueSize(43)
            .limitSegmentationValues(25)
            .limitBreadcrumb(90)
            .limitTraceLength(78)
            .limitTraceLines(89)
        
        let serverConfig = builder.build()
        let countlyConfig = TestUtils.createBaseConfig()
        configSetter(countlyConfig, serverConfig)
        
        let countly = Countly()
        countly.start(with: countlyConfig)
        
        TestUtils.sleep(2, {builder.validateAgainst()})
        
    }
    
    private func setupTestAllFeatures(_ serverConfig: [String: Any]) -> CountTracker {
        let tracker = CountTracker()
                
        // Define the mock behavior
        MockURLProtocol.requestHandler = { request in
            let requestString = request.url?.absoluteString ?? ""

            if requestString.contains("hc=") { // TODO IOS DOES NOT HAVE HC
                tracker.counts[0] += 1
            } else if requestString.contains("method=feedback") {
                tracker.counts[1] += 1
            } else if requestString.contains("method=rc") {
                tracker.counts[2] += 1
            } else if requestString.contains("method=queue") {
                tracker.counts[3] += 1
            } else if requestString.contains("method=sc") {
                // Do nothing
            }

            if requestString.contains("method=sc") {
                tracker.counts[4] += 1
                var configToReturn = Data()
                do{
                    configToReturn = try JSONSerialization.data(withJSONObject: serverConfig)
                } catch {
                    //ignored
                }
                return (configToReturn, HTTPURLResponse(url: request.url!,
                                                statusCode: 200,
                                                httpVersion: nil,
                                                headerFields: nil), nil)
            }

            return ("{\"result\":\"fail\"}".data(using: .utf8), HTTPURLResponse(url: request.url!,
                                            statusCode: 400,
                                            httpVersion: nil,
                                            headerFields: nil), nil)
        }

        // Create a URLSession using the mock protocol
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        
        let countlyConfig = TestUtils.createBaseConfig()
        countlyConfig.manualSessionHandling = true
        countlyConfig.urlSessionConfiguration = config;
        
        Countly.sharedInstance().start(with: countlyConfig)
        //Countly.sharedInstance().moduleContent.CONTENT_START_DELAY_MS = 0
        //Countly.sharedInstance().moduleContent.REFRESH_CONTENT_ZONE_DELAY_MS = 0
        
        return tracker
    }
    
    private func validateCounts(_ counts: [Int], hc: Int, fc: Int, rc: Int, cc: Int, sc: Int) {
        TestUtils.sleep(2) {
            XCTAssertEqual(hc, counts[0]) // health check request
            XCTAssertEqual(fc, counts[1]) // feedback request
            XCTAssertEqual(rc, counts[2]) // remote config request
            XCTAssertEqual(cc, counts[3]) // content request ?? when it debugged counts increasing but some sleep it needs
            XCTAssertEqual(sc, counts[4]) // server config request
        }
    }
    
    private func flowAllFeatures() -> String {
        Countly.sharedInstance().beginSession()
        Countly.sharedInstance().recordEvent("test_event")
        Countly.sharedInstance().views().startView("test_view")
        
        let e = NSException()
        Countly.sharedInstance().record(e)
        
        Countly.user().set("test_property", value: "test_value")
        Countly.user().save()
        
        Countly.sharedInstance().recordLocation(CLLocationCoordinate2D(latitude:33.6895, longitude:139.6917), city:"Tokyo", isoCountryCode:"JP", ip:"255.255.255.255");
        Countly.sharedInstance().recordNetworkTrace("test_trace", requestPayloadSize: 2000, responsePayloadSize: 2000, responseStatusCode: 400, startTime: 1111, endTime: 2222)
        Countly.sharedInstance().recordDirectAttribution(withCampaignType: "_special_test", andCampaignData:"test_data")
        
        let params = ["key": "value"]
        Countly.sharedInstance().addDirectRequest(params)
        
        return CountlyCrashReporterTests.extractStackTrace(e)!
    }
    
    private func immediateFlowAllFeatures() {
        Countly.sharedInstance().remoteConfig().downloadKeys { response, error, fullValueUpdate, downloadedValues in
         }
        Countly.sharedInstance().feedback().getAvailableFeedbackWidgets { (feedbackWidgets: [CountlyFeedbackWidget]?, error) in
            if (error != nil)
            {
              print("Getting widgets list failed. \n \(error!.localizedDescription) \n \((error! as NSError).userInfo)")
            }
            else
            {
              print("Getting widgets list successfully completed. \(String(describing: feedbackWidgets))")
            }
          }
        Countly.sharedInstance().content().enterContentZone()
        TestUtils.sleep(2) {
            Countly.sharedInstance().content().refreshContentZone()
        }
        
    }
    
    private func feedbackFlowAllFeatures() {
        Countly.sharedInstance().recordRatingWidget(withID: "test", rating: 5, email: "test", comment: "test", userCanBeContacted: true)
        let mockWidget = MockFeedbackWidget(
            id: "test",
            type: CLYFeedbackWidgetType.NPS
        )
        mockWidget.recordResult(nil)
    }
    
    private func baseAllFeatures(_ consumer: (ServerConfigBuilder) -> Void, hc: Int, fc: Int, rc: Int, cc: Int, scc: Int) throws {
        
        let sc = ServerConfigBuilder()
        consumer(sc)
        let tracker = setupTestAllFeatures(sc.buildJson())
        
        XCTAssertEqual(0, TestUtils.getCurrentRQ()?.count)
        XCTAssertEqual(0, TestUtils.getCurrentEQ()?.count)
        
        let stackTrace = flowAllFeatures()
        XCTAssertEqual(8, TestUtils.getCurrentRQ()?.count)

        XCTAssertTrue(TestUtils.getCurrentRQ()![0].contains("begin_session"))
        //ModuleCrashTests.validateCrash(stackTrace, "", false, false, 8, 1, [:], 0, [:], [])
        try TestUtils.validateEventInRQ("[CLY]_orientation", ["mode": "portrait"], 2, 8, 0, 3)
        try TestUtils.validateEventInRQ("test_event", [:], 2, 8, 0, 2)
        try TestUtils.validateEventInRQ("[CLY]_view", ["name": "test_view", "segment": "iOS", "visit": "1", "start": "1"], 2, 8, 1, 2)
        TestUtils.validateRequest([:], 3, { request in
            let userDetails = request["user_details"] as! [String: Any]
            XCTAssertTrue(TestUtils.compareDictionaries(userDetails["custom"] as! [String: Any], ["test_property": "test_value"]))
        })
        TestUtils.validateRequest(["location": "33.689500,139.691700"], 4)
        TestUtils.validateRequest([:], 5, { request in
            let apm = request["apm"] as! [String: Any]
            XCTAssertEqual("test_trace", apm["name"] as! String)
            XCTAssertEqual("network", apm["type"] as! String)
            XCTAssertTrue(TestUtils.compareDictionaries(apm["apm_metrics"] as! [String: Any],
                                                        ["response_time": 1111,
                                                         "response_code": 400,
                                                         "request_payload_size": 2000,
                                                         "response_payload_size": 2000]))
        })
        TestUtils.validateRequest(["attribution_data": "test_data"], 6)
        TestUtils.validateRequest(["key": "value"], 7)
        
        immediateFlowAllFeatures()
        XCTAssertEqual(0, TestUtils.getCurrentEQ()?.count)
        feedbackFlowAllFeatures()

        XCTAssertEqual(0, TestUtils.getCurrentEQ()?.count)
        XCTAssertEqual(9, TestUtils.getCurrentRQ()?.count)
        
        try TestUtils.validateEventInRQ("[CLY]_star_rating", [
            "platform": "iOS",
            "app_version": CountlyDeviceInfo.appVersion()!,
            "rating": "5",
            "widget_id": "test",
            "contactMe": 1,
            "email": "test",
            "comment": "test"
        ], 8, 9, 0, 2)
        
        try TestUtils.validateEventInRQ("[CLY]_nps", [
            "app_version": CountlyDeviceInfo.appVersion()!,
            "widget_id": "test",
            "closed": "1",
            "platform": "iOS"
        ], 8, 9, 1, 2)
        
        XCTAssertEqual(9, TestUtils.getCurrentRQ()?.count)
        
        validateCounts(tracker.counts, hc: hc, fc: fc, rc: rc, cc: cc, sc: scc)
    }
    
    private func setServerConfig(_ serverConfig: [String: Any]){
        UserDefaults.standard.set(serverConfig, forKey: "kCountlyServerConfigPersistencyKey")
        UserDefaults.standard.synchronize() // Not needed in modern Swift
    }
    
    func retrieveServerConfig() -> [String: Any] {
        return UserDefaults.standard.object(forKey: "kCountlyServerConfigPersistencyKey") as? [String: Any] ?? [:]
    }
}
