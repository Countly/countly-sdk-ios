//
//  TestUtils.swift
//  Countly
//
//  Created by Arif Burak Demiray on 3.04.2025.
//  Copyright © 2025 Countly. All rights reserved.
//
import XCTest
import Countly

class TestUtils {
    
    static let commonDeviceId: String = "deviceId"
    static let commonAppKey: String = "appkey"
    static let host: String = "https://testing.count.ly/"
    static let SDK_VERSION = "25.1.1"
    static let SDK_NAME = "objc-native-ios"
    
    static func cleanup() -> Void {
        let config = createBaseConfig()
        config.requiresConsent = false;
        config.manualSessionHandling = true;
        Countly.sharedInstance().start(with: config);
        sleep(1){
            Countly.sharedInstance().halt(true)
            sleep(1){}
        }
    }
    
    static func getCurrentRQ() -> [String]? {
        return CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? [String];
    }
    
    static func getCurrentEQ() -> [CountlyEvent]? {
        return CountlyPersistency.sharedInstance().value(forKey: "recordedEvents") as? [CountlyEvent];
    }
    
    static func sleep(_ seconds: TimeInterval, _ job: () -> Void){
        let exp = XCTestExpectation(description: "Run after \(seconds) seconds")
        let result = XCTWaiter.wait(for: [exp], timeout: seconds)
        if result == XCTWaiter.Result.timedOut {
            job()
        } else {
            XCTFail("Delay interrupted")
        }
    }
    
    static func validateRequest(_ params: [String: Any], _ idx: Int){
        validateRequest(params, idx, { request in })
    }
    
    static func validateRequest(_ params: [String: Any], _ idx: Int, _ customValidator: ([String: Any]) -> Void){
        let requestStr = getCurrentRQ()![idx]
        let request = parseQueryString(requestStr)
        validateRequiredParams(request)
        
        for (key, value) in params {
            let reqValue = request[key]
            
            if let nestedMap = value as? [String: Any] {
                let nestedReqValue = reqValue as! [String: Any]
                for (nestedKey, nestedValue) in nestedMap {
                    XCTAssertEqual("\(String(describing: nestedReqValue[nestedKey]))", "\(nestedValue)")
                }
                XCTAssertEqual(nestedMap.count, nestedReqValue.count)
            } else {
                XCTAssertEqual("\(String(describing: reqValue!))", "\(value)")
            }
        }
        
        customValidator(request)
    }
    
