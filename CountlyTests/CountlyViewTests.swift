//
//  CountlyViewTrackingTests.swift
//  CountlyTests
//
//  Copyright © 2024 Countly. All rights reserved.
//

import XCTest
@testable import Countly

class CountlyViewTrackingTests: CountlyViewBaseTest {
    
    // Run this test first if you are facing cache not clear or instances are not reset properly
    // This is a dummy test to cover the edge case clear the cache when SDK is not initialized
    func testDummy() {
        let config = createBaseConfig()
        config.requiresConsent = false;
        config.manualSessionHandling = true;
        Countly.sharedInstance().start(with: config);
        Countly.sharedInstance().halt(true)
    }
    
    func testStartAndStopView() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        // Start the first view with "View1" and set an expectation to stop after 3 seconds
        let viewID = Countly.sharedInstance().views().startView("View1")
        XCTAssertNotNil(viewID, "View should be started successfully.")
        
        let expectation = XCTestExpectation(description: "First view should be stopped after 3 seconds.")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            Countly.sharedInstance().views().stopView(withName: "View1")
            expectation.fulfill()
        }
        
        // Start the second view with "View1" and set an expectation to stop after 5 seconds
        let viewID1 = Countly.sharedInstance().views().startView("View1")
        XCTAssertNotNil(viewID1, "View should be started successfully.")
        
        let expectation1 = XCTestExpectation(description: "Second view should be stopped after 5 seconds.")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            Countly.sharedInstance().views().stopView(withName: "View1")
            expectation1.fulfill()
        }
        
        // Wait for both expectations to be fulfilled within 10 seconds
        wait(for: [expectation, expectation1], timeout: 10.0)
        
        // Verify recorded events
        let startedEventsCount = ["View1": 2] // Expecting 2 start events for "View1"
        let endedEventsDurations = ["View1": [3, 5]] // Expecting 2 stop events with durations 3 and 5 seconds
        
        // Call validateRecordedEvents to check if the events match expectations
        validateRecordedViews(startedEventsCount: startedEventsCount, endedEventsDurations: endedEventsDurations)
    }

    
    func testStartAndStopViewWithSegmentation() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        // Start the view with segmentation
        let viewID = Countly.sharedInstance().views().startView("View1", segmentation: ["key": "value"])
        XCTAssertNotNil(viewID, "View should be started successfully with segmentation.")
        
        let expectation = XCTestExpectation(description: "View should be stopped after 4 seconds.")
        
        // Stop the view after 4 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            Countly.sharedInstance().views().stopView(withName: "View1")
            expectation.fulfill()  // Fulfill expectation once view is stopped
        }
        
        // Wait for the stop operation to complete within the timeout
        wait(for: [expectation], timeout: 5.0)
        
        // Verify recorded events
        let startedEventsCount = ["View1": 1] // Expecting 1 start events for "View1"
        let endedEventsDurations = ["View1": [4]] // Expecting 1 stop events with durations 4 seconds
        
        // Call validateRecordedEvents to check if the events match expectations
        validateRecordedViews(startedEventsCount: startedEventsCount, endedEventsDurations: endedEventsDurations)
        
        validateRecordedEventSegmentations(forEventID: viewID ?? "", expectedSegmentations: ["name": "View1", "visit": 1, "key": "value", "segment": "iOS"])
    }
    
    func testStartViewAndStopViewWithID() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        guard let viewID = Countly.sharedInstance().views().startView("View1") else {
            XCTFail("View should be started successfully, but viewID is nil.")
            return
        }
        
        let expectation = XCTestExpectation(description: "View should be stopped after 3 seconds.")
        
        // Stop the view after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            Countly.sharedInstance().views().stopView(withID: viewID)
            expectation.fulfill()  // Fulfill expectation once view is stopped
        }
        
        // Wait for the expectation to be fulfilled within 5 seconds
        wait(for: [expectation], timeout: 5.0)
        
        // Verify recorded events
        let startedEventsCount = ["View1": 1] // Expecting 1 start events for "View1"
        let endedEventsDurations = ["View1": [3]] // Expecting 1 stop events with durations 3 seconds
        
        // Call validateRecordedEvents to check if the events match expectations
        validateRecordedViews(startedEventsCount: startedEventsCount, endedEventsDurations: endedEventsDurations)
    }
    
    func testStartAndStopMultipleViewsIncludingAutoStoppedViews() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        // Ensure views are started successfully
        guard let viewID1 = Countly.sharedInstance().views().startView("View1") else {
            XCTFail("View1 should be started successfully.")
            return
        }
        
       Countly.sharedInstance().views().startAutoStoppedView("View2")
        
        let expectation = XCTestExpectation(description: "Views should be stopped after 5 seconds.")
        
        // Stop the views after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            Countly.sharedInstance().views().startView("View3")
            
            Countly.sharedInstance().views().stopView(withID: viewID1)
            expectation.fulfill()
        }
        
        // Wait for the stop operation to complete
        wait(for: [expectation], timeout: 7.0)  // Increased timeout to ensure sufficient time
        
        // Check recorded events for both views
        // Verify recorded events
        let startedEventsCount = ["View1": 1,
                                  "View2" : 1,
                                  "View3" : 1]
        
        let endedEventsDurations = ["View1": [5],
                                    "View2": [5]]
        
        // Call validateRecordedEvents to check if the events match expectations
        validateRecordedViews(startedEventsCount: startedEventsCount, endedEventsDurations: endedEventsDurations)
    }
    
    func testPauseAndResumeViewsForMultipleViews() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        // Start views
        guard let viewID1 = Countly.sharedInstance().views().startView("View1") else {
            XCTFail("View1 should be started successfully.")
            return
        }
        
        guard let viewID2 = Countly.sharedInstance().views().startAutoStoppedView("View2") else {
            XCTFail("View2 should be started successfully.")
            return
        }
        
        XCTAssertNotNil(viewID1, "View1 should be started successfully.")
        XCTAssertNotNil(viewID2, "View2 should be started successfully.")
        
        // Create expectations
        let pauseExpectation = XCTestExpectation(description: "Pause View1 after 4 seconds.")
        let resumeExpectation = XCTestExpectation(description: "Resume View1 after pausing for 3 seconds.")
        let stopExpectation = XCTestExpectation(description: "Stop both views after resuming View1 for 4 seconds.")
        
        // Pause View1 after 4 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            Countly.sharedInstance().views().pauseView(withID: viewID1)
            pauseExpectation.fulfill()
        }
        
        // Resume View1 after an additional 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
            Countly.sharedInstance().views().resumeView(withID: viewID1)
            resumeExpectation.fulfill()
        }
        
        // Stop both views after 5 more seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
            Countly.sharedInstance().views().stopView(withName: "View1")
            Countly.sharedInstance().views().stopView(withID: viewID2)
            stopExpectation.fulfill()
        }
        
        // Wait for expectations to be fulfilled
        wait(for: [pauseExpectation, resumeExpectation, stopExpectation], timeout: 15.0)
        
        // Check recorded events for both views
        // Verify recorded events
        let startedEventsCount = ["View1": 1,
                                  "View2" : 1]
        
        let endedEventsDurations = ["View1": [4, 5],
                                    "View2": [12]]
        
        // Call validateRecordedEvents to check if the events match expectations
        validateRecordedViews(startedEventsCount: startedEventsCount, endedEventsDurations: endedEventsDurations)
    }
    
    func testMultiplePauseAndResumeCyclesOnSameView() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        // Start view and assert it's started successfully
        guard let viewID = Countly.sharedInstance().views().startView("View1") else {
            XCTFail("View1 should be started successfully.")
            return
        }
        XCTAssertNotNil(viewID, "View should be started successfully.")
        
        // Create expectations
        let pauseExpectation = XCTestExpectation(description: "Pause View1 after 4 seconds.")
        let resumeExpectation = XCTestExpectation(description: "Resume View1 after 3 seconds of pause.")
        
        let pauseExpectation1 = XCTestExpectation(description: "Pause View1 after 3 seconds.")
        let resumeExpectation1 = XCTestExpectation(description: "Resume View1 after 5 seconds of pause.")
        
        let stopExpectation = XCTestExpectation(description: "Stop View1 after another 5 seconds of resuming.")
        
        // Pause the view after 4 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            Countly.sharedInstance().views().pauseView(withID: viewID)
            pauseExpectation.fulfill()
        }
        
        // Resume the view after 3 more seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { // 4 + 3 seconds
            Countly.sharedInstance().views().resumeView(withID: viewID)
            resumeExpectation.fulfill()
        }
        
        // Pause the view after 4 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            Countly.sharedInstance().views().pauseView(withID: viewID)
            pauseExpectation1.fulfill()
        }
        
        // Resume the view after 3 more seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { // 4 + 3 seconds
            Countly.sharedInstance().views().resumeView(withID: viewID)
            resumeExpectation1.fulfill()
        }
        
        // Stop the view after another 4 seconds of resuming
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { // 4 + 3 + 4 seconds
            Countly.sharedInstance().views().stopView(withName: "View1")
            stopExpectation.fulfill()
        }
        
        Countly.sharedInstance().views().startView("View1")
        Countly.sharedInstance().views().stopView(withName: "View1")
        
        // Wait for all expectations to be fulfilled
        wait(for: [pauseExpectation, resumeExpectation,pauseExpectation1, resumeExpectation1, stopExpectation], timeout: 35.0)
        
        // Verify recorded events
        let startedEventsCount = ["View1": 2]
        
        let endedEventsDurations = ["View1": [4, 3, 5, 0]]
        
        // Call validateRecordedEvents to check if the events match expectations
        validateRecordedViews(startedEventsCount: startedEventsCount, endedEventsDurations: endedEventsDurations)
    }
    
    func testStartViewWhileAutoViewTrackingEnabled() throws {
        let config = createBaseConfig()
        config.enableAutomaticViewTracking = true // Enable auto view tracking
        Countly.sharedInstance().start(with: config)
        
        // Start a manual view tracking call
        let viewID = Countly.sharedInstance().views().startView("View1")
        Countly.sharedInstance().views().stopView(withName: "View1")
        Countly.sharedInstance().views().stopView(withID: viewID)
        // Assert that manual view tracking returns nil when auto tracking is enabled
        XCTAssertNil(viewID, "Manual view tracking should be ignored when auto view tracking is enabled.")
        // Verify recorded events
        let startedEventsCount: [String: Int] = [:]
        
        let endedEventsDurations : [String: [Int]] = [:]
        
        // Call validateRecordedEvents to check if the events match expectations
        validateRecordedViews(startedEventsCount: startedEventsCount, endedEventsDurations: endedEventsDurations)
    }
    
    func testStartAndStopAutoStoppedViewWithSegmentation() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        // Start the auto-stopped view with segmentation
        guard let viewID = Countly.sharedInstance().views().startAutoStoppedView("View1", segmentation: ["key": "value"]) else {
            XCTFail("Auto-stopped view should be started successfully with segmentation.")
            return
        }
        
        XCTAssertNotNil(viewID, "Auto-stopped view should be started successfully with segmentation.")
        
        // Create an expectation for stopping the view after 4 seconds
        let stopExpectation = XCTestExpectation(description: "Wait for 4 seconds before stopping the auto-stopped view.")
        
        // Stop the view after 4 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            Countly.sharedInstance().views().stopView(withID: viewID)
            stopExpectation.fulfill()
        }
        
        // Wait for the stop expectation
        wait(for: [stopExpectation], timeout: 6.0) // Allow a small buffer beyond the 4-second delay
        
        let startedEventsCount = ["View1": 1]
        
        let endedEventsDurations = ["View1": [4]]
        
        // Call validateRecordedEvents to check if the events match expectations
        validateRecordedViews(startedEventsCount: startedEventsCount, endedEventsDurations: endedEventsDurations)
    }

    func testStartAutoStoppedViewAndInitiateAnother() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        let viewID1 = Countly.sharedInstance().views().startAutoStoppedView("View1")
        XCTAssertNotNil(viewID1, "View1 should be started successfully.")
        
        var viewID2 = ""
        let startExpectation = XCTestExpectation(description: "Start second view after 4 seconds")
        let stopExpectation = XCTestExpectation(description: "Stop both views after 3 seconds")
        
        // Start second view after 4 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            viewID2 = Countly.sharedInstance().views().startAutoStoppedView("View2")
            XCTAssertNotNil(viewID2, "View2 should be started successfully.")
            
            // Fulfill startExpectation after starting View2
            startExpectation.fulfill()
            
            // Stop both views after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                Countly.sharedInstance().views().stopView(withID: viewID2)
                
                // Fulfill stopExpectation after stopping both views
                stopExpectation.fulfill()
            }
        }
        
        // Wait for both expectations
        wait(for: [startExpectation, stopExpectation], timeout: 10.0)
        
        let startedEventsCount = ["View1": 1,
                                  "View2": 1]
        
        let endedEventsDurations = ["View1": [4],
                                    "View2": [3]]
        
        // Call validateRecordedEvents to check if the events match expectations
        validateRecordedViews(startedEventsCount: startedEventsCount, endedEventsDurations: endedEventsDurations)
    }
    
    func testStartRegularViewPauseAndResumeMultipleTimesThenStop() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        // Start the view
        let viewID = Countly.sharedInstance().views().startView("View1")
        XCTAssertNotNil(viewID, "View should be started successfully.")
        var viewID2 = "";
        // Create expectations
        let pauseExpectation = XCTestExpectation(description: "Pause the view after 3 seconds")
        let resumeExpectation = XCTestExpectation(description: "Resume the view after another 4 seconds")
        let stopExpectation = XCTestExpectation(description: "Stop the view after 5 seconds")
        
        // Pause the view after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            Countly.sharedInstance().views().pauseView(withID: viewID)
            viewID2 = Countly.sharedInstance().views().startView("View2")
            pauseExpectation.fulfill()
        }
        
        // Resume the view after another 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
            Countly.sharedInstance().views().resumeView(withID: viewID)
            Countly.sharedInstance().views().pauseView(withID: viewID2)
            resumeExpectation.fulfill()
        }
        
        // Stop the view after 4 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
            Countly.sharedInstance().views().stopView(withName: "View1")
            Countly.sharedInstance().views().resumeView(withID: viewID2)
            stopExpectation.fulfill()
        }
        
        // Wait for all expectations to be fulfilled
        wait(for: [pauseExpectation, resumeExpectation, stopExpectation], timeout: 20)
        
        let startedEventsCount = ["View1": 1,
                                  "View2": 1]
        
        let endedEventsDurations = ["View1": [3, 5],
                                    "View2": [4]]
        
        // Call validateRecordedEvents to check if the events match expectations
        validateRecordedViews(startedEventsCount: startedEventsCount, endedEventsDurations: endedEventsDurations)
    }
    
    func testStopAllViewsWithSpecificSegmentation() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        // Start multiple views
        let viewID1 = Countly.sharedInstance().views().startView("View1")
        let viewID2 = Countly.sharedInstance().views().startView("View2")
        
        XCTAssertNotNil(viewID1, "View1 should be started successfully.")
        XCTAssertNotNil(viewID2, "View2 should be started successfully.")
        
        // Create expectation for stopping all views
        let stopAllViewsExpectation = XCTestExpectation(description: "Wait for 4 seconds before stopping all views.")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            Countly.sharedInstance().views().stopAllViews(["key": "value"])
            stopAllViewsExpectation.fulfill()
        }
        
        // Wait for the expectation to be fulfilled
        wait(for: [stopAllViewsExpectation], timeout: 6.0)
        
        let startedEventsCount = ["View1": 1,
                                  "View2": 1]
        
        let endedEventsDurations = ["View1": [4],
                                    "View2": [4]]
        
        // Call validateRecordedEvents to check if the events match expectations
        validateRecordedViews(startedEventsCount: startedEventsCount, endedEventsDurations: endedEventsDurations)
        //TODO: check segmentations also
    }
    
    func testUpdateSegmentationMultipleTimesOnTheSameView() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        let viewID = Countly.sharedInstance().views().startView("View1", segmentation: ["startKey": "startValue"])
        XCTAssertNotNil(viewID, "View should be started successfully.")
        
        // Create expectations
        let waitForStart = XCTestExpectation(description: "Wait for 4 seconds before adding segmentation.")
        let waitForSecondSegmentation = XCTestExpectation(description: "Wait for 4 seconds before adding second segmentation.")
        let waitForStop = XCTestExpectation(description: "Wait for 3 seconds before stopping the view.")
        
        // Add first segmentation
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            Countly.sharedInstance().views().addSegmentationToView(withName: "View1", segmentation: ["key1": "value1"])
            waitForStart.fulfill()
            
            // Add second segmentation
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                Countly.sharedInstance().views().addSegmentationToView(withName: "View1", segmentation: ["key2": "value2"])
                waitForSecondSegmentation.fulfill()
                
                // Stop the view
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    Countly.sharedInstance().views().stopView(withName: "View1")
                    waitForStop.fulfill()
                }
            }
        }
        
        // Wait for all expectations to be fulfilled
        wait(for: [waitForStart, waitForSecondSegmentation, waitForStop], timeout: 12.0)
        
        validateRecordedEventSegmentations(forEventID: viewID ?? "", expectedSegmentations: ["name": "View1", "visit": 1, "startKey": "startValue", "segment": "iOS"])
        validateRecordedEventSegmentations(forEventID: viewID ?? "", expectedSegmentations: ["name": "View1", "key1": "value1", "key2": "value2", "segment": "iOS"])
    }
    
    func testStartViewWithConsentNotGiven() throws {
        let config = createBaseConfig()
        config.requiresConsent = true
        Countly.sharedInstance().start(with: config)
        
        
        let beforeEventCount = getRecordedViews().count;
        
        let viewID = Countly.sharedInstance().views().startView("View1")
        XCTAssertNil(viewID, "Event should not be recorded when consent is not given.")
        
        Countly.sharedInstance().views().stopView(withName: "View1") // This should also not affect recorded events
        
        let viewID2 = Countly.sharedInstance().views().startView("View2")
        Countly.sharedInstance().views().stopView(withID: viewID2)
        //TODO: Add all the public methods
        
        
        let afterEventCount = getRecordedViews().count
        
        XCTAssertEqual(beforeEventCount, afterEventCount, "Stopping a non-started view should not record any new event.")
    
    }
    
    func testSetAndUpdateGlobalViewSegmentationWithViewInteractions() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        // Start the first view
        Countly.sharedInstance().views().startView("View1")
        //TODO: validate that view or remove it
        
        // Create expectations for various events
        let stopView1Expectation = XCTestExpectation(description: "Expect View1 to be stopped after 4 seconds.")
        let startView2Expectation = XCTestExpectation(description: "Expect View2 to start after 3 seconds.")
        let stopView2Expectation = XCTestExpectation(description: "Expect View2 to be stopped after 4 seconds.")
        var viewID2 = ""
        // Stop View1 after 4 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            Countly.sharedInstance().views().stopView(withName: "View1")
            stopView1Expectation.fulfill() // Fulfill View1 stop expectation
            
            // Set global view segmentation
            Countly.sharedInstance().views().setGlobalViewSegmentation(["key": "value"])
            
            // Start View2 after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                viewID2 = Countly.sharedInstance().views().startView("View2")
                //TODO: also start with segmentation to check the precedence of user provided and global segmentation
                startView2Expectation.fulfill() // Fulfill View2 start expectation
                
                // Update global view segmentation
                Countly.sharedInstance().views().updateGlobalViewSegmentation(["key": "newValue"])
                
                // Stop View2 after 4 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    Countly.sharedInstance().views().stopView(withName: "View2")
                    stopView2Expectation.fulfill() // Fulfill View2 stop expectation
                }
            }
        }
        
        // Wait for all expectations to be fulfilled
        wait(for: [stopView1Expectation, startView2Expectation, stopView2Expectation], timeout: 12.0)
        
        validateRecordedEventSegmentations(forEventID: viewID2, expectedSegmentations: ["visit": 1, "key": "value", "name": "View2", "segment": "iOS"])
        validateRecordedEventSegmentations(forEventID: viewID2, expectedSegmentations: ["key": "newValue", "name": "View2", "segment": "iOS"])
    }

}

