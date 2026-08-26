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
        #if os(macOS)
            // xctest is never a frontmost NSApplication; report active so macOS exercises the
            // same automatic-session paths as the other platforms. See TestAppActivation.
            TestAppActivation.installIfNeeded()
            TestAppActivation.isActive = true
        #endif
        cleanupState()
    }

    /// `CountlyConfig.sdkInternalLimits` is a process-wide object, not per-config, so a test
    /// (or a server config response) that lowers a limit leaves it lowered for every test
    /// that runs afterwards. Restore the defaults from `CountlySDKLimitsConfig`.
    func resetSharedSDKLimits() {
        let limits = CountlyConfig().sdkInternalLimits()
        limits.setMaxKeyLength(128)
        limits.setMaxValueSize(256)
        limits.setMaxValueSizePicture(4096)
        limits.setMaxSegmentationValues(100)
        limits.setMaxBreadcrumbCount(100)
        limits.setMaxStackTraceLineLength(200)
        limits.setMaxStackTraceLinesPerThread(30)
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
        // Restore the shared SDK limits here rather than in setUp: a test legitimately lowers
        // them through its own server config, so resetting beforehand would fight the test
        // itself. Cleaning up afterwards leaves the next test unaffected either way.
        resetSharedSDKLimits()
    }
    
    func cleanupState() {
        // Fully purge any state persisted by a previous test *process*. halt(true) alone does
        // not reliably clear stale persisted requests when the SDK was never started in this
        // process (this is the edge case the historical `testDummy` was added to work around).
        // Starting first wires up persistency/connection-manager and loads the stale state, then
        // halt(true) forces a full reset + empty save — so every test, including ones run in
        // isolation, begins from a clean slate.
        let config = createBaseConfig()
        config.requiresConsent = false
        config.manualSessionHandling = true
        Countly.sharedInstance().start(with: config)
        Countly.sharedInstance().halt(true)
        // Many tests assert absolute request-queue indices ("RQ[0] is begin_session"), so the
        // queue has to start empty. halt(true) clears persisted storage, but a request enqueued
        // by an earlier test can still be sitting in memory, and on watchOS nothing ever drains
        // because URLProtocol interception is unavailable there, so leftovers accumulate.
        CountlyPersistency.sharedInstance().flushQueue()
    }
}