    static func validateEventInRQ(_ eventName: String, _ segmentation: [String: Any], _ idx: Int, _ rqCount: Int, _ eventIdx: Int, _ eventCount: Int) throws {
        let requestStr = getCurrentRQ()![idx]
        let request = parseQueryString(requestStr)
        validateRequiredParams(request)
        
        if let eventsStr = request["events"] as? String,
           let data = eventsStr.data(using: .utf8) {
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: [])
                // Optionally cast it
                if let eventArray = json as? [[String: Any]] {
                    XCTAssertEqual(eventCount, eventArray.count)
                    let event = eventArray[eventIdx]
                    XCTAssertEqual(event["key"] as? String, eventName)
                    XCTAssertEqual(event["count"] as? Int, 1)

                    let sum = (event["sum"] as? Double) ?? 0.0
                    XCTAssertEqual(sum, 0, accuracy: 0.0001)

                    let duration = (event["dur"] as? Double) ?? 0.0
                    XCTAssertEqual(duration, 0, accuracy: 0.0001)
                    
                    if(!segmentation.isEmpty){
                        if let eventSegmentation = event["segmentation"] as? [String: Any] {
                            XCTAssertEqual(eventSegmentation.count, segmentation.count, "Expected segmentation: \(segmentation), got: \(eventSegmentation)")
                            for (key, value) in segmentation {
                                let segValue = eventSegmentation[key]
                                XCTAssertEqual("\(String(describing: segValue!))", "\(value)")
                            }
                        } else {
                            XCTFail("Missing or invalid 'segmentation' in event")
                        }
                    }

                    if let dow = event["dow"] as? Int {
                        XCTAssertTrue((0..<7).contains(dow))
                    } else {
                        XCTFail("Missing or invalid 'dow'")
                    }

                    if let hour = event["hour"] as? Int {
                        XCTAssertTrue((0..<24).contains(hour))
                    } else {
                        XCTFail("Missing or invalid 'hour'")
                    }

                    if let timestamp = event["timestamp"] as? Int {
                        XCTAssertTrue(timestamp >= 0)
                    } else {
                        XCTFail("Missing or invalid 'timestamp'")
                    }

                    // Custom validation function
                    validateId("_CLY_", event["id"] as? String, "Event ID")
                    validateId("_CLY_", event["pvid"] as? String, "Previous View ID")
                    validateId("_CLY_", event["cvid"] as? String, "Current View ID")
                    validateId("_CLY_", event["peid"] as? String, "Previous Event ID")

                }
            } catch {
                XCTFail("Failed to parse JSON: \(error)")
            }
        }
        //XCTFail((request["events"] as? String)!)
        //ModuleEventsTests.validateEventInRQ(
          //  TestUtils.commonDeviceId,
           // eventName,
           // segmentation,
            //1,
            //0.0,
            //0.0,
            //"_CLY_",
            //"_CLY_",
            //"_CLY_",
            //"_CLY_",
            //idx,
            //rqCount,
            //eventIdx,
            //eventCount
       // )
    }
    
    static func validateId(_ id: String?, _ toValidate: String?, _ name: String) {
        if let id = id, id == "_CLY_" {
            if let val = toValidate, !val.isEmpty {
                validateSafeRandomVal(val)
            }
        } else {
            XCTAssertEqual(toValidate, id, "\(name) is not validated")
        }
    }

    static func validateSafeRandomVal(_ val: String) {
        XCTAssertEqual(val.count, 21, "Expected val to be 21 characters")

        let base64Regex = #"^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=|[A-Za-z0-9+/]{4})$"#
        let base64Pattern = try! NSRegularExpression(pattern: base64Regex)

        let timestampStr = String(val.suffix(13))
        let base64Str = String(val.prefix(val.count - 13))

        let matches = base64Pattern.numberOfMatches(in: base64Str, range: NSRange(location: 0, length: base64Str.utf16.count))
        if matches > 0, let timestamp = Int64(timestampStr) {
            let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
            let calendar = Calendar(identifier: .gregorian)

            let dow = calendar.component(.weekday, from: date) - 1  // Sunday=1 → normalize to 0-6
            let hour = calendar.component(.hour, from: date)

            XCTAssertTrue((0..<7).contains(dow), "Day of week is not valid")
            XCTAssertTrue((0..<24).contains(hour), "Hour is not valid")
            XCTAssertTrue(timestamp > 0, "Timestamp is not positive")
        } else {
            XCTFail("No match for \(val)")
        }
    }

    
    static func validateSdkIdentityParams(_ params: [String: Any]) {
          XCTAssertEqual(SDK_VERSION, params["sdk_version"] as? String)
          XCTAssertEqual(SDK_NAME, params["sdk_name"] as? String)
    }
      
      static func validateRequiredParams(_ params: [String: Any]) {
          guard let hour = Int((params["hour"] as? String)!),
                let dow = Int((params["dow"] as? String)!),
                let tz = Int((params["tz"] as? String)!),
                let timestamp = Int((params["timestamp"] as? String)!) else {
              XCTFail("Invalid parameter types")
              return
          }
          
          validateSdkIdentityParams(params)
          XCTAssertEqual(commonDeviceId, params["device_id"] as? String)
          XCTAssertEqual(commonAppKey, params["app_key"] as? String)
          XCTAssertEqual(CountlyDeviceInfo.appVersion(), params["av"] as? String)
          XCTAssertEqual("0", params["t"] as? String)
          XCTAssertTrue(timestamp > 0)
          XCTAssertTrue(hour >= 0 && hour < 24)
          XCTAssertTrue(dow >= 0 && dow < 7)
          XCTAssertTrue(tz >= -720 && tz <= 840)
      }
    
    static func parseQueryString(_ queryString: String) -> [String: Any] {
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
    
    static func compareDictionaries(_ dict1: [String: Any],_ dict2: [String: Any]) -> Bool {
        guard dict1.count == dict2.count else {
            return false
        }
        
        for (key, value) in dict1 {
            guard let otherValue = dict2[key] else {
                return false
            }
            
            if let nestedDict1 = value as? [String: Any], let nestedDict2 = otherValue as? [String: Any] {
                if !compareDictionaries(nestedDict1, nestedDict2) {
                    return false
                }
            } else if "\(value)" != "\(otherValue)" {
                return false
            }
        }
        
        return true
    }
    
    static func createBaseConfig() -> CountlyConfig {
        let config: CountlyConfig = CountlyConfig()
        config.appKey = commonAppKey
        config.deviceID = commonDeviceId
        config.host = host
        config.enableDebug = true
        config.features = [CLYFeature.crashReporting];
        return config
    }
    
}
