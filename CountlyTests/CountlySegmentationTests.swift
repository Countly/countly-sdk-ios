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
        cleanupState()
        let config = createBaseConfig()
        config.requiresConsent = false;
        Countly.sharedInstance().start(with: config)
        
        let segmentation: [String: Any] = [
            "intKey": 42,                       // Int
            "boolKey": true,                    // Bool
            "stringKey": "Hello, World!",       // String
            "arrayKey": ["one", 2, 3.14],       // Array<String, Int, Double>
            "intArrayKey": [1, 2, 3],              // Array<Int>
            "boolArrayKey": [true, false, true],   // Array<Bool>
            "doubleArrayKey": [1.1, 2.2, 3.3],    // Array<Double>
            "stinrgArrayKey": ["one", "two", "three"], // Array<String>
            "doubleKey": 3.14,                  // Double
            "invalidArrayKey": ["one", 2, Date()], // Array containing non-allowed types
            "invalidValueKey": Date()           // Unsupported type (Date)
        ]

        Countly.sharedInstance().recordEvent("EventKey", segmentation: segmentation)
        Countly.sharedInstance().views().startView("exView", segmentation: segmentation)
        Countly.sharedInstance().views().stopAllViews(segmentation)

        
        // get request queue
        guard let queuedRequests =  CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? [String] else {
            fatalError("Failed to get queuedRequests from CountlyPersistency")
        }
        XCTAssertTrue(queuedRequests[0].contains("begin_session=1"), "Begin session failed.")
    
        // get event queue
        guard let recordedEvents =  CountlyPersistency.sharedInstance().value(forKey: "recordedEvents") as? [CountlyEvent] else {
            fatalError("Failed to get recordedEvents from CountlyPersistency")
        }
        // two views and one event
        XCTAssertEqual(3, recordedEvents.count)
        
        let event = recordedEvents[0]
        XCTAssertEqual("EventKey", event.key, "Recorded event should be with key 'EventKey'")
        
        // One key removed
        XCTAssertEqual(10, event.segmentation.count)
        checkSegmentations(event: event)

        // Check views
        let event2 = recordedEvents[1]
        XCTAssertEqual("[CLY]_view", event2.key, "Recorded event should be with key 'EventKey'")
        XCTAssertEqual(14, event2.segmentation.count)
        checkSegmentations(event: event2)
        
        let event3 = recordedEvents[2]
        XCTAssertEqual("[CLY]_view", event3.key, "Recorded event should be with key 'EventKey'")
        XCTAssertEqual(12, event3.segmentation.count)
        checkSegmentations(event: event3)
        
        func checkSegmentations(event: CountlyEvent) {
            // Primitive types
            XCTAssertEqual(42, event.segmentation["intKey"] as! Int, "intKey issue")
            XCTAssertEqual(true, event.segmentation["boolKey"] as! Bool, "boolKey issue")
            XCTAssertEqual("Hello, World!", event.segmentation["stringKey"] as! String, "stringKey issue")
            XCTAssertEqual(3.14, event.segmentation["doubleKey"] as! Double, "doubleKey issue")
            
            // Array values are kept
            let arrayKey: [Any] = event.segmentation["arrayKey"] as! [Any]
            XCTAssertEqual("one", arrayKey[0] as! String )
            XCTAssertEqual(2, arrayKey[1] as! Int )
            XCTAssertEqual(3.14, arrayKey[2] as! Double )
            XCTAssertEqual(3, arrayKey.count)
            
            // Int Array values are kept
            let intArray: [Int] = event.segmentation["intArrayKey"] as! [Int]
            XCTAssertEqual(1, intArray[0] )
            XCTAssertEqual(2, intArray[1] )
            XCTAssertEqual(3, intArray[2] )
            XCTAssertEqual(3, intArray.count)
            
            // Double Array values are kept
            let dbArray: [Double] = event.segmentation["doubleArrayKey"] as! [Double]
            XCTAssertEqual(1.1, dbArray[0] )
            XCTAssertEqual(2.2, dbArray[1] )
            XCTAssertEqual(3.3, dbArray[2] )
            XCTAssertEqual(3, dbArray.count)
            
            // Bool Array values are kept
            let boolArray: [Bool] = event.segmentation["boolArrayKey"] as! [Bool]
            XCTAssertEqual(true, boolArray[0] )
            XCTAssertEqual(false, boolArray[1] )
            XCTAssertEqual(true, boolArray[2] )
            XCTAssertEqual(3, boolArray.count)
            
            // String Array values are kept
            let stringArray: [String] = event.segmentation["stinrgArrayKey"] as! [String]
            XCTAssertEqual("one", stringArray[0] )
            XCTAssertEqual("two", stringArray[1] )
            XCTAssertEqual("three", stringArray[2] )
            XCTAssertEqual(3, stringArray.count)

            // Date (unsupported type) is removed
            let invalidArray: [Any] = event.segmentation["invalidArrayKey"] as! [Any]
            XCTAssertEqual("one", invalidArray[0] as! String )
            XCTAssertEqual(2, invalidArray[1] as! Int )
            XCTAssertEqual(2, invalidArray.count)
            
            // Unsupported type removed
            XCTAssertNil(event.segmentation["invalidValueKey"])
            
        }
    }
}
