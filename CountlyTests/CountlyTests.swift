//
//  CountlyTests.swift
//  CountlyTests
//
//  Created by Muhammad Junaid Akram on 22/12/2023.
//  Copyright © 2023 Alin Radut. All rights reserved.
//

import XCTest
import Countly

final class CountlyTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        let config: CountlyConfig = CountlyConfig()
        config.appKey = "58594c9a3f461ebc000761a68c2146659ef75ea0"
        config.host = "https://master.count.ly/"
        config.enableDebug = true
        config.eventSendThreshold = 0
        
        config.features = [CLYFeature.crashReporting];
        Countly.sharedInstance().start(with: config)

    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testEvent() async throws {
        Countly.sharedInstance().recordEvent("EVENT_NAME");
        // TODO: It is added to wait for completion of request, need to find a correct way to handle this
        try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
    }
    
    func testView() async throws {
        Countly.sharedInstance().views().startView("VIEW_NAME");
        try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
        Countly.sharedInstance().views().stopView(withName: "VIEW_NAME");
        try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
        
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
    }

    func testPerformanceExample() async throws {
        
        // This is an example of a performance test case.
        measure {
//            Countly.sharedInstance().recordEvent("TestEvent");
            // Put the code you want to measure the time of here.
        }
    }

}
