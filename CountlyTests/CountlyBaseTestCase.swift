//
//  CountlyBaseTestCase.swift
//  CountlyTests
//
//  Created by Muhammad Junaid Akram on 27/12/2023.
//  Copyright © 2023 Countly. All rights reserved.
//

import XCTest
@testable import Countly

class CountlyBaseTestCase: XCTestCase {
    var countly: Countly!
    var deviceID: String = ""
    let appKey: String = "appkey"
    var host: String = "https://testing.count.ly/"
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        cleanupState()
    }
    
    func createBaseConfig() -> CountlyConfig {
        let config: CountlyConfig = CountlyConfig()
        config.appKey = appKey
        config.host = host
        config.enableDebug = true
        config.features = [CLYFeature.crashReporting];
        return config
    }
    
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func cleanupState() {
        // Fully purge any state persisted by a previous test *process*. halt(true) alone does
        // not reliably clear stale persisted requests when the SDK was never started in this
        // process (this is the edge case the historical `testDummy` was added to work around).
        // Starting first wires up persistency/connection-manager and loads the stale state, then
        // halt(true) forces a full reset + empty save — so every test, including ones run in
        // isolation, begins from a clean slate.
        let config = createBaseConfig()
        config.requiresConsent = false
        config.manualSessionHandling = true
        Countly.sharedInstance().start(with: config)
        Countly.sharedInstance().halt(true)
    }
}


