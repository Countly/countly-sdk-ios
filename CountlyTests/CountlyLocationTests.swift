//
//  CountlyLocationTests.swift
//  CountlyTests
//
//  Created by Muhammad Junaid Akram on 25/07/2024.
//  Copyright © 2024 Countly. All rights reserved.
//

import XCTest
@testable import Countly

// M:Manual Sessions enabled
// A:Automatic sessions enabled
// H:Hybrid Sessions enabled
// CR:Consent Required
// CNR:Consent not Required
// CG:Consent given (All)
// CNG:Consent not given (All)
// CGS:Consent given for session
// CGL:Consent givent for location
// LD:Location Disable
// L: Location Provided

class CountlyLocationTests: CountlyBaseTestCase {
    
    func testDummy() {
    }
    
    func testLocationInit_CNR_A() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config);
        
        // get request queue
        guard let queuedRequests =  CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? [String] else {
            fatalError("Failed to get queuedRequests from CountlyPersistency")
        }
        XCTAssertTrue(queuedRequests[0].contains("begin_session=1"), "Begin session failed.")
        XCTAssertFalse(queuedRequests[0].contains("location="), "Location should not be send in this scenario")
    }
    
    func testLocationInit_CR_CNG_A() throws {
        let config = createBaseConfig()
        config.requiresConsent = true
        Countly.sharedInstance().start(with: config);
        
        // get request queue
        guard let queuedRequests =  CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? [String] else {
            fatalError("Failed to get queuedRequests from CountlyPersistency")
        }
        
        XCTAssertFalse(queuedRequests[0].contains("begin_session=1"), "Begin session should not start session consent is not given.")
        XCTAssertTrue(queuedRequests[1].contains("location="), "Individual location request should send in this scenario")
    }
    
    func testLocationInit_CR_CG_A() throws {
        let config = createBaseConfig()
        config.requiresConsent = true
        config.enableAllConsents = true
        Countly.sharedInstance().start(with: config);
        
        // get request queue
        guard let queuedRequests =  CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? [String] else {
            fatalError("Failed to get queuedRequests from CountlyPersistency")
        }
        
        XCTAssertTrue(queuedRequests[0].contains("begin_session=1"), "Begin session failed.")
        XCTAssertFalse(queuedRequests[0].contains("location="), "Location should not be send in this scenario")
    }
    
    func testLocationInit_CR_CGS_A() throws {
        let config = createBaseConfig()
        config.requiresConsent = true
        config.consents = [CLYConsent.sessions];
        Countly.sharedInstance().start(with: config);
        
        // get request queue
        guard let queuedRequests =  CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? [String] else {
            fatalError("Failed to get queuedRequests from CountlyPersistency")
        }
        
        XCTAssertTrue(queuedRequests[0].contains("begin_session=1"), "Begin session failed.")
        XCTAssertTrue(queuedRequests[0].contains("location="), "Location should send in this scenario")
    }
    
    func testLocationInit_CR_CGL_A() throws {
        let config = createBaseConfig()
        config.requiresConsent = true
        config.consents = [CLYConsent.location];
        Countly.sharedInstance().start(with: config);
        
        // get request queue
        guard let queuedRequests =  CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? [String] else {
            fatalError("Failed to get queuedRequests from CountlyPersistency")
        }
        
        XCTAssertTrue(queuedRequests[0].contains("consent="), "Only consent request should send in this scenario")
    }
    
    func testLocationInit_CR_CGLS_A() throws {
        let config = createBaseConfig()
        config.requiresConsent = true
        config.consents = [CLYConsent.location, CLYConsent.sessions];
        Countly.sharedInstance().start(with: config);
        
        // get request queue
        guard let queuedRequests =  CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? [String] else {
            fatalError("Failed to get queuedRequests from CountlyPersistency")
        }
        
        XCTAssertTrue(queuedRequests[0].contains("begin_session=1"), "Begin session failed.")
        XCTAssertFalse(queuedRequests[0].contains("location="), "Location should not be send in this scenario")
    }
    
    func testLocationInit_CNR_A_L() throws {
        let config = createBaseConfig()
        config.location = CLLocationCoordinate2D(latitude:35.6895, longitude: 139.6917)
        config.city = "Tokyo"
        config.isoCountryCode = "JP"
        config.ip = "255.255.255.255"
        Countly.sharedInstance().start(with: config);
        
        // get request queue
        guard let queuedRequests =  CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? [String] else {
            fatalError("Failed to get queuedRequests from CountlyPersistency")
        }
        XCTAssertTrue(queuedRequests[0].contains("begin_session=1"), "Begin session failed.")
        
        let parsedRequest = TestUtils.parseQueryString(queuedRequests[0])
        
        XCTAssertTrue((parsedRequest["location"] as! String) == "35.689500,139.691700", "Begin session should contains provided location")
        XCTAssertTrue((parsedRequest["city"] as! String) == "Tokyo", "Begin session should contains provided city")
        XCTAssertTrue((parsedRequest["country_code"] as! String) == "JP", "Begin session should contains provided country code")
        XCTAssertTrue((parsedRequest["ip_address"] as! String) == "255.255.255.255", "Begin session should contains provided IP address")
    }
    
    func testLocationInit_CNR_M() throws {
        let config = createBaseConfig()
        config.manualSessionHandling = true
        Countly.sharedInstance().start(with: config);
        
        Countly.sharedInstance().beginSession()
        
        // get request queue
        guard let queuedRequests =  CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? [String] else {
            fatalError("Failed to get queuedRequests from CountlyPersistency")
        }
        XCTAssertTrue(queuedRequests[0].contains("begin_session=1"), "Begin session failed.")
        XCTAssertFalse(queuedRequests[0].contains("location="), "Location should not be send in this scenario")
    }
    
    func testLocationInit_CR_CNG_M() throws {
        let config = createBaseConfig()
        config.manualSessionHandling = true
        config.requiresConsent = true
        Countly.sharedInstance().start(with: config);
        Countly.sharedInstance().beginSession()
        
        // get request queue
        guard let queuedRequests =  CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? [String] else {
            fatalError("Failed to get queuedRequests from CountlyPersistency")
        }
        
        XCTAssertFalse(queuedRequests[0].contains("begin_session=1"), "Begin session should not start session consent is not given.")
        XCTAssertTrue(queuedRequests[1].contains("location="), "Individual location request should send in this scenario")
    }
    
    func testLocationInit_CR_CG_M() throws {
        let config = createBaseConfig()
        config.manualSessionHandling = true
        config.requiresConsent = true
        config.enableAllConsents = true
        Countly.sharedInstance().start(with: config);
        Countly.sharedInstance().beginSession()
        
        // get request queue
        guard let queuedRequests =  CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? [String] else {
            fatalError("Failed to get queuedRequests from CountlyPersistency")
        }
        
        XCTAssertTrue(queuedRequests[1].contains("begin_session=1"), "Begin session failed.")
        XCTAssertFalse(queuedRequests[1].contains("location="), "Location should not be send in this scenario")
    }
    
    func testLocationInit_CR_CGS_M() throws {
        let config = createBaseConfig()
        config.manualSessionHandling = true
        config.requiresConsent = true
        config.consents = [CLYConsent.sessions];
        Countly.sharedInstance().start(with: config);
        Countly.sharedInstance().beginSession()
        
        // get request queue
        guard let queuedRequests =  CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? [String] else {
            fatalError("Failed to get queuedRequests from CountlyPersistency")
        }
        
        XCTAssertTrue(queuedRequests[1].contains("begin_session=1"), "Begin session failed.")
        XCTAssertTrue(queuedRequests[1].contains("location="), "Location should send in this scenario")
    }
    
    func testLocationInit_CR_CGL_M() throws {
        let config = createBaseConfig()
        config.manualSessionHandling = true
        config.requiresConsent = true
        config.consents = [CLYConsent.location];
        Countly.sharedInstance().start(with: config);
        Countly.sharedInstance().beginSession()
        
        // get request queue
        guard let queuedRequests =  CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? [String] else {
            fatalError("Failed to get queuedRequests from CountlyPersistency")
        }
        
        XCTAssertTrue(queuedRequests[0].contains("consent="), "Only consent request should send in this scenario")
    }
    
    func testLocationInit_CR_CGLS_M() throws {
        let config = createBaseConfig()
        config.manualSessionHandling = true
        config.requiresConsent = true
        config.consents = [CLYConsent.location, CLYConsent.sessions];
        Countly.sharedInstance().start(with: config);
        Countly.sharedInstance().beginSession()
        
        // get request queue
        guard let queuedRequests =  CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? [String] else {
            fatalError("Failed to get queuedRequests from CountlyPersistency")
        }
        
        XCTAssertTrue(queuedRequests[1].contains("begin_session=1"), "Begin session failed.")
        XCTAssertFalse(queuedRequests[1].contains("location="), "Location should not be send in this scenario")
    }
    
    func testLocationInit_CNR_M_L() throws {
        let config = createBaseConfig()
        config.manualSessionHandling = true
        config.location = CLLocationCoordinate2D(latitude:35.6895, longitude: 139.6917)
        config.city = "Tokyo"
        config.isoCountryCode = "JP"
        config.ip = "255.255.255.255"
        Countly.sharedInstance().start(with: config);
        Countly.sharedInstance().beginSession()
        
        // get request queue
        guard let queuedRequests =  CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? [String] else {
            fatalError("Failed to get queuedRequests from CountlyPersistency")
        }
        XCTAssertTrue(queuedRequests[0].contains("begin_session=1"), "Begin session failed.")
        
        let parsedRequest = TestUtils.parseQueryString(queuedRequests[0])
        
        XCTAssertTrue((parsedRequest["location"] as! String) == "35.689500,139.691700", "Begin session should contains provided location")
        XCTAssertTrue((parsedRequest["city"] as! String) == "Tokyo", "Begin session should contains provided city")
        XCTAssertTrue((parsedRequest["country_code"] as! String) == "JP", "Begin session should contains provided country code")
        XCTAssertTrue((parsedRequest["ip_address"] as! String) == "255.255.255.255", "Begin session should contains provided IP address")
    }

    /**
     * <pre>
     * Behavior settings that turn location tracking off are applied at start before the SDK has its app key and host, so
     * the empty location they call for is sent once init is complete. A request queued earlier carries "app_key=(null)",
     * the server rejects it, and a rejected request stays at the head of the queue, holding back every request behind it.
     *
     * 1- Start with provided behavior settings that turn location tracking off, against a server that rejects an unknown app key
     * 2- Verify the session begin and the empty location reach the server, and every request carries the app key
     * 3- Halt and start again with the same settings: halt resets the location state, so the restart takes the same path
     * </pre>
     */
    func testLocationTrackingOffAtStart_theSessionBeginIsNotHeldBehindARejectedRequest() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        let server = AppKeyCheckingServer(appKey: appKey)
        MockURLProtocol.requestHandler = server.answer
        defer { MockURLProtocol.replyEmptyToEveryRequest() }
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]

        for run in ["first start", "restart after halt"] {
            server.forgetReceived()
            let config = createBaseConfig()
            config.urlSessionConfiguration = sessionConfig
            config.sdkBehaviorSettings = ServerConfigBuilder().locationTracking(false).build()
            Countly.sharedInstance().start(with: config)
            assertEveryRequestReachesTheServer(server, run)
            Countly.sharedInstance().halt(true)
        }
    }

    /// Waits for the request queue to be sent, then checks that the session begin and the empty location reached the server
    /// and that every request received or still queued carries the app key.
    private func assertEveryRequestReachesTheServer(_ server: AppKeyCheckingServer, _ run: String, file: StaticString = #filePath, line: UInt = #line) {
        TestUtils.waitUntil("the request queue is sent") { TestUtils.getCurrentRQ()?.isEmpty ?? true }
        let received = server.received
        XCTAssertTrue(received.contains { $0.contains("begin_session=1") }, "\(run): the session begin must not wait behind a rejected request, received: \(received)", file: file, line: line)
        XCTAssertTrue(received.contains { TestUtils.parseQueryString($0)["location"] as? String == "" }, "\(run): the empty location reaches the server, received: \(received)", file: file, line: line)
        for query in received + (TestUtils.getCurrentRQ() ?? []) {
            XCTAssertEqual(appKey, TestUtils.parseQueryString(query)["app_key"] as? String, "\(run): every request carries the app key: \(query)", file: file, line: line)
        }
    }
}

/// Answers like a Countly server, which rejects a request with an app key it does not know, and records what it received.
private final class AppKeyCheckingServer {
    private let lock = NSLock()
    private let appKey: String
    private var queries: [String] = []

    init(appKey: String) {
        self.appKey = appKey
    }

    /// Records the request and answers it, with the server's 400 when it does not carry the known app key.
    func answer(_ request: URLRequest) -> (Data?, URLResponse?, Error?) {
        let query = CountlyServerConfigTests.capturedQueryString(request)
        lock.lock()
        queries.append(query)
        lock.unlock()
        let isKnownApp = TestUtils.parseQueryString(query)["app_key"] as? String == appKey
        let body = isKnownApp ? #"{"result":"Success"}"# : #"{"result":"App does not exist"}"#
        return (body.data(using: .utf8), HTTPURLResponse(url: request.url!, statusCode: isKnownApp ? 200 : 400, httpVersion: nil, headerFields: nil), nil)
    }

    /// The query strings received so far, in the order they arrived.
    var received: [String] {
        lock.lock()
        defer { lock.unlock() }
        return queries
    }

    /// Forgets the requests received so far.
    func forgetReceived() {
        lock.lock()
        queries = []
        lock.unlock()
    }
}

