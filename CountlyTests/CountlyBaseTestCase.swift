//
//  CountlyBaseTestCase.swift
//  CountlyTests
//
//  Created by Muhammad Junaid Akram on 27/12/2023.
//  Copyright © 2023 Alin Radut. All rights reserved.
//

import XCTest
@testable import Countly

class CountlyBaseTestCase: XCTestCase {
    var countly: Countly!
    var deviceID: String = ""
    let appKey: String = "appkey"
    var host: String = "https://test.count.ly/"
    
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
        Countly.sharedInstance().halt(true)
    }
    
}


