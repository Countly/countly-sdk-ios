// CountlyTests.swift
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

import XCTest

@testable import Countly

final class CountlyTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        let config: CountlyConfig = CountlyConfig()
        config.appKey = "58594c9a3f461ebc000761a68c2146659ef75ea0"
        config.host = "https://master.count.ly"
        config.enableDebug = true
        //        config.loggerDelegate = self
        
        config.features = [CLYFeature.crashReporting] //Optional features
        
        config.enableRemoteConfig = true
        config.remoteConfigCompletionHandler = { (error : Error?) in
            if (error == nil)
            {
                var baloon : Any? = Countly.sharedInstance().remoteConfigValue(forKey:"baloon")
                
                print("baloon value AppDelegate success: \(baloon ?? 0)")
                
                //                if (baloon == nil) //if value does not exist, you can set your default fallback value
                //                {
                //                    baloon = "default value"
                //                }
                //                else // if value exists, you can use it as you see fit
                //                {
                //                    print("baloon value : \(baloon ?? 0)")
                //                }
            }
            else
            {
                var baloon : Any? = Countly.sharedInstance().remoteConfigValue(forKey:"baloon")
                
                print("baloon value AppDelegate error: \(baloon ?? 0)")
                print("There was an error while fetching Remote Config:\n\(error!.localizedDescription)")
            }
        }
        Countly.sharedInstance().start(with: config)
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        measure {
            // Put the code you want to measure the time of here.
        }
    }

}
