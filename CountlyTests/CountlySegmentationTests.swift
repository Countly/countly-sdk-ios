//
//  CountlyEventTests.swift
//  CountlyTests
//
//  Created by Muhammad Junaid Akram on 25/06/2024.
//  Copyright © 2024 Countly. All rights reserved.
//

import Foundation
import Foundation
import XCTest
@testable import Countly

class CountlySegmentationTests: CountlyBaseTestCase {
    
    func test_Event_Segmentation() {
        let config = createBaseConfig()
        config.requiresConsent = false;
        Countly.sharedInstance().start(with: config);
        
        let segmentation: [String: Any] = [
            "intKey": 42,                       // Int
            "boolKey": true,                    // Bool
            "stringKey": "Hello, World!",       // String
            "arrayKey": ["one", 2, 3.14],       // Array<String, Int, Double>
            "doubleKey": 3.14,                  // Double
            "invalidArrayKey": ["one", 2, Date()], // Array containing non-allowed types
            "invalidValueKey": Date()           // Unsupported type (Date)
        ]
        
        Countly.sharedInstance().recordEvent("EventKey", segmentation: segmentation);
        
        
//        XCTAssertEqual(7, CountlyPersistency.sharedInstance().remainingRequestCount())
        guard let queuedRequests =  CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? [String] else {
            fatalError("Failed to get queuedRequests from CountlyPersistency")
        }
        XCTAssertTrue(queuedRequests[0].contains("begin_session=1"), "Begin session failed.")
    
        guard let recordedEvents =  CountlyPersistency.sharedInstance().value(forKey: "recordedEvents") as? [CountlyEvent] else {
            fatalError("Failed to get recordedEvents from CountlyPersistency")
        }
        XCTAssertEqual(1, recordedEvents.count)
        
        let event = recordedEvents[0]
        XCTAssertEqual("EventKey", event.key, "Recorded event should be with key 'EventKey'")
        XCTAssertEqual(6, event.segmentation.count)
        print(event.segmentation["invalidValueKey"] ?? "nillll");
        XCTAssertNil(event.segmentation["invalidValueKey"])
        let invalidArray: [Any] = event.segmentation["invalidArrayKey"] as! [Any]
        XCTAssertEqual(2, invalidArray.count)
    }
}
