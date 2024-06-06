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
    
    func parseQueryString(_ queryString: String) -> [String: Any] {
        var result: [String: Any] = [:]
        
        // Split the query string by '&' to get individual key-value pairs
        let pairs = queryString.split(separator: "&")
        
        for pair in pairs {
            // Split each pair by '=' to separate the key and value
            let components = pair.split(separator: "=", maxSplits: 1)
            
            if components.count == 2 {
                let key = String(components[0])
                let value = String(components[1])
                
                // If the value is a JSON string (starts and ends with '%7B' and '%7D' respectively after URL decoding), decode it
                if let decodedValue = value.removingPercentEncoding, decodedValue.hasPrefix("{"), decodedValue.hasSuffix("}") {
                    if let jsonData = decodedValue.data(using: .utf8) {
                        do {
                            let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
                            result[key] = jsonObject
                            continue
                        } catch {
                            print("Error decoding JSON for key \(key): \(error)")
                        }
                    }
                }
                
                // Otherwise, simply assign the value to the key in the result dictionary
                result[key] = value.removingPercentEncoding ?? value
            }
        }
        
        return result
    }
    
}