class CountlyViewForegroundBackgroundTests: CountlyViewBaseTest {
    func testStartMultipleViewsMoveAppToBackgroundAndReturnToForeground() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        // Start the views
        Countly.sharedInstance().views().startView("V1")
        Countly.sharedInstance().views().startAutoStoppedView("A1")
        
        // Create expectations for various events
        let waitForStart = XCTestExpectation(description: "Wait for 3 seconds before backgrounding app.")
        let waitForBackground = XCTestExpectation(description: "Wait for 4 seconds in background.")
        let waitForForeground = XCTestExpectation(description: "Wait for 3 seconds after foregrounding.")
        let waitBGStartView = XCTestExpectation(description: "Wait for 1 seconds after background.")
        let waitFGStartView = XCTestExpectation(description: "Wait for 1 seconds after background.")
        
        // Start the timer for moving the app to the background
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            // Simulate app going to background
            NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
            waitForStart.fulfill() // Fulfill the start expectation
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                Countly.sharedInstance().views().startView("BGV1")
                Countly.sharedInstance().views().startAutoStoppedView("BGA1")
                waitBGStartView.fulfill() // Fulfill the foreground expectation
            }
            
            
            // Wait in background for 4 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                // Simulate app returning to foreground
                NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
                waitForBackground.fulfill() // Fulfill the background expectation
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    Countly.sharedInstance().views().startView("FGV1")
                    Countly.sharedInstance().views().startAutoStoppedView("FGA1")
                    waitFGStartView.fulfill() // Fulfill the foreground expectation
                }
                // Wait after foreground for 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    // Stop the views after returning to foreground
                    Countly.sharedInstance().views().stopAllViews(nil);
                    waitForForeground.fulfill() // Fulfill the foreground expectation
                }
            }
        }
        
        // Wait for all expectations to be fulfilled
        wait(for: [waitForStart, waitForBackground, waitForForeground], timeout: 20)
        
        let startedQueuedEventsCount = ["V1": 1,
                                        "A1": 1]
        
        let endedQueuedEventsDurations = ["V1": [3],
                                          "A1": [3]]
        
        // Call validateRecordedEvents to check if the events match expectations
        validateQueuedViews(startedEventsCount: startedQueuedEventsCount, endedEventsDurations: endedQueuedEventsDurations)
        
        let startedEventsCount = ["BGV1": 1,
                                  "BGA1": 1,
                                  "V1": 1,
                                  "A1": 1,
                                  "FGV1": 1,
                                  "FGA1": 1]
        
        let endedEventsDurations = ["BGA1": [3],
                                    "A1": [1],
                                    "V1": [5],
                                    "BGV1": [8],
                                    "FGV1": [4],
                                    "FGA1": [4]]
        
        // Call validateRecordedEvents to check if the events match expectations
        validateRecordedViews(startedEventsCount: startedEventsCount, endedEventsDurations: endedEventsDurations)
    }
    
    func testStartViewBackgroundAppResumeViewWhenReturningToForeground() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        // Start the view
        Countly.sharedInstance().views().startView("View1")
        
        // Create expectations for various events
        let waitForStart = XCTestExpectation(description: "Wait for 3 seconds before backgrounding app.")
        let waitForBackground = XCTestExpectation(description: "Wait for 4 seconds in background.")
        let waitForForeground = XCTestExpectation(description: "Wait for 3 seconds after foregrounding.")
        
        // Start the timer for moving the app to the background
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            // Simulate app going to background
            NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
            waitForStart.fulfill() // Fulfill the start expectation
            
            // Wait in background for 4 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                // Simulate app returning to foreground
                NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
                waitForBackground.fulfill() // Fulfill the background expectation
                
                // Wait after foreground for 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    // Stop the view after returning to foreground
                    Countly.sharedInstance().views().stopView(withName: "View1")
                    waitForForeground.fulfill() // Fulfill the foreground expectation
                }
            }
        }
        
        // Wait for all expectations to be fulfilled
        wait(for: [waitForStart, waitForBackground, waitForForeground], timeout: 20.0)
        
        let startedQueuedEventsCount = ["View1": 1]
        
        let endedQueuedEventsDurations = ["View1": [5]]
        
        // Call validateRecordedEvents to check if the events match expectations
        validateQueuedViews(startedEventsCount: startedQueuedEventsCount, endedEventsDurations: endedQueuedEventsDurations)
        
        let startedEventsCount = ["View1": 1]
        
        let endedEventsDurations = ["View1": [3]]
        
        // Call validateRecordedEvents to check if the events match expectations
        validateRecordedViews(startedEventsCount: startedEventsCount, endedEventsDurations: endedEventsDurations)
    }
    
    func testAttemptToStopANonStartedView() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        // Attempt to stop a non-started view
        let beforeEventCount = getRecordedViews().count;
        Countly.sharedInstance().views().stopView(withName: "ViewNotStarted")
        let afterEventCount = getRecordedViews().count
        
        XCTAssertEqual(beforeEventCount, afterEventCount, "Stopping a non-started view should not record any new event.")
    }
    
    func testBackgroundAndForegroundTriggers() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        Countly.sharedInstance().views().startView("View1")
        
        // Create expectations for various events
        let waitForStart = XCTestExpectation(description: "Wait for 3 seconds before backgrounding app.")
        let waitForBackground = XCTestExpectation(description: "Wait for 4 seconds in background.")
        let waitForForeground = XCTestExpectation(description: "Wait for 3 seconds after foregrounding.")
        
        // Start the timer for moving the app to the background
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            // Simulate app going to background
            NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
            waitForStart.fulfill() // Fulfill the start expectation
            
            // Wait in background for 4 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                // Simulate app returning to foreground
                NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
                waitForBackground.fulfill() // Fulfill the background expectation
                
                // Wait after foreground for 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    waitForForeground.fulfill() // Fulfill the foreground expectation
                }
            }
        }
        
        // Wait for all expectations to be fulfilled
        wait(for: [waitForStart, waitForBackground, waitForForeground], timeout: 15.0)
        
        let startedQueuedEventsCount = ["View1": 1]
        
        let endedQueuedEventsDurations = ["View1": [3]]
        
        // Call validateRecordedEvents to check if the events match expectations
        validateQueuedViews(startedEventsCount: startedQueuedEventsCount, endedEventsDurations: endedQueuedEventsDurations)
        
        let startedEventsCount = ["View1": 1]
        
        let endedEventsDurations: [String: [Int]]  = [:]
        
        // Call validateRecordedEvents to check if the events match expectations
        validateRecordedViews(startedEventsCount: startedEventsCount, endedEventsDurations: endedEventsDurations)
    }
}

