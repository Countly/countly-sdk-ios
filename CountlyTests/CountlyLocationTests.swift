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
    
}

