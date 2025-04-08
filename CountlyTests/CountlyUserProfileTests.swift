//
//  CountlyUserProfileTests.swift
//  CountlyTests
//
//  Created by Muhammad Junaid Akram on 29/05/2024.
//  Copyright © 2024 Countly. All rights reserved.
//

import Foundation

import XCTest
@testable import Countly

// M:Manual Sessions enabled
// A:Automatic sessions enabled
// H:Hybrid Sessions enabled
// CR:Consent Required
// CNR:Consent not Required
// CG:Consent given (All)
// CNG:Consent not given (All)

class CountlyUserProfileTests: CountlyBaseTestCase {
    
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
    // Run this test first if you are facing cache not clear or instances are not reset properly
    // This is a dummy test to cover the edge case clear the cache when SDK is not initialized
    func testDummy() {
        let config = createBaseConfig()
        config.requiresConsent = false;
        config.manualSessionHandling = true;
        Countly.sharedInstance().start(with: config);
        Countly.sharedInstance().halt(true)
    }
    
    func test_200_CNR_A() {
        let config = createBaseConfig()
        config.requiresConsent = false;
        Countly.sharedInstance().start(with: config);
        sendUserProperty()
        setUserData()
        XCTAssertEqual(2, CountlyPersistency.sharedInstance().remainingRequestCount())
        if let queuedRequests = CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? [String] {
            XCTAssertTrue(queuedRequests[0].contains("begin_session=1"), "Begin session failed.")
            validateUserDetails(request: queuedRequests[1]);
        }
    }
    
    func test_201_CR_CG_A() {
        let config = createBaseConfig()
        config.requiresConsent = true;
        config.enableAllConsents = true;
        Countly.sharedInstance().start(with: config);
        sendUserProperty()
        setUserData()
        XCTAssertEqual(3, CountlyPersistency.sharedInstance().remainingRequestCount())
        if let queuedRequests = CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? [String] {
            XCTAssertTrue(queuedRequests[0].contains("begin_session=1"), "Begin session failed.")
            XCTAssertTrue(queuedRequests[1].contains("consent="), "Set all consents failed.")
            validateUserDetails(request: queuedRequests[2]);
        }
    }
    
    func test_202_CR_CNG_A() {
        let config = createBaseConfig()
        config.requiresConsent = true;
        config.enableAllConsents = false;
        
        Countly.sharedInstance().start(with: config);
        sendUserProperty()
        setUserData()
        XCTAssertEqual(2, CountlyPersistency.sharedInstance().remainingRequestCount()) // consents, location
    }
    
    func test_203_CNR_A() {
        let config = createBaseConfig()
        config.requiresConsent = false;
        Countly.sharedInstance().start(with: config);
        
        Countly.sharedInstance().recordEvent("A");
        Countly.sharedInstance().recordEvent("B");
        
        setSameData()
        Countly.sharedInstance().recordEvent("C");
        setSameData()
        Countly.sharedInstance().recordEvent("D");
        setSameData()
        Countly.sharedInstance().recordEvent("E");
        
        XCTAssertEqual(7, CountlyPersistency.sharedInstance().remainingRequestCount())
        guard let queuedRequests =  CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? [String] else {
            fatalError("Failed to get queuedRequests from CountlyPersistency")
        }
        XCTAssertTrue(queuedRequests[0].contains("begin_session=1"), "Begin session failed.")
        validateEvents(request: queuedRequests[1], keysToCheck: ["A","B"])
        validateCustomUserDetails(request: queuedRequests[2], propertiesToCheck: ["a12345": 4])
        validateEvents(request: queuedRequests[3], keysToCheck: ["C"])
        validateCustomUserDetails(request: queuedRequests[4], propertiesToCheck: ["a12345": 4])
        validateEvents(request: queuedRequests[5], keysToCheck: ["D"])
        validateCustomUserDetails(request: queuedRequests[6], propertiesToCheck: ["a12345": 4])
        
        guard let recordedEvents =  CountlyPersistency.sharedInstance().value(forKey: "recordedEvents") as? [CountlyEvent] else {
            fatalError("Failed to get recordedEvents from CountlyPersistency")
        }
        XCTAssertEqual(1, recordedEvents.count)
        
        XCTAssertEqual("E", recordedEvents[0].key, "Recorded event should be with key 'E'")
        
        
    }
    
