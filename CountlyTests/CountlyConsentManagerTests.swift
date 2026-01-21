//
//  CountlyConsentManagerTests.swift
//  Countly
//
//  Created by Arif Burak Demiray on 18.11.2025.
//  Copyright © 2025 Countly. All rights reserved.
//
import Foundation

import XCTest
@testable import Countly

class CountlyConsentManagerTests: CountlyBaseTestCase {
    
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
    /**
     * Tests that consent requirement is properly handled when enabled.
     * Verifies that:
     * 1. Initial consent request is sent as none given
     * 2. No data is collected until consent is given
     * 3. Location is properly handled with empty value
     * 4. After giveAllConsent call, consent request sent as all given
     */
    func test_giveAllConsents() {
        let config = TestUtils.createBaseConfig()
        config.requiresConsent = true
        
        Countly.sharedInstance().start(with: config)
        XCTAssertEqual(2, TestUtils.getCurrentRQ()?.count)
        Countly.sharedInstance().giveAllConsents()
        XCTAssertEqual(4, TestUtils.getCurrentRQ()?.count)
        var consents: [String: Any?] = [
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
            "views": 0,
            "metrics": 0
        ]

        TestUtils.validateRequest(["consent": consents], 0)
        TestUtils.validateRequest(["location": ""], 1)
        TestUtils.validateRequest(["begin_session": "1"], 2)
        for key in consents.keys {
            consents[key] = 1
        }
        TestUtils.validateRequest(["consent": consents], 3)

    }
    
}



