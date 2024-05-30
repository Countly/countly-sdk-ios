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
            XCTAssertTrue(queuedRequests[1].contains("consent="), "Set all consets failed.")
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
        XCTAssertEqual(0, CountlyPersistency.sharedInstance().remainingRequestCount())
    }
    
    func test_203_CNR_A_events() {
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
        validateEvents(request: queuedRequests[1], keysToCheck: ["A","B"]);
        validateCustomUserDetails(request: queuedRequests[2], propertiesToCheck: ["a12345": 4])
        
    }
    
    func validateEvents(request: String, keysToCheck: [String]) {
        let parsedRequest = parseQueryString(request)
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
        let parsedRequest = parseQueryString(request)
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
                           XCTAssertTrue(NSDictionary(dictionary: customDict).isEqual(to: checkDict),"Value for key \(key) does not match. Expected: \(checkDict), Found: \(customDict)")
                        
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
        let parsedRequest = parseQueryString(request)
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
    
    func setSameData() {
        Countly.user().set("a12345", value: "1");
        Countly.user().set("a12345", value: "2");
        Countly.user().set("a12345", value: "3");
        Countly.user().set("a12345", value: "4");
    }
    
}



