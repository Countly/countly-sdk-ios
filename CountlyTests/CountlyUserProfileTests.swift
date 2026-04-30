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

        // sdkInternalLimits() returns a file-scope static singleton, not a
        // per-config instance — so a test setting setMaxValueSize/setMaxKeyLength
        // mutates state visible to every later test. Reset to defaults here.
        let limits = CountlyConfig().sdkInternalLimits()
        limits.setMaxKeyLength(128)
        limits.setMaxValueSize(256)
        limits.setMaxValueSizePicture(4096)
        limits.setMaxSegmentationValues(100)
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
    
    func test_eventSaveScenario_sessionCallsTriggersSave_M() {
        let config = createBaseConfig()
        config.manualSessionHandling = true;
        config.enableOrientationTracking = false;
        Countly.sharedInstance().start(with: config);
        
        Countly.user().set("beforeBeginSession", value: "1");
        Countly.sharedInstance().beginSession()
        
        Countly.user().set("beforeUpdateSession", value: "1");
        Countly.sharedInstance().updateSession()
        
        Countly.user().set("beforeEndSession", value: "1");
        Countly.sharedInstance().endSession()
        
        XCTAssertEqual(6, CountlyPersistency.sharedInstance().remainingRequestCount())
        guard let queuedRequests =  CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? [String] else {
            fatalError("Failed to get queuedRequests from CountlyPersistency")
        }
        validateCustomUserDetails(request: queuedRequests[0], propertiesToCheck: ["beforeBeginSession": "1"])
        XCTAssertTrue(queuedRequests[1].contains("begin_session=1"), "Begin session failed.")
        validateCustomUserDetails(request: queuedRequests[2], propertiesToCheck: ["beforeUpdateSession": "1"])
        XCTAssertTrue(queuedRequests[3].contains("session_duration=0"), "Update session failed.")
        validateCustomUserDetails(request: queuedRequests[4], propertiesToCheck: ["beforeEndSession": "1"])
        XCTAssertTrue(queuedRequests[5].contains("end_session=1"), "End session failed.")
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
        // $push/$pull/$addToSet always serialize as arrays (post first-write-as-array fix
        // — server-accepted, prevents NSMutableString crash on second-call array merge).
        let userProperties = ["a12345": "My Property",
                              "b12345": ["$inc": 1],
                              "c12345": ["$inc": 10],
                              "d12345": ["$mul": 20],
                              "e12345": ["$max": 100],
                              "f12345": ["$min": 50],
                              "g12345": ["$setOnce": 200],
                              "h12345": ["$addToSet": ["morning"]],
                              "i12345": ["$push": ["morning"]],
                              "j12345": ["$pull": ["morning"]] ]as [String : Any]
        return userProperties;
    }
    
    func setSameData() {
        Countly.user().set("a12345", value: "1");
        Countly.user().set("a12345", value: "2");
        Countly.user().set("a12345", value: "3");
        Countly.user().set("a12345", value: "4");
    }

    // MARK: - New API tests (Android `ModuleUserProfileTests` parity)

    /// Android parity: `setAndSaveValues` (line 40)
    /// `setProperties` with named + custom keys, then `save`, produces a single
    /// user_details request with named fields at top level and custom keys nested.
    func test_setAndSaveValues_namedAndCustomBundled() {
        let config = createBaseConfig()
        config.requiresConsent = false
        config.manualSessionHandling = true
        Countly.sharedInstance().start(with: config)

        let userProperties: [String: Any] = [
            "name": "Test Test",
            "username": "test",
            "email": "test@gmail.com",
            "organization": "Tester",
            "phone": "+1234567890",
            "gender": "M",
            "picture": "http://domain.com/test.png",
            "byear": 2000,
            "key1": "value1",
            "key2": "value2"
        ]

        Countly.user().setProperties(userProperties)
        Countly.user().save()

        guard let rq = TestUtils.getCurrentRQ() else {
            XCTFail("RQ is nil"); return
        }
        guard let userDetailsRequest = rq.first(where: { $0.contains("user_details=") }) else {
            XCTFail("No user_details request in RQ"); return
        }

        let parsed = TestUtils.parseQueryString(userDetailsRequest)
        guard let userDetails = parsed["user_details"] as? [String: Any] else {
            XCTFail("user_details missing or not a dict"); return
        }

        XCTAssertEqual("Test Test", userDetails["name"] as? String)
        XCTAssertEqual("test", userDetails["username"] as? String)
        XCTAssertEqual("test@gmail.com", userDetails["email"] as? String)
        XCTAssertEqual("Tester", userDetails["organization"] as? String)
        XCTAssertEqual("+1234567890", userDetails["phone"] as? String)
        XCTAssertEqual("M", userDetails["gender"] as? String)
        XCTAssertEqual("http://domain.com/test.png", userDetails["picture"] as? String)
        XCTAssertEqual(2000, userDetails["byear"] as? Int)

        guard let custom = userDetails["custom"] as? [String: Any] else {
            XCTFail("custom dict missing"); return
        }
        XCTAssertEqual("value1", custom["key1"] as? String)
        XCTAssertEqual("value2", custom["key2"] as? String)
    }

    /// Android parity: `testClear` (line 289)
    /// After `clear`, `hasUnsyncedChanges` returns false and `save` produces no
    /// user_details request.
    func test_clear_dropsAllPendingChanges() {
        let config = createBaseConfig()
        config.requiresConsent = false
        config.manualSessionHandling = true
        Countly.sharedInstance().start(with: config)

        Countly.user().setProperties([
            "name": "Test",
            "email": "test@example.com",
            "key1": "value1"
        ])
        XCTAssertTrue(Countly.user().hasUnsyncedChanges())

        // `Countly.user().clear()` is ambiguous from Swift due to a duplicated
        // `clear` import (Countly module + bridging-header view of
        // CountlyUserDetails.h). Resolving via runtime selector lookup.
        _ = Countly.user().perform(NSSelectorFromString("clear"))
        XCTAssertFalse(Countly.user().hasUnsyncedChanges())

        let rqBefore = TestUtils.getCurrentRQ()?.count ?? 0
        Countly.user().save()
        let rqAfter = TestUtils.getCurrentRQ()?.count ?? 0
        XCTAssertEqual(rqBefore, rqAfter, "save() after clear() must not enqueue a request")
    }

    /// Android parity: `testCustomModifiers` (line 272)
    /// Multiple `pushUnique` calls on the same key accumulate into an array
    /// (the array-merge fix). Scalar values like `$inc` and `$mul` stay as numbers.
    func test_customModifiers_addToSetAccumulates() {
        let config = createBaseConfig()
        config.requiresConsent = false
        config.manualSessionHandling = true
        Countly.sharedInstance().start(with: config)

        Countly.user().increment(by: "key_inc", value: 1)
        Countly.user().multiply("key_mul", value: 2)
        Countly.user().pushUnique("key_set", value: "test1")
        Countly.user().pushUnique("key_set", value: "test2")
        Countly.user().save()

        guard let rq = TestUtils.getCurrentRQ(),
              let request = rq.first(where: { $0.contains("user_details=") }) else {
            XCTFail("No user_details request"); return
        }

        let parsed = TestUtils.parseQueryString(request)
        guard let userDetails = parsed["user_details"] as? [String: Any],
              let custom = userDetails["custom"] as? [String: Any] else {
            XCTFail("custom missing"); return
        }

        XCTAssertEqual(1, (custom["key_inc"] as? [String: Any])?["$inc"] as? Int)
        XCTAssertEqual(2, (custom["key_mul"] as? [String: Any])?["$mul"] as? Int)

        guard let setEntry = custom["key_set"] as? [String: Any],
              let setArray = setEntry["$addToSet"] as? [Any] else {
            XCTFail("key_set should hold an $addToSet array"); return
        }
        XCTAssertEqual(2, setArray.count)
        XCTAssertEqual("test1", setArray[0] as? String)
        XCTAssertEqual("test2", setArray[1] as? String)
    }

    /// Android parity: `testCustomData` (line 243)
    /// `setProperty` with a custom key lands in the custom dict.
    func test_setProperty_customKeyLandsInCustom() {
        let config = createBaseConfig()
        config.requiresConsent = false
        config.manualSessionHandling = true
        Countly.sharedInstance().start(with: config)

        Countly.user().setProperties(["key1": "value1", "key2": "value2"])
        Countly.user().setProperty("key_prop", value: "value_prop")
        Countly.user().save()

        guard let rq = TestUtils.getCurrentRQ(),
              let request = rq.first(where: { $0.contains("user_details=") }) else {
            XCTFail("No user_details request"); return
        }

        let parsed = TestUtils.parseQueryString(request)
        guard let userDetails = parsed["user_details"] as? [String: Any],
              let custom = userDetails["custom"] as? [String: Any] else {
            XCTFail("custom missing"); return
        }
        XCTAssertEqual("value1", custom["key1"] as? String)
        XCTAssertEqual("value2", custom["key2"] as? String)
        XCTAssertEqual("value_prop", custom["key_prop"] as? String)
    }

    /// Android parity: `internalLimit_testCustomData` (line 441)
    /// With maxKeyLength=10, custom keys longer than 10 are truncated and merge.
    /// Note (Android difference): Android does NOT truncate predefined keys;
    /// iOS doesn't pass predefined names through key truncation either since the
    /// named-field switch matches the full constant.
    func test_internalLimit_truncatesCustomKeys() {
        let config = createBaseConfig()
        config.requiresConsent = false
        config.manualSessionHandling = true
        config.sdkInternalLimits().setMaxKeyLength(10)
        Countly.sharedInstance().start(with: config)

        Countly.user().setProperties([
            "hair_color_id": 4567,
            "hair_color_tone": "bold"
        ])
        Countly.user().setProperty("hair_color", value: "black")
        Countly.user().setProperty("hair_skin_tone", value: "yellow")
        Countly.user().save()

        guard let rq = TestUtils.getCurrentRQ(),
              let request = rq.first(where: { $0.contains("user_details=") }) else {
            XCTFail("No user_details request"); return
        }

        let parsed = TestUtils.parseQueryString(request)
        guard let userDetails = parsed["user_details"] as? [String: Any],
              let custom = userDetails["custom"] as? [String: Any] else {
            XCTFail("custom missing"); return
        }
        XCTAssertEqual("black", custom["hair_color"] as? String,
                       "hair_color_id (truncated to hair_color), then hair_color_tone (also truncated to hair_color), then hair_color literal — last write wins")
        XCTAssertEqual("yellow", custom["hair_skin_"] as? String,
                       "hair_skin_tone truncated to hair_skin_")
    }

    /// Android parity: `internalLimit_testCustomModifiers` (line 468)
    /// With maxKeyLength=10, two `push` calls on different long keys whose
    /// truncated form collides should accumulate into the same array.
    /// This exercises the truncated-key merge fix and the array-merge fix together.
    func test_internalLimit_pushKeysCollideAndAccumulate() {
        let config = createBaseConfig()
        config.requiresConsent = false
        config.manualSessionHandling = true
        config.sdkInternalLimits().setMaxKeyLength(10)
        Countly.sharedInstance().start(with: config)

        Countly.user().push("key_push_reminder", value: "test1")
        Countly.user().push("key_push_rock", value: "test3")
        Countly.user().save()

        guard let rq = TestUtils.getCurrentRQ(),
              let request = rq.first(where: { $0.contains("user_details=") }) else {
            XCTFail("No user_details request"); return
        }

        let parsed = TestUtils.parseQueryString(request)
        guard let userDetails = parsed["user_details"] as? [String: Any],
              let custom = userDetails["custom"] as? [String: Any] else {
            XCTFail("custom missing"); return
        }

        guard let entry = custom["key_push_r"] as? [String: Any],
              let pushArray = entry["$push"] as? [Any] else {
            XCTFail("Expected key_push_r with $push array"); return
        }
        XCTAssertEqual(2, pushArray.count)
        XCTAssertEqual("test1", pushArray[0] as? String)
        XCTAssertEqual("test3", pushArray[1] as? String)
    }

    /// Android parity: `internalLimit_setProperties_maxValueSizePicture` (line 591)
    /// Picture URL uses the picture-specific limit (4096), independent of maxValueSize.
    func test_internalLimit_pictureUsesItsOwnLimit() {
        let config = createBaseConfig()
        config.requiresConsent = false
        config.manualSessionHandling = true
        config.sdkInternalLimits().setMaxValueSize(2)
        Countly.sharedInstance().start(with: config)

        let longURL = String(repeating: "a", count: 6000)
        Countly.user().setProperty("picture", value: longURL)
        Countly.user().save()

        guard let rq = TestUtils.getCurrentRQ(),
              let request = rq.first(where: { $0.contains("user_details=") }) else {
            XCTFail("No user_details request"); return
        }

        let parsed = TestUtils.parseQueryString(request)
        guard let userDetails = parsed["user_details"] as? [String: Any] else {
            XCTFail("user_details missing"); return
        }
        let pic = userDetails["picture"] as? String
        XCTAssertEqual(4096, pic?.count, "picture should be truncated to 4096, not maxValueSize=2")
    }

    /// Android parity: `setUserProperties_null` (line 695)
    /// NSNull values are skipped with a warning; nothing reaches the wire.
    func test_setProperties_nullValuesSkipped() {
        let config = createBaseConfig()
        config.requiresConsent = false
        config.manualSessionHandling = true
        Countly.sharedInstance().start(with: config)

        let rqBefore = TestUtils.getCurrentRQ()?.count ?? 0
        Countly.user().setProperties(["null_key": NSNull()])
        Countly.user().save()
        let rqAfter = TestUtils.getCurrentRQ()?.count ?? 0
        XCTAssertEqual(rqBefore, rqAfter, "NSNull-only setProperties + save should not enqueue a user_details request")
    }

    // MARK: - iOS-specific Android-parity tests (gaps B, C, A, F, E)

    /// Gap B parity: empty string for a named string field serializes as null
    /// (clear-on-server semantics).
    func test_emptyStringForNamedField_serializesAsNull() {
        let config = createBaseConfig()
        config.requiresConsent = false
        config.manualSessionHandling = true
        Countly.sharedInstance().start(with: config)

        Countly.user().setProperties(["name": "Joe"])
        Countly.user().save()
        Countly.user().setProperty("name", value: "")
        Countly.user().save()

        guard let rq = TestUtils.getCurrentRQ() else {
            XCTFail("RQ is nil"); return
        }
        let userDetailsRequests = rq.filter { $0.contains("user_details=") }
        XCTAssertGreaterThanOrEqual(userDetailsRequests.count, 2)

        let lastClearRequest = userDetailsRequests.last!
        let parsed = TestUtils.parseQueryString(lastClearRequest)
        guard let userDetails = parsed["user_details"] as? [String: Any] else {
            XCTFail("user_details missing"); return
        }

        // After serialization, name was empty string — should be NSNull (clear).
        XCTAssertTrue(userDetails["name"] is NSNull,
                      "Empty string should serialize as null. Got: \(String(describing: userDetails["name"]))")
    }

    /// Gap C parity: negative byear serializes as null (clear-on-server).
    func test_negativeBirthYear_serializesAsNull() {
        let config = createBaseConfig()
        config.requiresConsent = false
        config.manualSessionHandling = true
        Countly.sharedInstance().start(with: config)

        Countly.user().setProperty("byear", value: -1)
        Countly.user().save()

        guard let rq = TestUtils.getCurrentRQ(),
              let request = rq.first(where: { $0.contains("user_details=") }) else {
            XCTFail("No user_details request"); return
        }

        let parsed = TestUtils.parseQueryString(request)
        guard let userDetails = parsed["user_details"] as? [String: Any] else {
            XCTFail("user_details missing"); return
        }
        XCTAssertTrue(userDetails["byear"] is NSNull,
                      "Negative byear should serialize as null. Got: \(String(describing: userDetails["byear"]))")
    }

    /// Gap A parity: `picturePath` pointing at a non-existent file is dropped
    /// with a warning; pictureLocalPath remains nil.
    func test_picturePath_nonExistentFile_isDropped() {
        let config = createBaseConfig()
        config.requiresConsent = false
        config.manualSessionHandling = true
        Countly.sharedInstance().start(with: config)

        Countly.user().setProperty("picturePath", value: "/definitely/not/a/real/file.jpg")
        Countly.user().save()

        // No request should fire because pictureLocalPath got nilled out and
        // no other user-detail change happened.
        guard let rq = TestUtils.getCurrentRQ() else {
            XCTFail("RQ is nil"); return
        }
        let userDetailsRequests = rq.filter { $0.contains("user_details=") }
        XCTAssertEqual(0, userDetailsRequests.count,
                       "Non-existent picturePath should not produce a user_details request")
    }

    /// Gap E parity: changing a user property triggers an event-queue flush
    /// (Android `onUserPropertiesChanged`). When events are pending and a
    /// property change occurs, the events get drained into the request queue.
    func test_propertyChange_flushesPendingEvents() {
        let config = createBaseConfig()
        config.requiresConsent = false
        config.manualSessionHandling = true
        Countly.sharedInstance().start(with: config)

        Countly.sharedInstance().recordEvent("eventA")
        Countly.sharedInstance().recordEvent("eventB")

        // Before the property change, events sit in the event queue.
        XCTAssertEqual(2, TestUtils.getCurrentEQ()?.count ?? 0)

        Countly.user().setProperty("level", value: 42)

        // After the property change, the event queue should be drained.
        XCTAssertEqual(0, TestUtils.getCurrentEQ()?.count ?? 0,
                       "Auto-flush should drain the event queue when a user property changes")
    }

    /// Gap D parity: `providedUserProperties` from CountlyConfig is applied
    /// at SDK start and saved automatically.
    func test_providedUserPropertiesAtInit_appliedAndSaved() {
        let config = createBaseConfig()
        config.requiresConsent = false
        config.manualSessionHandling = true
        config.providedUserProperties = [
            "email": "init@example.com",
            "favorite_color": "blue"
        ]
        Countly.sharedInstance().start(with: config)

        guard let rq = TestUtils.getCurrentRQ(),
              let request = rq.first(where: { $0.contains("user_details=") }) else {
            XCTFail("Expected a user_details request from providedUserProperties"); return
        }

        let parsed = TestUtils.parseQueryString(request)
        guard let userDetails = parsed["user_details"] as? [String: Any] else {
            XCTFail("user_details missing"); return
        }
        XCTAssertEqual("init@example.com", userDetails["email"] as? String)
        let custom = userDetails["custom"] as? [String: Any]
        XCTAssertEqual("blue", custom?["favorite_color"] as? String)
    }
}