class CountlyViewBaseTest: CountlyBaseTestCase {
    
    // Helper methods to validate results
    
    func validateRecordedViews(startedEventsCount: [String: Int], endedEventsDurations: [String: [Int]]) {
        // Access recorded events
        guard let recordedEvents = CountlyPersistency.sharedInstance().value(forKey: "recordedEvents") as? [CountlyEvent] else {
            fatalError("Failed to get recordedEvents from CountlyPersistency")
        }
        
        //        XCTAssertNotEqual(recordedEvents.count, 0, "No recorded events found")
        
        // Track occurrences for started and ended events
        var actualStartedEventsCount: [String: Int] = [:]
        var actualEndedEventsDurations: [String: [Int]] = [:]
        
        // Iterate through recorded events to populate actual counts and durations
        for event in recordedEvents {
            // Check for start events with "visit": "1"
            if event.key == kCountlyReservedEventView
            {
                if let eventKey = event.segmentation?["name"] as? String {
                    if let visit = event.segmentation?["visit"], visit as! Int == 1 {
                        actualStartedEventsCount[eventKey, default: 0] += 1
                    }
                    else{
                        actualEndedEventsDurations[eventKey, default: []].append(Int(event.duration))
                    }
                }
            }
        }
        
        // Validate started events count
        for (key, expectedCount) in startedEventsCount {
            let actualCount = actualStartedEventsCount[key] ?? 0
            XCTAssertEqual(actualCount, expectedCount, "Started events count for key \(key) does not match expected count \(expectedCount)")
        }
        
        // Validate ended events durations
        for (key, expectedDurations) in endedEventsDurations {
            let actualDurations = actualEndedEventsDurations[key] ?? []
            
            // First, ensure the counts match
            XCTAssertEqual(actualDurations.count, expectedDurations.count, "Ended events count for key \(key) does not match expected count \(expectedDurations.count)")
            
            // Create a mutable copy of actualDurations to modify
            var mutableActualDurations = actualDurations
            
            // Check each duration matches
            for (index, expectedDuration) in expectedDurations.enumerated() {
                // Check if the expected duration exists in the actual durations
                XCTAssertTrue(mutableActualDurations.contains(expectedDuration), "Duration at index \(index) for key \(key) does not match expected duration \(expectedDuration)")
                
                // Remove the expectedDuration from mutableActualDurations
                if let foundIndex = mutableActualDurations.firstIndex(of: expectedDuration) {
                    mutableActualDurations.remove(at: foundIndex)
                }
            }
            
            // Optionally, check if all expected durations have been matched
            XCTAssertTrue(mutableActualDurations.isEmpty, "Not all actual durations were matched with expected durations for key \(key)")
        }
        
    }
    