    func test_205_CR_CG_A() {
        let config = createBaseConfig()
        config.requiresConsent = true;
        config.enableAllConsents = true;
        Countly.sharedInstance().start(with: config);
        
        Countly.sharedInstance().recordEvent("A");
        Countly.sharedInstance().recordEvent("B");
        
        setSameData()
        Countly.sharedInstance().recordEvent("C");
        setSameData()
        Countly.sharedInstance().recordEvent("D");
        setSameData()
        Countly.sharedInstance().recordEvent("E");
        
        XCTAssertEqual(8, CountlyPersistency.sharedInstance().remainingRequestCount())
        guard let queuedRequests =  CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? [String] else {
            fatalError("Failed to get queuedRequests from CountlyPersistency")
        }
        XCTAssertTrue(queuedRequests[0].contains("begin_session=1"), "Begin session failed.")
        XCTAssertTrue(queuedRequests[1].contains("consent="), "Set all consets failed.")
        validateEvents(request: queuedRequests[2], keysToCheck: ["A","B"])
        validateCustomUserDetails(request: queuedRequests[3], propertiesToCheck: ["a12345": 4])
        validateEvents(request: queuedRequests[4], keysToCheck: ["C"])
        validateCustomUserDetails(request: queuedRequests[5], propertiesToCheck: ["a12345": 4])
        validateEvents(request: queuedRequests[6], keysToCheck: ["D"])
        validateCustomUserDetails(request: queuedRequests[7], propertiesToCheck: ["a12345": 4])
    }
    
    func test_206_CR_CNG_A() {
        let config = createBaseConfig()
        config.requiresConsent = true;
        Countly.sharedInstance().start(with: config);
        
        Countly.sharedInstance().recordEvent("A");
        Countly.sharedInstance().recordEvent("B");
        
        setSameData()
        Countly.sharedInstance().recordEvent("C");
        setSameData()
        Countly.sharedInstance().recordEvent("D");
        setSameData()
        Countly.sharedInstance().recordEvent("E");
        XCTAssertEqual(2, CountlyPersistency.sharedInstance().remainingRequestCount()) // consents, location
    }
    
    func test_207_CNR_M() {
        let config = createBaseConfig()
        config.requiresConsent = false;
        config.manualSessionHandling = true;
        Countly.sharedInstance().start(with: config);
        Countly.sharedInstance().beginSession()
        
        Countly.sharedInstance().recordEvent("A");
        Countly.sharedInstance().recordEvent("B");
        
        setSameData()
        Countly.sharedInstance().endSession()
        
        Countly.sharedInstance().recordEvent("C");
        setUserData()
        Countly.sharedInstance().endSession()
        
        Countly.sharedInstance().changeDeviceID(withMerge: "merge_id")
        setSameData()
        Countly.sharedInstance().changeDeviceIDWithoutMerge("non_merge_id")
        setSameData()
        Countly.sharedInstance().recordEvent("D");
        
        
        XCTAssertEqual(9, CountlyPersistency.sharedInstance().remainingRequestCount())
        guard let queuedRequests =  CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? [String] else {
            fatalError("Failed to get queuedRequests from CountlyPersistency")
        }
        XCTAssertTrue(queuedRequests[0].contains("begin_session=1"), "Begin session failed.")
        validateEvents(request: queuedRequests[1], keysToCheck: ["A","B"])
        validateCustomUserDetails(request: queuedRequests[2], propertiesToCheck: ["a12345": 4])
        XCTAssertTrue(queuedRequests[3].contains("end_session=1"), "End session failed.")
        validateEvents(request: queuedRequests[4], keysToCheck: ["C"])
        validateCustomUserDetails(request: queuedRequests[5], propertiesToCheck: getUserDataMap())
        XCTAssertTrue(queuedRequests[6].contains("device_id=merge_id"), "Merge device id failed")
        validateCustomUserDetails(request: queuedRequests[7], propertiesToCheck: ["a12345": 4])
        XCTAssertTrue(queuedRequests[8].contains("device_id=non_merge_id"), "Non Merge device id failed")
        validateCustomUserDetails(request: queuedRequests[8], propertiesToCheck: ["a12345": 4])
        
        guard let recordedEvents =  CountlyPersistency.sharedInstance().value(forKey: "recordedEvents") as? [CountlyEvent] else {
            fatalError("Failed to get recordedEvents from CountlyPersistency")
        }
        XCTAssertEqual(1, recordedEvents.count)
        
        XCTAssertEqual("D", recordedEvents[0].key, "Recorded event should be with key 'D'")
    }
    
