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
    var host: String = "https://testing.count.ly/"
    
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
        // Reset view tracking state BEFORE halt — sharedInstance() returns nil after halt.
        // Use KVC to clear internal state directly since stopAllViews checks consent
        // and may be a no-op if previous test required consent.
        if let viewTracking = CountlyViewTrackingInternal.sharedInstance() {
            viewTracking.setValue(NSMutableDictionary(), forKey: "viewDataDictionary")
            viewTracking.setValue(nil, forKey: "currentViewID")
            viewTracking.setValue(nil, forKey: "currentViewName")
            viewTracking.setValue(nil, forKey: "previousViewID")
            viewTracking.setValue(nil, forKey: "previousViewName")
            viewTracking.setValue(false, forKey: "isAutoViewTrackingActive")
            viewTracking.resetFirstView()
        }
        CountlyHealthTracker.sharedInstance()?.resetState()

        Countly.sharedInstance().halt(true)
        // halt(true) calls removePersistentDomainForName which doesn't work in xctest
        // environment (different bundle ID), so clear SDK keys manually
        let sdkKeys = [
            "kCountlyServerConfigPersistencyKey",
            "kCountlyHealthCheckStatePersistencyKey",
            "kCountlyQueuedRequestsPersistencyKey",
            "kCountlyStartedEventsPersistencyKey",
            "kCountlyStoredDeviceIDKey",
            "kCountlyStoredNSUUIDKey",
            "kCountlyStarRatingStatusKey",
            "kCountlyRemoteConfigKey",
            "kCountlyIsCustomDeviceIDKey",
            "kCountlyNotificationPermissionKey",
            "kCountlyWatchParentDeviceIDKey"
        ]
        for key in sdkKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.synchronize()
    }
}