    func validateQueuedViews(startedEventsCount: [String: Int], endedEventsDurations: [String: [Int]]) {
        guard let queuedRequests = CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? [String] else {
            fatalError("Failed to get queuedRequests from CountlyPersistency")
        }
        
        // Filter out requests containing "events="
        let eventRequests = queuedRequests.filter { $0.contains("events=") }
        
        // Initialize dictionaries to track actual counts and durations for verification
        var actualStartedEventsCount: [String: Int] = [:]
        var actualEndedEventsDurations: [String: [Int]] = [:]
        
        // Loop through each event request to process events
        for request in eventRequests {
            // Parse the query parameters
            let parsedRequest = TestUtils.parseQueryString(request)
            
            // Check if "events" parameter exists and parse it
            if let eventsJSON = parsedRequest["events"] as? String,
               let jsonData = eventsJSON.data(using: .utf8) {
                do {
                    // Decode JSON data into an array of events
                    let events = try JSONDecoder().decode([CountlyEventStruct].self, from: jsonData)
                    
                    // Process each event to check if it’s a start or stop event
                    for event in events {
                        if event.key == kCountlyReservedEventView {
                            let eventKey = event.segmentation?["name"] as? String ?? ""
                            
                            // Check for start events with "visit": "1"
                            if let visit = event.segmentation?["visit"] as? Int, visit == 1 {
                                actualStartedEventsCount[eventKey, default: 0] += 1
                            }
                            // Check for stop events with "dur" for duration
                            else {
                                actualEndedEventsDurations[eventKey, default: []].append(Int(event.duration))
                            }
                        }
                    }
                } catch {
                    print("Failed to decode events JSON: \(error.localizedDescription)")
                }
            }
        }
        
        // Validate started events count
        for (key, expectedCount) in startedEventsCount {
            let actualCount = actualStartedEventsCount[key] ?? 0
            XCTAssertEqual(actualCount, expectedCount, "Started events count for key \(key) does not match expected count \(expectedCount)")
        }
        
        // Validate ended events durations
        for (key, expectedDurations) in endedEventsDurations {
            let actualDurations = actualEndedEventsDurations[key] ?? []
            XCTAssertEqual(actualDurations.count, expectedDurations.count, "Ended events count for key \(key) does not match expected count \(expectedDurations.count)")
            
            // Check each duration matches
            for (index, expectedDuration) in expectedDurations.enumerated() {
                XCTAssertEqual(actualDurations[index], expectedDuration, "Duration at index \(index) for key \(key) does not match expected duration \(expectedDuration)")
            }
        }
    }
    