    func test_208_CR_CG_M() {
        let config = createBaseConfig()
        config.requiresConsent = true;
        config.enableAllConsents = true;
        config.manualSessionHandling = true;
        Countly.sharedInstance().start(with: config);
        Countly.sharedInstance().beginSession()
        
        Countly.sharedInstance().recordEvent("A");
        Countly.sharedInstance().recordEvent("B");
        
        setSameData()
        Countly.sharedInstance().endSession()
        
        Countly.sharedInstance().recordEvent("C");
        setUserData()
        Countly.sharedInstance().endSession()
        
        Countly.sharedInstance().changeDeviceID(withMerge: "merge_id")
        setSameData()
        Countly.sharedInstance().changeDeviceIDWithoutMerge("non_merge_id")
        
        // Give all consent again here, else features will not work because device id without merge change has cancelled all consents
        setSameData()
        Countly.sharedInstance().recordEvent("D");
        
        
        XCTAssertEqual(10, CountlyPersistency.sharedInstance().remainingRequestCount())
        guard let queuedRequests =  CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? [String] else {
            fatalError("Failed to get queuedRequests from CountlyPersistency")
        }
        XCTAssertTrue(queuedRequests[0].contains("consent="), "Set all consets failed.")
        XCTAssertTrue(queuedRequests[1].contains("begin_session=1"), "Begin session failed.")
        
        validateEvents(request: queuedRequests[2], keysToCheck: ["A","B"])
        validateCustomUserDetails(request: queuedRequests[3], propertiesToCheck: ["a12345": 4])
        XCTAssertTrue(queuedRequests[4].contains("end_session=1"), "End session failed.")
        validateEvents(request: queuedRequests[5], keysToCheck: ["C"])
        validateCustomUserDetails(request: queuedRequests[6], propertiesToCheck: getUserDataMap())
        XCTAssertTrue(queuedRequests[7].contains("device_id=merge_id"), "Merge device id failed")
        validateCustomUserDetails(request: queuedRequests[8], propertiesToCheck: ["a12345": 4])
        XCTAssertTrue(queuedRequests[9].contains("location="), "Empty location should send in this case.")
        
//        XCTAssertTrue(queuedRequests[9].contains("device_id=non_merge_id"), "Non Merge device id failed")
//        validateCustomUserDetails(request: queuedRequests[9], propertiesToCheck: ["a12345": 4])
    }
    
    func test_209_CR_CNG_M() {
        let config = createBaseConfig()
        config.requiresConsent = true;
        config.manualSessionHandling = true;
        Countly.sharedInstance().start(with: config);
        Countly.sharedInstance().beginSession()
        
        Countly.sharedInstance().recordEvent("A");
        Countly.sharedInstance().recordEvent("B");
        
        setSameData()
        Countly.sharedInstance().endSession()
        
        Countly.sharedInstance().recordEvent("C");
        setUserData()
        Countly.sharedInstance().endSession()
        
        Countly.sharedInstance().changeDeviceID(withMerge: "merge_id")
        setSameData()
        Countly.sharedInstance().changeDeviceIDWithoutMerge("non_merge_id")
        setSameData()
        Countly.sharedInstance().recordEvent("D");
        
        
        XCTAssertEqual(3, CountlyPersistency.sharedInstance().remainingRequestCount()) // consents, location, device id change
        guard let queuedRequests =  CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? [String] else {
            fatalError("Failed to get queuedRequests from CountlyPersistency")
        }
        XCTAssertTrue(queuedRequests[2].contains("device_id=merge_id"), "Merge device id failed")
        XCTAssertTrue(queuedRequests[2].contains("old_device_id="), "Merge device id failed")
    }
    
    // Test case for Consent Not Required with Manual Sessions enabled
    func test_210_CNR_M() {
        let config = createBaseConfig()
        config.requiresConsent = false;
        config.manualSessionHandling = true
        config.updateSessionPeriod = 5.0;
        Countly.sharedInstance().start(with: config);
        setUserData()
        
        // Create an expectation for the timer
        let expectation = self.expectation(description: "Wait for timer")
        
        // Schedule a block to fulfill the expectation after 6 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            expectation.fulfill()
        }
        
