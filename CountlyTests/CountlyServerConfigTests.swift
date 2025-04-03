import XCTest
@testable import Countly

class CountlyServerConfigTests: CountlyBaseTestCase {

    override func setUp() {
        super.setUp()
        // Initialize or reset necessary objects here
        Countly.sharedInstance().halt(true)
    }

    override func tearDown() {
        // Ensure everything is cleaned up properly
        super.tearDown()
        Countly.sharedInstance().halt(true)
    }

    // MARK: - Basic Configuration Tests
    
    /**
     * Test default configuration when server config is disabled and storage is empty
     */
    func testDefaultConfigWhenServerConfigDisabledAndStorageEmpty() {
        let config = createBaseConfig()
        
        Countly.sharedInstance().start(with: config)
        
        let serverConfig = retrieveServerConfig()
        
        XCTAssertTrue(serverConfig.isEmpty)
        assertDefaultConfigValues(Countly.sharedInstance());
    }
    
    /**
     * Test default configuration when server config is enabled and storage is empty
     */
    func testDefaultConfigWhenServerConfigEnabledAndStorageEmpty() {
        let config = createBaseConfig()
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
    func testServerConfigWhenEnabledAndAllPropertiesAllowing() throws {
        setServerConfig(createStorageConfig(tracking: true, networking: true, crashes: true))
        let config = createBaseConfig()
        config.enableServerConfiguration = true;
        let countly = Countly()
        countly.start(with: config)
        
        XCTAssertNotNil(CountlyPersistency.sharedInstance().retrieveServerConfig())
        assertDefaultConfigValues(countly)
    }
    
    /**
     * Test configuration when server config is enabled and all properties are forbidding
     */
    func testServerConfigWhenEnabledAndAllPropertiesForbidding() {
        setServerConfig(createStorageConfig(tracking: false, networking: false, crashes: false))
        let config = createBaseConfig()
        config.enableServerConfiguration = true
        config.enableDebug = false
        
        Countly.sharedInstance().start(with: config)
        
        sleep(2, {
            XCTAssertFalse(retrieveServerConfig().isEmpty)
            XCTAssertFalse(CountlyServerConfig.sharedInstance().networkingEnabled())
            XCTAssertFalse(CountlyServerConfig.sharedInstance().trackingEnabled())
            XCTAssertFalse(CountlyServerConfig.sharedInstance().crashReportingEnabled())
        })
    }
    
    /**
     * Test configuration when server config is disabled and all properties are allowing
     */
    func testServerConfigWhenDisabledAndAllPropertiesAllowing() throws {
        setServerConfig(createStorageConfig(tracking: true, networking: true, crashes: true))
        let config = createBaseConfig()
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
    func testServerConfigDefaultValues() throws {
        let config = createBaseConfig()
        config.enableDebug = false
        Countly.sharedInstance().start(with: config)
        sleep(2, {ServerConfigBuilder().defaults().validateAgainst()})
    }
    
    /**
     * Tests that custom server configuration values are correctly applied when provided directly.
     * Verifies that the configuration is properly parsed and applied to the SDK.
     */
    func testServerConfigProvidedValues() throws {
        try initServerConfigWithValues { config, serverConfig in
            config.serverConfiguration = serverConfig
        }
    }
    
    /**
     * Tests that server configuration values are correctly applied when using an immediate request generator.
     * Verifies that the configuration is properly handled when received through the request generator.
     */
    func testServerConfigWithImmediateRequestGenerator() throws {
        try initServerConfigWithValues { config, serverConfig in
            config.urlSessionConfiguration = createUrlSessionConfigForResponse(serverConfig)
        }
    }
    
    /**
     * Tests that all features work correctly with default server configuration.
     * Verifies that all SDK features (sessions, events, views, crashes, etc.) function as expected
     * when using default configuration values.
     */
    func testServerConfigDefaultsAllFeatures() throws {
        try baseAllFeatures({ _ in }, hc: 0, fc: 1, rc: 1, cc: 2, scc: 1)
    }
    
    /**
     * Tests that all features are properly disabled when explicitly configured to be disabled.
     * Verifies that no requests are generated and no data is collected when all features are disabled.
     */
    func testDisableAllFeatures() {
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
        
        let counts = setupTestAllFeatures(sc.buildJson())
        
        XCTAssertEqual(0, getCurrentRQ()?.count)
        XCTAssertEqual(0, getCurrentEQ()?.count)
        
        flowAllFeatures()
        XCTAssertEqual(0, getCurrentRQ()?.count)
        
        immediateFlowAllFeatures()
        XCTAssertEqual(0, getCurrentEQ()?.count)

        feedbackFlowAllFeatures()
        XCTAssertEqual(0, getCurrentRQ()?.count)
        XCTAssertEqual(0, getCurrentEQ()?.count)
        
        validateCounts(counts, hc: 0, fc: 0, rc: 0, cc: 0, sc: 1)
    }
    
    /**
     * Tests that consent requirement is properly handled when enabled.
     * Verifies that:
     * 1. Initial consent request is sent
     * 2. No data is collected until consent is given
     * 3. Location is properly handled with empty value
     */
    func testConsentEnabledAllFeatures() {
        Countly.sharedInstance().halt(true)
        let sc = ServerConfigBuilder()
        sc.consentRequired(true)
        
        let counts = setupTestAllFeatures(sc.buildJson())
        
        XCTAssertEqual(0, getCurrentRQ()?.count)
        XCTAssertEqual(0, getCurrentEQ()?.count)
        // VALIDATE CONSENT ALL FALSE idx 0
        // VALIDATE DISABLE LOCATION idx 1
        
        flowAllFeatures()
        immediateFlowAllFeatures()
        XCTAssertEqual(0, getCurrentEQ()?.count)
        feedbackFlowAllFeatures()
        
        XCTAssertEqual(2, getCurrentRQ()?.count)
        XCTAssertEqual(0, getCurrentEQ()?.count)

        validateCounts(counts, hc: 0, fc: 0, rc: 0, cc: 0, sc: 1)
    }
    
    /**
     * Tests that session tracking is properly disabled when configured.
     * Verifies that:
     * 1. No session requests are generated
     * 2. Other features (events, views, crashes) continue to work
     * 3. Request counts and order are maintained correctly
     */
    func testSessionsDisabledAllFeatures() throws {
        let sc = ServerConfigBuilder()
        sc.sessionTracking(false)
        let counts = setupTestAllFeatures(sc.buildJson())
        
        XCTAssertEqual(0, getCurrentRQ()?.count)
        XCTAssertEqual(0, getCurrentEQ()?.count)
        
        let stackTrace = flowAllFeatures()
        
        //ModuleCrashTests.validateCrash(stackTrace, "", false, false, 7, 0, [:], 0, [:], [])
        try validateEventInRQ("test_event", [:], 1, 7, 0, 2)
        try validateEventInRQ("[CLY]_view", ["name": "test_view", "segment": "iOS", "visit": "1"], 1, 7, 1, 2)
        //ModuleUserProfileTests.validateUserProfileRequest(2, 7, [:], ["test_property": "test_value"])
        //TestUtils.validateRequest(TestUtils.commonDeviceId, ["location": "gps"], 3)
        //ModuleAPMTests.validateNetworkRequest(4, 7, "test_trace", 1111, 400, 2000, 1111)
        //TestUtils.validateRequest(TestUtils.commonDeviceId, ["attribution_data": "test_data"], 5)
        //TestUtils.validateRequest(TestUtils.commonDeviceId, ["key": "value"], 6)
        
        XCTAssertEqual(8, getCurrentRQ()?.count)
        immediateFlowAllFeatures()
        
        XCTAssertEqual(0, getCurrentEQ()?.count)
        feedbackFlowAllFeatures()
        XCTAssertEqual(1, getCurrentEQ()?.count)

        try validateEventInRQ("[CLY]_star_rating", [
            "platform": "ios",
            "app_version": "1.0", // TODO Countly.DEFAULT_APP_VERSION
            "rating": "5",
            "widget_id": "test",
            "contactMe": true,
            "email": "test",
            "comment": "test"
        ], 7, 8, 0, 2)
        
        try validateEventInRQ("[CLY]_nps", [
            "app_version": "1.0", // TODO APP_VERSION
            "widget_id": "test",
            "closed": "1",
            "platform": "ios"
        ], 7, 8, 1, 2)
        
        XCTAssertEqual(8, getCurrentRQ()?.count)

        validateCounts(counts, hc: 0, fc: 1, rc: 1, cc: 2, sc: 1)
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
    func testEventQueueSize() throws {
        let countlyConfig = createBaseConfig()
        countlyConfig.manualSessionHandling = true
        countlyConfig.urlSessionConfiguration = createUrlSessionConfigForResponse(ServerConfigBuilder().eventQueueSize(3).build())
        Countly.sharedInstance().start(with: countlyConfig)
        
        XCTAssertEqual(0, getCurrentRQ()?.count)
        XCTAssertEqual(0, getCurrentRQ()?.count)
        
        Countly.sharedInstance().recordEvent("test_event")
        XCTAssertEqual(0, getCurrentRQ()?.count)
        XCTAssertEqual(1, getCurrentEQ()?.count)
        
        Countly.sharedInstance().recordEvent("test_event_1")
        XCTAssertEqual(0, getCurrentRQ()?.count)
        XCTAssertEqual(2, getCurrentEQ()?.count)
        
        Countly.sharedInstance().recordEvent("test_event_2")
        XCTAssertEqual(0, getCurrentRQ()?.count) // Android Packs Here
        XCTAssertEqual(3, getCurrentEQ()?.count) // Android Flush Here
        
        Countly.sharedInstance().recordEvent("test_event_3")
        XCTAssertEqual(0, getCurrentRQ()?.count)
        XCTAssertEqual(4, getCurrentEQ()?.count)
        
        try validateEventInRQ("test_event", [:], 0, 1, 0, 3)
        try validateEventInRQ("test_event_1", [:], 0, 1, 1, 3)
        try validateEventInRQ("test_event_2", [:], 0, 1, 2, 3)
    }
    
    /**
     * Tests that the request queue size limit is properly enforced.
     * Verifies that:
     * 1. Requests are queued until the size limit is reached
     * 2. When limit is reached, new requests are rejected
     * 3. Different types of requests (sessions, attribution, location) are counted towards the limit
     */
    func testRequestQueueSize() throws {
        let countlyConfig = createBaseConfig()
        countlyConfig.manualSessionHandling = true
        countlyConfig.urlSessionConfiguration = createUrlSessionConfigForResponse(ServerConfigBuilder().requestQueueSize(3).build())
        Countly.sharedInstance().start(with: countlyConfig)
        
        Countly.sharedInstance().beginSession()
        XCTAssertTrue(getCurrentRQ()![0].contains("begin_session"))
        
        Countly.sharedInstance().recordDirectAttribution(withCampaignType: "_special_test", andCampaignData: "_special_test")
        XCTAssertEqual(2, getCurrentRQ()?.count)
        
        Countly.sharedInstance().recordLocation(CLLocationCoordinate2D(latitude:33.6895, longitude:139.6917), city:"Tokyo", isoCountryCode:"JP", ip:"255.255.255.255");
        XCTAssertEqual(3, getCurrentRQ()?.count)
        
        let params = ["key": "value"]
        Countly.sharedInstance().addDirectRequest(params)
        

        XCTAssertFalse(getCurrentRQ()![0].contains("begin_session"))
    }
    
    // MARK: - Helper Methods
    
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
    
    private func initAndValidateConfigParsingResult(_ targetResponse: String?, responseAccepted: Bool) -> Countly {
        let config = createBaseConfig()
        config.enableServerConfiguration = true
        
        if let response = targetResponse {
            config.urlSessionConfiguration = createUrlSessionConfigForResponse(response)
        }
        
        let countly = Countly()
        countly.start(with: config)
        
        let serverConfig = retrieveServerConfig()
        
        if !responseAccepted {
            XCTAssertNil(serverConfig)
            assertDefaultConfigValues(countly)
        } else {
            XCTAssertNotNil(serverConfig)
        }
        
        return countly
    }
    
    private func createUrlSessionConfigForResponse(_ targetResponse: String) -> URLSessionConfiguration {
        
        MockURLProtocol.requestHandler = { request in
            return (targetResponse.data(using: .utf8), HTTPURLResponse(url: request.url!,
                                            statusCode: 200,
                                            httpVersion: nil,
                                            headerFields: nil), nil)
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
        let countlyConfig = createBaseConfig()
        configSetter(countlyConfig, serverConfig)
        
        let countly = Countly()
        countly.start(with: countlyConfig)
        
        sleep(2, {builder.validateAgainst()})
        
    }
    
    private func setupTestAllFeatures(_ serverConfig: [String: Any]) -> [Int] {
        var counts = [0, 0, 0, 0, 0]
                
        // Define the mock behavior
        MockURLProtocol.requestHandler = { request in
            let requestString = request.url?.absoluteString ?? ""

            if requestString.contains("hc=") { // TODO IOS DOES NOT HAVE HC
                counts[0] += 1
            } else if requestString.contains("method=feedback") {
                counts[1] += 1
            } else if requestString.contains("method=rc") {
                counts[2] += 1
            } else if requestString.contains("method=queue") {
                counts[3] += 1
            } else if requestString.contains("method=sc") {
                // Do nothing
            }

            if requestString.contains("method=sc") {
                counts[4] += 1
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

            return ("{\"result\":\"success\"}".data(using: .utf8), HTTPURLResponse(url: request.url!,
                                            statusCode: 200,
                                            httpVersion: nil,
                                            headerFields: nil), nil)
        }

        // Create a URLSession using the mock protocol
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        
        let countlyConfig = createBaseConfig()
        countlyConfig.manualSessionHandling = true
        countlyConfig.urlSessionConfiguration = config;
        
        Countly.sharedInstance().start(with: countlyConfig)
        //Countly.sharedInstance().moduleContent.CONTENT_START_DELAY_MS = 0
        //Countly.sharedInstance().moduleContent.REFRESH_CONTENT_ZONE_DELAY_MS = 0
        
        return counts
    }
    
    private func validateCounts(_ counts: [Int], hc: Int, fc: Int, rc: Int, cc: Int, sc: Int) {
        sleep(2) {
            XCTAssertEqual(hc, counts[0]) // health check request
            XCTAssertEqual(fc, counts[1]) // feedback request
            XCTAssertEqual(rc, counts[2]) // remote config request
            XCTAssertEqual(cc, counts[3]) // content request
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
        let expectation = expectation(description: "Wait for all network requests")
        expectation.expectedFulfillmentCount = 2
        Countly.sharedInstance().remoteConfig().downloadKeys { response, error, fullValueUpdate, downloadedValues in
            if(error == nil){
                expectation.fulfill()
            }
         }
        Countly.sharedInstance().feedback().getAvailableFeedbackWidgets { (feedbackWidgets: [CountlyFeedbackWidget]?, error) in
            if (error != nil)
            {
              print("Getting widgets list failed. \n \(error!.localizedDescription) \n \((error! as NSError).userInfo)")
            }
            else
            {
                expectation.fulfill()
              print("Getting widgets list successfully completed. \(String(describing: feedbackWidgets))")
            }
          }
        Countly.sharedInstance().content().enterContentZone()
        waitForExpectations(timeout: 10)

        sleep(2) {
            Countly.sharedInstance().content().refreshContentZone()
        }
        
    }
    
    private func feedbackFlowAllFeatures() {
        Countly.sharedInstance().recordRatingWidget(withID: "test", rating: 5, email: "test", comment: "test", userCanBeContacted: true)
        let widget = CountlyFeedbackWidget()
        widget.recordResult(nil)
    }
    
    private func validateEventInRQ(_ eventName: String, _ segmentation: [String: Any], _ idx: Int, _ rqCount: Int, _ eventIdx: Int, _ eventCount: Int) throws {
        //ModuleEventsTests.validateEventInRQ(
          //  TestUtils.commonDeviceId,
           // eventName,
           // segmentation,
            //1,
            //0.0,
            //0.0,
            //"_CLY_",
            //"_CLY_",
            //"_CLY_",
            //"_CLY_",
            //idx,
            //rqCount,
            //eventIdx,
            //eventCount
       // )
    }
    
    private func baseAllFeatures(_ consumer: (ServerConfigBuilder) -> Void, hc: Int, fc: Int, rc: Int, cc: Int, scc: Int) throws {
        let sc = ServerConfigBuilder()
        consumer(sc)
        let counts = setupTestAllFeatures(sc.buildJson())
        
        XCTAssertEqual(0, getCurrentRQ()?.count)
        XCTAssertEqual(0, getCurrentEQ()?.count)
        
        let stackTrace = flowAllFeatures()
        
        //ModuleSessionsTests.validateSessionBeginRequest(0, TestUtils.commonDeviceId)
        //ModuleCrashTests.validateCrash(stackTrace, "", false, false, 8, 1, [:], 0, [:], [])
        try validateEventInRQ("[CLY]_orientation", ["mode": "portrait"], 2, 8, 0, 3)
        try validateEventInRQ("test_event", [:], 2, 8, 1, 3)
        try validateEventInRQ("[CLY]_view", ["name": "test_view", "segment": "iOS", "visit": "1", "start": "1"], 2, 8, 2, 3)
        //ModuleUserProfileTests.validateUserProfileRequest(3, 8, [:], ["test_property": "test_value"])
        //TestUtils.validateRequest(TestUtils.commonDeviceId, ["location": "gps"], 4)
        //ModuleAPMTests.validateNetworkRequest(5, 8, "test_trace", 1111, 400, 2000, 1111)
        //TestUtils.validateRequest(TestUtils.commonDeviceId, ["attribution_data": "test_data"], 6)
        //TestUtils.validateRequest(TestUtils.commonDeviceId, ["key": "value"], 7)
        
        XCTAssertEqual(8, getCurrentRQ()?.count)
        
        immediateFlowAllFeatures()
        XCTAssertEqual(0, getCurrentEQ()?.count)
        feedbackFlowAllFeatures()
        XCTAssertEqual(1, getCurrentEQ()?.count)
        
        try validateEventInRQ("[CLY]_star_rating", [
            "platform": "ios",
            "app_version": "",//Countly.DEFAULT_APP_VERSION,
            "rating": "5",
            "widget_id": "test",
            "contactMe": true,
            "email": "test",
            "comment": "test"
        ], 8, 9, 0, 2)
        
        try validateEventInRQ("[CLY]_nps", [
            "app_version": "",//Countly.DEFAULT_APP_VERSION,
            "widget_id": "test",
            "closed": "1",
            "platform": "ios"
        ], 8, 9, 1, 2)
        
        XCTAssertEqual(8, getCurrentRQ()?.count)
        
        validateCounts(counts, hc: hc, fc: fc, rc: rc, cc: cc, sc: scc)
    }
    
    private func getCurrentRQ() -> [String]? {
        return CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? [String];
    }
    
    private func getCurrentEQ() -> [CountlyEvent]? {
        return CountlyPersistency.sharedInstance().value(forKey: "recordedEvents") as? [CountlyEvent];
    }
    
    private func setServerConfig(_ serverConfig: [String: Any]){
        UserDefaults.standard.set(serverConfig, forKey: "kCountlyServerConfigPersistencyKey")
        UserDefaults.standard.synchronize() // Not needed in modern Swift
    }
    
    func retrieveServerConfig() -> [String: Any] {
        return UserDefaults.standard.object(forKey: "kCountlyServerConfigPersistencyKey") as? [String: Any] ?? [:]
    }
    
    private func sleep(_ seconds: TimeInterval, _ job: () -> Void){
        let exp = expectation(description: "Run after \(seconds) seconds")
        let result = XCTWaiter.wait(for: [exp], timeout: seconds)
        if result == XCTWaiter.Result.timedOut {
            job()
        } else {
            XCTFail("Delay interrupted")
        }
    }

}