    func getRecordedViews() -> [CountlyEvent] {
        // Access recorded events
        guard let recordedEvents = CountlyPersistency.sharedInstance().value(forKey: "recordedEvents") as? [CountlyEvent] else {
            fatalError("Failed to get recordedEvents from CountlyPersistency")
        }
        
        // Filter and return events with the key `kCountlyReservedEventView`
        return recordedEvents.filter { $0.key == kCountlyReservedEventView }
    }
    
    func getQueuedViews() -> [CountlyEventStruct] {
        guard let queuedRequests = CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? [String] else {
            fatalError("Failed to get queuedRequests from CountlyPersistency")
        }
        
        // Filter out requests containing "events="
        let eventRequests = queuedRequests.filter { $0.contains("events=") }
        var queuedViews: [CountlyEventStruct] = []
        
        // Process each event request to extract and filter events
        for request in eventRequests {
            // Parse the query parameters
            let parsedRequest = TestUtils.parseQueryString(request)
            
            // Check if "events" parameter exists and parse it
            if let eventsJSON = parsedRequest["events"] as? String,
               let jsonData = eventsJSON.data(using: .utf8) {
                do {
                    // Decode JSON data into an array of events
                    let events = try JSONDecoder().decode([CountlyEventStruct].self, from: jsonData)
                    
                    // Filter and add events with the key `kCountlyReservedEventView`
                    queuedViews.append(contentsOf: events.filter { $0.key == kCountlyReservedEventView })
                } catch {
                    print("Failed to decode events JSON: \(error.localizedDescription)")
                }
            }
        }
        
        return queuedViews
    }
    
    
    func validateRecordedEventSegmentations(forEventID eventID: String, expectedSegmentations: [String: Any]) {
        // Get recorded views filtered by key
        let recordedViews = getRecordedViews()
        
        // Determine if "visit" is specified in expectedSegmentations
        let requiresVisit = expectedSegmentations["visit"] as? Int == 1
        
        // Filter events based on the presence and value of "visit"
        let filteredEvents = recordedViews.filter { event in
            event.id == eventID &&
            (requiresVisit ? (event.segmentation?["visit"] as? Int == 1) : (event.segmentation?["visit"] == nil))
        }
        
        // Ensure there are events with the specified ID and segmentation criteria
        XCTAssertFalse(filteredEvents.isEmpty, "No recorded events found with ID \(eventID) matching expected segmentation criteria")
        
        // Validate segmentations for each filtered event
        for event in filteredEvents {
            guard let eventSegmentations = event.segmentation as? [String: Any] else {
                XCTFail("Event segmentation is missing or invalid for event with ID \(eventID)")
                continue
            }
            
            // Validate each expected segmentation
            for (key, expectedValue) in expectedSegmentations {
                if let actualValue = eventSegmentations[key] {
                    XCTAssertEqual("\(actualValue)", "\(expectedValue)", "Segmentation mismatch for key \(key) in recorded event with ID \(eventID): expected \(expectedValue), found \(actualValue)")
                } else {
                    XCTFail("Segmentation key \(key) missing in recorded event with ID \(eventID)")
                }
            }
        }
    }
    