        // Wait for the expectation to be fulfilled, with a timeout
        waitForExpectations(timeout: 10, handler: nil)
        
        // After waiting, perform the assertions
        
        XCTAssertEqual(1, CountlyPersistency.sharedInstance().remainingRequestCount())
        guard let queuedRequests =  CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? [String] else {
            fatalError("Failed to get queuedRequests from CountlyPersistency")
        }
        
        validateCustomUserDetails(request: queuedRequests[0], propertiesToCheck: getUserDataMap())
    }
    
    func validateEvents(request: String, keysToCheck: [String]) {
        let parsedRequest = TestUtils.parseQueryString(request)
        let events = parsedRequest["events"];
        XCTAssertNotNil(events, "events are nil");
        if((events) != nil) {
            guard let jsonData = (events as! String).data(using: .utf8) else {
                fatalError("Failed to convert JSON string to Data")
            }
            do {
                // Decode JSON data into an array of CountlyEventStruct
                let countlyEvents = try JSONDecoder().decode([CountlyEventStruct].self, from: jsonData)
                let eventKeysSet = Set(countlyEvents.map { $0.key })
                
                XCTAssertNotEqual(0, countlyEvents.count, "No events found")
                XCTAssertEqual(keysToCheck.count, eventKeysSet.count, "Events count is not matched")
                
                for key in keysToCheck {
                    XCTAssertTrue(eventKeysSet.contains(key), "Event with key \(key) does not exist in countlyEvents")
                }
            } catch {
                if let decodingError = error as? DecodingError {
                    switch decodingError {
                    case .dataCorrupted(let context):
                        print("Data corrupted: \(context.debugDescription)")
                    case .keyNotFound(let key, let context):
                        print("Key not found: \(key.stringValue) in context: \(context.debugDescription)")
                    case .typeMismatch(let type, let context):
                        print("Type mismatch: \(type) in context: \(context.debugDescription)")
                    case .valueNotFound(let value, let context):
                        print("Value not found: \(value) in context: \(context.debugDescription)")
                    @unknown default:
                        print("Unknown decoding error")
                    }
                } else {
                    print("Failed to decode JSON: \(error.localizedDescription)")
                }
            }
        }
    }
    
    
    func validateCustomUserDetails(request: String, propertiesToCheck: [String: Any]) {
        let parsedRequest = TestUtils.parseQueryString(request)
        let userDetails = parsedRequest["user_details"];
        XCTAssertNotNil(userDetails, "user details are nil");
        if((userDetails) != nil) {
            guard let customUserDetails = (userDetails as! [String: Any])["custom"] else {
                fatalError("Failed to get custom user details")
            }
            do {
                // Decode JSON data into an array of CountlyEventStruct
                let custom = customUserDetails as! [String: Any]
                
                XCTAssertNotEqual(0, custom.count, "No custom properties found")
                XCTAssertEqual(propertiesToCheck.count, custom.count, "Custom propeties count is not matched")
                for (key, value) in propertiesToCheck {
                    let customValue = custom[key]
                    XCTAssertNotNil(customValue, "Key \(key) not found in custom properties")
                    
                    // Check if both values are dictionaries
                    if let customDict = customValue as? [String: Any], let checkDict = value as? [String: Any] {
                        // Check if the dictionaries are equal
                        XCTAssertTrue(TestUtils.compareDictionaries(customDict, checkDict),"Value for key \(key) does not match. Expected: \(checkDict), Found: \(customDict)")
                        
                    } else { // Convert to string for comparison
                        XCTAssertNotEqual("\(customValue)", "\(value)","Value for key \(key) does not match. Expected: \(value), Found: \(customValue)")
                    }
                }
                
            } catch {
                if let decodingError = error as? DecodingError {
                    switch decodingError {
                    case .dataCorrupted(let context):
                        print("Data corrupted: \(context.debugDescription)")
                    case .keyNotFound(let key, let context):
                        print("Key not found: \(key.stringValue) in context: \(context.debugDescription)")
                    case .typeMismatch(let type, let context):
                        print("Type mismatch: \(type) in context: \(context.debugDescription)")
                    case .valueNotFound(let value, let context):
                        print("Value not found: \(value) in context: \(context.debugDescription)")
                    @unknown default:
                        print("Unknown decoding error")
                    }
                } else {
                    print("Failed to decode JSON: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func validateUserDetails(request: String) {
        let parsedRequest = TestUtils.parseQueryString(request)
        let userDetails = parsedRequest["user_details"];
        XCTAssertNotNil(userDetails, "user details is nil");
        let userDetailsMap =  userDetails as! [String: Any]
        if((userDetails) != nil) {
            XCTAssertNotNil(userDetailsMap["byear"], "byear should not be nil")
            XCTAssertNotNil(userDetailsMap["email"], "email should not be nil")
            XCTAssertNotNil(userDetailsMap["gender"], "gender should not be nil")
            XCTAssertNotNil(userDetailsMap["gender"], "gender should not be nil")
            XCTAssertNotNil(userDetailsMap["organization"], "organization should not be nil")
            XCTAssertNotNil(userDetailsMap["phone"], "phone should not be nil")
            XCTAssertNotNil(userDetailsMap["picture"], "picture should not be nil")
            XCTAssertNotNil(userDetailsMap["username"], "username should not be nil")
            
            XCTAssertEqual(1970, userDetailsMap["byear"] as! Int, "byear should be 1970")
            
            XCTAssertEqual("john@doe.com", userDetailsMap["email"] as! String, "email should be john@doe.com")
            XCTAssertEqual("M", userDetailsMap["gender"] as! String, "gender should be Male")
            XCTAssertEqual("John Doe", userDetailsMap["name"] as! String, "name should be John Doe")
            XCTAssertEqual("United Nations", userDetailsMap["organization"] as! String, "organization should be United Nations")
            XCTAssertEqual("+0123456789", userDetailsMap["phone"] as! String, "phone should be +0123456789")
            XCTAssertEqual("https://s12.postimg.org/qji0724gd/988a10da33b57631caa7ee8e2b5a9036.jpg", userDetailsMap["picture"] as! String, "picture should be https://s12.postimg.org/qji0724gd/988a10da33b57631caa7ee8e2b5a9036.jpg")
            XCTAssertEqual("johndoe", userDetailsMap["username"] as! String, "username should be johndoe")
        }
    }
    
    func sendUserProperty() {
        //default properties
        Countly.user().name = "John Doe" as CountlyUserDetailsNullableString
        Countly.user().username = "johndoe" as CountlyUserDetailsNullableString
        Countly.user().email = "john@doe.com" as CountlyUserDetailsNullableString
        Countly.user().birthYear = 1970 as CountlyUserDetailsNullableNumber
        Countly.user().organization = "United Nations" as CountlyUserDetailsNullableString
        Countly.user().gender = "M" as CountlyUserDetailsNullableString
        Countly.user().phone = "+0123456789" as CountlyUserDetailsNullableString
        
        //profile photo
        Countly.user().pictureURL = "https://s12.postimg.org/qji0724gd/988a10da33b57631caa7ee8e2b5a9036.jpg" as CountlyUserDetailsNullableString
        //or local image on the device
        Countly.user().pictureLocalPath = "" as any CountlyUserDetailsNullableString
        Countly.user().save()
    }
    
    func setUserData() {
        Countly.user().set("a12345", value: "My Property");
        Countly.user().increment("b12345");
        Countly.user().increment(by: "c12345", value: 10);
        Countly.user().multiply("d12345", value: 20);
        Countly.user().max("e12345", value: 100);
        Countly.user().min("f12345", value: 50);
        Countly.user().setOnce("g12345", value: "200");
        Countly.user().pushUnique("h12345", value: "morning");
        Countly.user().push("i12345", value: "morning");
        Countly.user().pull("j12345", value: "morning");
    }
    
    func getUserDataMap()-> [String: Any]{
        let userProperties = ["a12345": "My Property",
                              "b12345": ["$inc": 1],
                              "c12345": ["$inc": 10],
                              "d12345": ["$mul": 20],
                              "e12345": ["$max": 100],
                              "f12345": ["$min": 50],
                              "g12345": ["$setOnce": 200],
                              "h12345": ["$addToSet": "morning"],
                              "i12345": ["$push": "morning"],
                              "j12345": ["$pull": "morning"] ]as [String : Any]
        return userProperties;
    }
    
    func setSameData() {
        Countly.user().set("a12345", value: "1");
        Countly.user().set("a12345", value: "2");
        Countly.user().set("a12345", value: "3");
        Countly.user().set("a12345", value: "4");
    }
    
}



