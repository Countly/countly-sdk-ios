//
//  CountlyViewTrackingTests.swift
//  CountlyTests
//
//  Copyright © 2024 Countly. All rights reserved.
//

import XCTest
@testable import Countly

class CountlyViewTrackingTests: CountlyBaseTestCase {
    
    func checkPersistentValues() {
        let countlyPersistency =  CountlyPersistency.sharedInstance()
        if(countlyPersistency != nil) {
            if let queuedRequests = CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? NSMutableArray,
               let recordedEvents =  CountlyPersistency.sharedInstance().value(forKey: "recordedEvents") as? NSMutableArray,
               let startedEvents =  CountlyPersistency.sharedInstance().value(forKey: "startedEvents") as? NSMutableDictionary,
               let isQueueBeingModified =  CountlyPersistency.sharedInstance().value(forKey: "isQueueBeingModified") as? Bool {
                print("Successfully access private properties.")
                
                
            }
            else {
                print("Failed to access private properties.")
            }
        }
        
    }
    
    func testViewForegroundBackground() {
        let config = createBaseConfig()
        // No Device ID provided during init
        Countly.sharedInstance().start(with: config)
        
        let viewID = Countly.sharedInstance().views().startAutoStoppedView("TestAutoStoppedView")
        
        let pauseViewExpectation = XCTestExpectation(description: "Wait for pause view")
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            Countly.sharedInstance().views().pauseView(withID: viewID)
            pauseViewExpectation.fulfill()
        }
        
        let resumeViewExpectation = XCTestExpectation(description: "Wait for resume view")
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) { // Delayed by 10 seconds
            Countly.sharedInstance().views().resumeView(withID: viewID)
            resumeViewExpectation.fulfill()
        }
        
        let bgExpectation = XCTestExpectation(description: "Wait for background notification")
        DispatchQueue.global().asyncAfter(deadline: .now() + 15) { // Delayed by 15 seconds
            NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
            bgExpectation.fulfill()
        }
        
        let fgExpectation = XCTestExpectation(description: "Wait for active notification")
        DispatchQueue.global().asyncAfter(deadline: .now() + 20) { // Delayed by 20 seconds
            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
            fgExpectation.fulfill()
        }
        
        let bgExpectation1 = XCTestExpectation(description: "Wait for second background notification")
        DispatchQueue.global().asyncAfter(deadline: .now() + 25) { // Delayed by 25 seconds
            NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
            bgExpectation1.fulfill()
        }
        
        let fgExpectation1 = XCTestExpectation(description: "Wait for second active notification")
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) { // Delayed by 30 seconds
            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
            fgExpectation1.fulfill()
        }
        
        // Wait for all expectations or timeout
        wait(for: [pauseViewExpectation, resumeViewExpectation, bgExpectation, fgExpectation, bgExpectation1, fgExpectation1], timeout: 35)
        
        let viewID1 =  Countly.sharedInstance().views().startView("startView")
        
        checkPersistentValues()
        Countly.sharedInstance().views().stopAllViews(nil);
        
        checkPersistentValues()
    }

    
    func testViewTrackingInit_CNR_AV() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        let viewID = Countly.sharedInstance().views().startAutoStoppedView("TestAutoStoppedView")
        
        XCTAssertNotNil(viewID, "Auto-stopped view should be started successfully.")
        
        let pauseViewExpectation = XCTestExpectation(description: "Wait for pause view")
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            Countly.sharedInstance().views().pauseView(withID: viewID)
            pauseViewExpectation.fulfill()
        }
        
        wait(for: [pauseViewExpectation], timeout: 10)
    }
    
    func testViewTrackingInit_CR_CNG_AV() throws {
        let config = createBaseConfig()
        config.requiresConsent = true
        Countly.sharedInstance().start(with: config)
        
        let viewID = Countly.sharedInstance().views().startAutoStoppedView("TestAutoStoppedViewWithoutConsent")
        XCTAssertNil(viewID, "Auto-stopped view should not be started when consent is not given.")
    }
    
    func testViewTrackingInit_CR_CGV_AV() throws {
        let config = createBaseConfig()
        config.requiresConsent = true
        config.consents = [CLYConsent.viewTracking]
        Countly.sharedInstance().start(with: config)
        
        let viewID = Countly.sharedInstance().views().startAutoStoppedView("TestAutoStoppedViewWithConsent")
        XCTAssertNotNil(viewID, "Auto-stopped view should be started when view tracking consent is given.")
    }
    
    func testManualViewTrackingInit_CNR_MV() throws {
        let config = createBaseConfig()
        config.manualSessionHandling = true
        Countly.sharedInstance().start(with: config)
        
        let viewID = Countly.sharedInstance().views().startView("TestManualView")
        XCTAssertNotNil(viewID, "Manual view should be started successfully.")
        
        Countly.sharedInstance().views().stopView(withID: viewID)
    }
    
    func testManualViewTrackingInit_CR_CNG_MV() throws {
        let config = createBaseConfig()
        config.manualSessionHandling = true
        config.requiresConsent = true
        Countly.sharedInstance().start(with: config)
        
        let viewID = Countly.sharedInstance().views().startView("TestManualViewWithoutConsent")
        XCTAssertNil(viewID, "Manual view should not be started when consent is not given.")
    }
    
    func testManualViewTrackingInit_CR_CGV_MV() throws {
        let config = createBaseConfig()
        config.manualSessionHandling = true
        config.requiresConsent = true
        config.consents = [CLYConsent.viewTracking]
        Countly.sharedInstance().start(with: config)
        
        let viewID = Countly.sharedInstance().views().startView("TestManualViewWithConsent")
        XCTAssertNotNil(viewID, "Manual view should be started when view tracking consent is given.")
        
        Countly.sharedInstance().views().stopView(withID: viewID)
    }
    
    func testPauseAndResumeViewTracking() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        let viewID = Countly.sharedInstance().views().startAutoStoppedView("TestViewPauseResume")
        XCTAssertNotNil(viewID, "Auto-stopped view should be started successfully.")
        
        let pauseViewExpectation = XCTestExpectation(description: "Wait for pause view")
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            Countly.sharedInstance().views().pauseView(withID: viewID)
            pauseViewExpectation.fulfill()
        }
        
        let resumeViewExpectation = XCTestExpectation(description: "Wait for resume view")
        DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
            Countly.sharedInstance().views().resumeView(withID: viewID)
            resumeViewExpectation.fulfill()
        }
        
        wait(for: [pauseViewExpectation, resumeViewExpectation], timeout: 10)
    }
    
    func testViewTrackingWithBackgroundAndForegroundNotifications() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        let viewID = Countly.sharedInstance().views().startView("TestViewNotifications")
        
        let bgExpectation = XCTestExpectation(description: "Wait for background notification")
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
            bgExpectation.fulfill()
        }
        
        let fgExpectation = XCTestExpectation(description: "Wait for foreground notification")
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
            fgExpectation.fulfill()
        }
        
        wait(for: [bgExpectation, fgExpectation], timeout: 15)
        XCTAssertNotNil(viewID, "View should handle background and foreground notifications correctly.")
    }
}
