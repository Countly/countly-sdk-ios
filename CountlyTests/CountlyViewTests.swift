//
//  CountlyViewTrackingTests.swift
//  CountlyTests
//
//  Copyright © 2024 Countly. All rights reserved.
//

import XCTest
@testable import Countly

class CountlyViewTrackingTests: CountlyBaseTestCase {
    
    func testStartAndStopView() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        let viewID = Countly.sharedInstance().views().startView("View1")
        XCTAssertNotNil(viewID, "View should be started successfully.")
        
        let expectation = XCTestExpectation(description: "View should be stopped after 3 seconds.")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            Countly.sharedInstance().views().stopView(withName: "View1")
            expectation.fulfill()
        }
        
        // Wait for the expectation to be fulfilled within 5 seconds
        wait(for: [expectation], timeout: 5.0)
        
        // Check recorded events after view has been stopped
        checkRecordedEventsForView(viewName: "View1")
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
        
        // Check recorded events for the view with segmentation
        checkRecordedEventsForView(viewName: "View1", segmentation: ["key": "value"])
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
        
        // Check recorded events for the view using the viewID
        checkRecordedEventsForView(withID: viewID)
    }
    
    func testStartAndStopMultipleViewsIncludingAutoStoppedViews() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        // Ensure views are started successfully
        guard let viewID1 = Countly.sharedInstance().views().startView("View1") else {
            XCTFail("View1 should be started successfully.")
            return
        }
        
        guard let viewID2 = Countly.sharedInstance().views().startAutoStoppedView("View2") else {
            XCTFail("View2 should be started successfully.")
            return
        }
        
        let expectation = XCTestExpectation(description: "Views should be stopped after 5 seconds.")
        
        // Stop the views after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            Countly.sharedInstance().views().stopView(withName: "View1")
            Countly.sharedInstance().views().stopView(withID: viewID2)
            expectation.fulfill()
        }
        
        // Wait for the stop operation to complete
        wait(for: [expectation], timeout: 7.0)  // Increased timeout to ensure sufficient time
        
        // Check recorded events for both views
        checkRecordedEventsForView(viewName: "View1")
        checkRecordedEventsForView(withID: viewID2)
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
        
        // Stop both views after 4 more seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 11) {
            Countly.sharedInstance().views().stopView(withName: "View1")
            Countly.sharedInstance().views().stopView(withID: viewID2)
            stopExpectation.fulfill()
        }
        
        // Wait for expectations to be fulfilled
        wait(for: [pauseExpectation, resumeExpectation, stopExpectation], timeout: 15.0)
        
        // Check recorded events for both views
        checkRecordedEventsForView(viewName: "View1")
        checkRecordedEventsForView(withID: viewID2)
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
        let stopExpectation = XCTestExpectation(description: "Stop View1 after another 4 seconds of resuming.")
        
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
        
        // Stop the view after another 4 seconds of resuming
        DispatchQueue.main.asyncAfter(deadline: .now() + 11) { // 4 + 3 + 4 seconds
            Countly.sharedInstance().views().stopView(withName: "View1")
            stopExpectation.fulfill()
        }
        
        // Wait for all expectations to be fulfilled
        wait(for: [pauseExpectation, resumeExpectation, stopExpectation], timeout: 12.0)
        
        // Check recorded events for the view
        checkRecordedEventsForView(viewName: "View1")
    }
    
    func testStartViewWhileAutoViewTrackingEnabled() throws {
        let config = createBaseConfig()
        config.enableAutomaticViewTracking = true // Enable auto view tracking
        Countly.sharedInstance().start(with: config)
        
        // Start a manual view tracking call
        let viewID = Countly.sharedInstance().views().startView("View1")
        
        // Assert that manual view tracking returns nil when auto tracking is enabled
        XCTAssertNil(viewID, "Manual view tracking should be ignored when auto view tracking is enabled.")
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
        
        // Check the recorded events for the view, including segmentation
        checkRecordedEventsForView(withID: viewID, segmentation: ["key": "value"])
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
                Countly.sharedInstance().views().stopView(withID: viewID1)
                Countly.sharedInstance().views().stopView(withID: viewID2)
                
                // Fulfill stopExpectation after stopping both views
                stopExpectation.fulfill()
            }
        }
        
        // Wait for both expectations
        wait(for: [startExpectation, stopExpectation], timeout: 10.0)
        
        // Check recorded events after views have been stopped
        checkRecordedEventsForView(withID: viewID1)
        checkRecordedEventsForView(withID: viewID2)
    }
    
    func testStartRegularViewPauseAndResumeMultipleTimesThenStop() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        // Start the view
        let viewID = Countly.sharedInstance().views().startView("View1")
        XCTAssertNotNil(viewID, "View should be started successfully.")
        
        // Create expectations
        let pauseExpectation = XCTestExpectation(description: "Pause the view after 3 seconds")
        let resumeExpectation = XCTestExpectation(description: "Resume the view after another 3 seconds")
        let stopExpectation = XCTestExpectation(description: "Stop the view after 4 seconds")
        
        // Pause the view after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            Countly.sharedInstance().views().pauseView(withID: viewID)
            pauseExpectation.fulfill()
        }
        
        // Resume the view after another 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            Countly.sharedInstance().views().resumeView(withID: viewID)
            resumeExpectation.fulfill()
        }
        
        // Stop the view after 4 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            Countly.sharedInstance().views().stopView(withName: "View1")
            stopExpectation.fulfill()
        }
        
        // Wait for all expectations to be fulfilled
        wait(for: [pauseExpectation, resumeExpectation, stopExpectation], timeout: 12.0)
        
        // Check recorded events after stopping the view
        checkRecordedEventsForView(viewName: "View1")
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
        wait(for: [stopAllViewsExpectation], timeout: 5.0)
        
        // Verify that all views have been stopped with the specified segmentation
        checkAllViewsStoppedWithSegmentation(["key": "value"])
    }
    
    func testAddSegmentationToAlreadyStartedViewUsingViewName() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        // Start the view and assert it starts successfully
        let viewID = Countly.sharedInstance().views().startView("View1")
        XCTAssertNotNil(viewID, "View1 should be started successfully.")
        
        // Create expectations
        let addSegmentationExpectation = XCTestExpectation(description: "Wait for 3 seconds before adding segmentation.")
        let stopViewExpectation = XCTestExpectation(description: "Wait for 4 seconds before stopping the view.")
        
        // Add segmentation after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            Countly.sharedInstance().views().addSegmentationToView(withName: "View1", segmentation: ["key": "value"])
            addSegmentationExpectation.fulfill()
            
            // Stop the view after another 4 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                Countly.sharedInstance().views().stopView(withName: "View1")
                stopViewExpectation.fulfill()
            }
        }
        
        // Wait for all expectations to be fulfilled
        wait(for: [addSegmentationExpectation, stopViewExpectation], timeout: 8.0)
        
        // Check if the recorded events include the added segmentation
        checkRecordedEventsForView(viewName: "View1", segmentation: ["key": "value"])
    }
    
    func testAddSegmentationToAlreadyStartedViewUsingViewID() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        // Start the view and assert it starts successfully
        let viewID = Countly.sharedInstance().views().startView("View1")
        XCTAssertNotNil(viewID, "View1 should be started successfully.")
        
        // Create expectations
        let addSegmentationExpectation = XCTestExpectation(description: "Wait for 3 seconds before adding segmentation.")
        let stopViewExpectation = XCTestExpectation(description: "Wait for 4 seconds before stopping the view.")
        
        // Add segmentation after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            Countly.sharedInstance().views().addSegmentationToView(withID: viewID, segmentation: ["key": "value"])
            addSegmentationExpectation.fulfill()
            
            // Stop the view after another 4 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                Countly.sharedInstance().views().stopView(withID: viewID)
                stopViewExpectation.fulfill()
            }
        }
        
        // Wait for all expectations to be fulfilled
        wait(for: [addSegmentationExpectation, stopViewExpectation], timeout: 8.0)
        
        // Check if the recorded events include the added segmentation
        checkRecordedEventsForView(withID: viewID, segmentation: ["key": "value"])
    }
    
    // Refactor remaining tests similarly...
    
    func testUpdateSegmentationMultipleTimesOnTheSameView() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        let viewID = Countly.sharedInstance().views().startView("View1")
        XCTAssertNotNil(viewID, "View should be started successfully.")
        
        // Create expectations
        let waitForStart = XCTestExpectation(description: "Wait for 4 seconds before adding segmentation.")
        let waitForSecondSegmentation = XCTestExpectation(description: "Wait for 4 seconds before adding second segmentation.")
        let waitForStop = XCTestExpectation(description: "Wait for 3 seconds before stopping the view.")
        
        // Add first segmentation
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            Countly.sharedInstance().views().addSegmentationToView(withName: "View1", segmentation: ["key": "value1"])
            waitForStart.fulfill()
            
            // Add second segmentation
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                Countly.sharedInstance().views().addSegmentationToView(withName: "View1", segmentation: ["key": "value2"])
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
        
        // Check recorded events for the view with the last segmentation
        checkRecordedEventsForView(viewName: "View1", segmentation: ["key": "value2"]) // Last segmentation should apply
    }
    
    func testStartViewWithConsentNotGiven() throws {
        let config = createBaseConfig()
        config.requiresConsent = true
        Countly.sharedInstance().start(with: config)
        
        let viewID = Countly.sharedInstance().views().startView("View1")
        XCTAssertNil(viewID, "Event should not be recorded when consent is not given.")
        
        Countly.sharedInstance().views().stopView(withName: "View1") // This should also not affect recorded events
        checkNoRecordedEvents()
    }
    
    func testSetAndUpdateGlobalViewSegmentationWithViewInteractions() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        // Start the first view
        Countly.sharedInstance().views().startView("View1")
        
        // Create expectations for various events
        let stopView1Expectation = XCTestExpectation(description: "Expect View1 to be stopped after 4 seconds.")
        let startView2Expectation = XCTestExpectation(description: "Expect View2 to start after 3 seconds.")
        let stopView2Expectation = XCTestExpectation(description: "Expect View2 to be stopped after 4 seconds.")
        
        // Stop View1 after 4 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            Countly.sharedInstance().views().stopView(withName: "View1")
            stopView1Expectation.fulfill() // Fulfill View1 stop expectation
            
            // Set global view segmentation
            Countly.sharedInstance().views().setGlobalViewSegmentation(["key": "value"])
            
            // Start View2 after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                Countly.sharedInstance().views().startView("View2")
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
        
        // Check if the global segmentation has been applied
        checkGlobalSegmentationApplied(expected: ["key": "newValue"])
    }

    func testAppTransitionsToBackgroundAndForegroundWithActiveViews() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        // Start the first view
        Countly.sharedInstance().views().startView("View1")
        
        // Create expectations for various events
        let backgroundAppExpectation = XCTestExpectation(description: "Wait for 3 seconds before backgrounding app.")
        let waitInBackgroundExpectation = XCTestExpectation(description: "Wait for 4 seconds in background.")
        let waitAfterForegroundExpectation = XCTestExpectation(description: "Wait for 3 seconds after foregrounding.")
        
        // Background the app after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            // Simulate app going to background
            NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
            backgroundAppExpectation.fulfill() // Fulfill background app expectation
            
            // Wait in background for 4 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                // Simulate app returning to foreground
                NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
                waitInBackgroundExpectation.fulfill() // Fulfill wait in background expectation
                
                // Wait after foreground for 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    // Stop the view after returning to foreground
                    Countly.sharedInstance().views().stopView(withName: "View1")
                    waitAfterForegroundExpectation.fulfill() // Fulfill wait after foreground expectation
                }
            }
        }
        
        // Wait for all expectations to be fulfilled
        wait(for: [backgroundAppExpectation, waitInBackgroundExpectation, waitAfterForegroundExpectation], timeout: 12.0)
        
        // Check recorded events for the view after transitions
        checkRecordedEventsForView(viewName: "View1")
    }
    
    func testStartMultipleViewsMoveAppToBackgroundAndReturnToForeground() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        // Start the views
        Countly.sharedInstance().views().startView("View1")
        Countly.sharedInstance().views().startAutoStoppedView("View2")
        
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
                    // Stop the views after returning to foreground
                    Countly.sharedInstance().views().stopView(withName: "View1")
                    Countly.sharedInstance().views().stopView(withName: "View2")
                    waitForForeground.fulfill() // Fulfill the foreground expectation
                }
            }
        }
        
        // Wait for all expectations to be fulfilled
        wait(for: [waitForStart, waitForBackground, waitForForeground], timeout: 12.0)
        
        // Check recorded events for the views after transitions
        checkRecordedEventsForView(viewName: "View1")
        checkRecordedEventsForView(viewName: "View2")
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
                    // Stop the view after returning to foreground
                    Countly.sharedInstance().views().stopView(withName: "View1")
                    waitForForeground.fulfill() // Fulfill the foreground expectation
                }
            }
        }
        
        // Wait for all expectations to be fulfilled
        wait(for: [waitForStart, waitForBackground, waitForForeground], timeout: 12.0)
        
        // Check recorded events for the view after transitions
        checkRecordedEventsForView(viewName: "View1")
    }

    func testAttemptToStopANonStartedView() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        // Attempt to stop a non-started view
//        let beforeEventCount = getRecordedEventCount()
        Countly.sharedInstance().views().stopView(withName: "ViewNotStarted")
//        let afterEventCount = getRecordedEventCount()
        
//        XCTAssertEqual(beforeEventCount, afterEventCount, "Stopping a non-started view should not change the state.")
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
        wait(for: [waitForStart, waitForBackground, waitForForeground], timeout: 12.0)
    }

    // Helper methods to validate results
    private func checkRecordedEventsForView(viewName: String, segmentation: [String: String]? = nil) {
        // Implement your logic to check recorded events for the specified view
    }
    
    private func checkRecordedEventsForView(withID viewID: String!, segmentation: [String: String]? = nil) {
        // Implement your logic to check recorded events for the specified view ID
    }
    
    private func checkAllViewsStoppedWithSegmentation(_ segmentation: [String: String]) {
        // Implement your logic to check that all views have been stopped with specific segmentation
    }
    
    private func checkGlobalSegmentationApplied(expected: [String: String]) {
        // Implement your logic to verify global segmentation applied correctly
    }
    
    private func checkNoRecordedEvents() {
        // Implement logic to verify no recorded events
    }
}