    func validateQueuedEventSegmentations(forEventID eventID: String, expectedSegmentations: [String: Any]) {
        // Get queued views filtered by key
        let queuedViews = getQueuedViews()
        
        // Determine if "visit" is specified in expectedSegmentations
        let requiresVisit = expectedSegmentations["visit"] as? Int == 1
        
        // Filter events based on the presence and value of "visit"
        let filteredEvents = queuedViews.filter { event in
            event.ID == eventID &&
            (requiresVisit ? (event.segmentation?["visit"] as? Int == 1) : (event.segmentation?["visit"] == nil))
        }
        
        // Ensure there are events with the specified ID and segmentation criteria
        XCTAssertFalse(filteredEvents.isEmpty, "No queued events found with ID \(eventID) matching expected segmentation criteria")
        
        // Validate segmentations for each filtered event
        for event in filteredEvents {
            guard let eventSegmentations = event.segmentation as? [String: Any] else {
                XCTFail("Event segmentation is missing or invalid for event with ID \(eventID)")
                continue
            }
            
            // Validate each expected segmentation
            for (key, expectedValue) in expectedSegmentations {
                if let actualValue = eventSegmentations[key] {
                    XCTAssertEqual("\(actualValue)", "\(expectedValue)", "Segmentation mismatch for key \(key) in queued event with ID \(eventID): expected \(expectedValue), found \(actualValue)")
                } else {
                    XCTFail("Segmentation key \(key) missing in queued event with ID \(eventID)")
                }
            }
        }
    }


}



