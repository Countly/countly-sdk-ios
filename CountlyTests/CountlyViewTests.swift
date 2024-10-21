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
        
        let expectation = XCTestExpectation(description: "Wait for 3 seconds before stopping the view.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            Countly.sharedInstance().views().stopView(withName: "View1")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0) // Wait for the expectation to be fulfilled
        checkRecordedEventsForView(viewName: "View1")
    }
    
    func testStartAndStopViewWithSegmentation() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        let viewID = Countly.sharedInstance().views().startView("View1", segmentation: ["key": "value"])
        XCTAssertNotNil(viewID, "View should be started successfully with segmentation.")
        
        let expectation = XCTestExpectation(description: "Wait for 4 seconds before stopping the view.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            Countly.sharedInstance().views().stopView(withName: "View1")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0) // Wait for the expectation to be fulfilled
        checkRecordedEventsForView(viewName: "View1", segmentation: ["key": "value"])
    }
    
    func testStartViewAndStopViewWithID() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        let viewID = Countly.sharedInstance().views().startView("View1") ?? ""
        XCTAssertNotNil(viewID, "View should be started successfully.")
        
        let expectation = XCTestExpectation(description: "Wait for 3 seconds before stopping the view.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            Countly.sharedInstance().views().stopView(withID: viewID)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0) // Wait for the expectation to be fulfilled
        checkRecordedEventsForView(withID: viewID)
    }
    
    func testStartAndStopMultipleViewsIncludingAutoStoppedViews() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        let viewID1 = Countly.sharedInstance().views().startView("View1")
        let viewID2 = Countly.sharedInstance().views().startAutoStoppedView("View2")
        XCTAssertNotNil(viewID1, "View1 should be started successfully.")
        XCTAssertNotNil(viewID2, "View2 should be started successfully.")
        
        let expectation = XCTestExpectation(description: "Wait for 5 seconds before stopping the views.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            Countly.sharedInstance().views().stopView(withName: "View1")
            Countly.sharedInstance().views().stopView(withID: viewID2)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 6.0) // Wait for the expectation to be fulfilled
        checkRecordedEventsForView(viewName: "View1")
        checkRecordedEventsForView(withID: viewID2)
    }
    
    func testPauseAndResumeViewsForMultipleViews() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        let viewID1 = Countly.sharedInstance().views().startView("View1")
        let viewID2 = Countly.sharedInstance().views().startAutoStoppedView("View2")
        XCTAssertNotNil(viewID1, "View1 should be started successfully.")
        XCTAssertNotNil(viewID2, "View2 should be started successfully.")
        
        let expectation = XCTestExpectation(description: "Wait for 4 seconds before pausing the view.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            Countly.sharedInstance().views().pauseView(withID: viewID1)
            
            // Now wait for 3 seconds before resuming the view
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                Countly.sharedInstance().views().resumeView(withID: viewID1)
                
                // Wait for another 4 seconds before stopping the views
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    Countly.sharedInstance().views().stopView(withName: "View1")
                    Countly.sharedInstance().views().stopView(withID: viewID2)
                    expectation.fulfill()
                }
            }
        }
        
        wait(for: [expectation], timeout: 15.0) // Wait for the expectation to be fulfilled
        checkRecordedEventsForView(viewName: "View1")
        checkRecordedEventsForView(withID: viewID2)
    }
    
    func testMultiplePauseAndResumeCyclesOnSameView() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        let viewID = Countly.sharedInstance().views().startView("View1")
        XCTAssertNotNil(viewID, "View should be started successfully.")
        
        let expectation = XCTestExpectation(description: "Wait for 4 seconds before pausing the view.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            Countly.sharedInstance().views().pauseView(withID: viewID)
            
            let resumeExpectation = XCTestExpectation(description: "Wait for 3 seconds before resuming the view.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                Countly.sharedInstance().views().resumeView(withID: viewID)
                
                let stopExpectation = XCTestExpectation(description: "Wait for 4 seconds before stopping the view.")
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    Countly.sharedInstance().views().stopView(withName: "View1")
                    stopExpectation.fulfill()
                }
                self.wait(for: [stopExpectation], timeout: 5.0)
            }
            self.wait(for: [resumeExpectation], timeout: 13.0)
        }
        
        wait(for: [expectation], timeout: 10.0)
        checkRecordedEventsForView(viewName: "View1")
    }
    
    func testStartViewWhileAutoViewTrackingEnabled() throws {
        let config = createBaseConfig()
        config.enableAutomaticViewTracking = true
        Countly.sharedInstance().start(with: config)
        
        let viewID = Countly.sharedInstance().views().startView("View1")
        XCTAssertNil(viewID, "Manual view tracking should be ignored when auto view tracking is enabled.")
    }
    
    func testStartAndStopAutoStoppedViewWithSegmentation() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        let viewID = Countly.sharedInstance().views().startAutoStoppedView("View1", segmentation: ["key": "value"])
        XCTAssertNotNil(viewID, "Auto-stopped view should be started successfully with segmentation.")
        
        let expectation = XCTestExpectation(description: "Wait for 4 seconds before stopping the view.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            Countly.sharedInstance().views().stopView(withID: viewID)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0) // Wait for the expectation to be fulfilled
        checkRecordedEventsForView(withID: viewID, segmentation: ["key": "value"])
    }
    
    func testStartAutoStoppedViewAndInitiateAnother() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        let viewID1 = Countly.sharedInstance().views().startAutoStoppedView("View1")
        XCTAssertNotNil(viewID1, "View1 should be started successfully.")
        var viewID2 = ""
        let expectation = XCTestExpectation(description: "Wait for 4 seconds before starting the second view.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            viewID2 = Countly.sharedInstance().views().startAutoStoppedView("View2")
            XCTAssertNotNil(viewID2, "View2 should be started successfully.")
            
            let stopExpectation = XCTestExpectation(description: "Wait for 3 seconds before stopping both views.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                Countly.sharedInstance().views().stopView(withID: viewID1)
                Countly.sharedInstance().views().stopView(withID: viewID2)
                
                stopExpectation.fulfill()
            }
            self.wait(for: [stopExpectation], timeout: 5.0)
        }
        
        wait(for: [expectation], timeout: 6.0)
        checkRecordedEventsForView(withID: viewID1)
        checkRecordedEventsForView(withID: viewID2)
    }
    
    func testStartRegularViewPauseAndResumeMultipleTimesThenStop() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        let viewID = Countly.sharedInstance().views().startView("View1")
        XCTAssertNotNil(viewID, "View should be started successfully.")
        
        let expectation = XCTestExpectation(description: "Wait for 3 seconds before pausing the view.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            Countly.sharedInstance().views().pauseView(withID: viewID)
            
            let resumeExpectation = XCTestExpectation(description: "Wait for 3 seconds before resuming the view.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                Countly.sharedInstance().views().resumeView(withID: viewID)
                
                let stopExpectation = XCTestExpectation(description: "Wait for 4 seconds before stopping the view.")
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    Countly.sharedInstance().views().stopView(withName: "View1")
                    stopExpectation.fulfill()
                }
                self.wait(for: [stopExpectation], timeout: 5.0)
            }
            self.wait(for: [resumeExpectation], timeout: 7.0)
        }
        
        wait(for: [expectation], timeout: 10.0)
        checkRecordedEventsForView(viewName: "View1")
    }

    
    func testStopAllViewsWithSpecificSegmentation() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        Countly.sharedInstance().views().startView("View1")
        Countly.sharedInstance().views().startView("View2")
        
        let expectation = XCTestExpectation(description: "Wait for 4 seconds before stopping all views.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            Countly.sharedInstance().views().stopAllViews(["key": "value"])
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0) // Wait for the expectation to be fulfilled
        checkAllViewsStoppedWithSegmentation(["key": "value"])
    }
    
    func testAddSegmentationToAlreadyStartedViewUsingViewName() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        Countly.sharedInstance().views().startView("View1")
        
        let expectation = XCTestExpectation(description: "Wait for 3 seconds before adding segmentation.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            Countly.sharedInstance().views().addSegmentationToView(withName: "View1", segmentation: ["key": "value"])
            
            let stopExpectation = XCTestExpectation(description: "Wait for 4 seconds before stopping the view.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                Countly.sharedInstance().views().stopView(withName: "View1")
                stopExpectation.fulfill()
            }
            self.wait(for: [stopExpectation], timeout: 5.0)
        }
        
        wait(for: [expectation], timeout: 6.0) // Wait for the expectation to be fulfilled
        checkRecordedEventsForView(viewName: "View1", segmentation: ["key": "value"])
    }
    
    func testAddSegmentationToAlreadyStartedViewUsingViewID() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        let viewID = Countly.sharedInstance().views().startView("View1")
        
        let expectation = XCTestExpectation(description: "Wait for 3 seconds before adding segmentation.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            Countly.sharedInstance().views().addSegmentationToView(withID: viewID, segmentation: ["key": "value"])
            
            let stopExpectation = XCTestExpectation(description: "Wait for 4 seconds before stopping the view.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                Countly.sharedInstance().views().stopView(withID: viewID)
                stopExpectation.fulfill()
            }
            self.wait(for: [stopExpectation], timeout: 5.0)
        }
        
        wait(for: [expectation], timeout: 6.0) // Wait for the expectation to be fulfilled
        checkRecordedEventsForView(withID: viewID, segmentation: ["key": "value"])
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
        
        Countly.sharedInstance().views().startView("View1")
        
        let expectation = XCTestExpectation(description: "Wait for 4 seconds before stopping View1.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            Countly.sharedInstance().views().stopView(withName: "View1")
            
            Countly.sharedInstance().views().setGlobalViewSegmentation(["key": "value"])
            
            let startExpectation = XCTestExpectation(description: "Wait for 3 seconds before starting View2.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                Countly.sharedInstance().views().startView("View2")
                Countly.sharedInstance().views().updateGlobalViewSegmentation(["key": "newValue"])
                
                let stopExpectation = XCTestExpectation(description: "Wait for 4 seconds before stopping View2.")
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    Countly.sharedInstance().views().stopView(withName: "View2")
                    stopExpectation.fulfill()
                }
                self.wait(for: [stopExpectation], timeout: 5.0)
            }
            self.wait(for: [startExpectation], timeout: 7.0)
        }
        
        wait(for: [expectation], timeout: 10.0) // Wait for the expectation to be fulfilled
        checkGlobalSegmentationApplied(expected: ["key": "newValue"])
    }
    
    func testAppTransitionsToBackgroundAndForegroundWithActiveViews() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        Countly.sharedInstance().views().startView("View1")
        
        let waitForStart = XCTestExpectation(description: "Wait for 3 seconds before backgrounding app.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            // Simulating app going to background
            NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
            
            let waitForBackground = XCTestExpectation(description: "Wait for 4 seconds in background.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                // Simulating app returning to foreground
                NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
                
                let waitForForeground = XCTestExpectation(description: "Wait for 3 seconds after foregrounding.")
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    Countly.sharedInstance().views().stopView(withName: "View1")
                    waitForForeground.fulfill()
                }
                self.wait(for: [waitForForeground], timeout: 5.0)
            }
            self.wait(for: [waitForBackground], timeout: 5.0)
        }
        
        wait(for: [waitForStart], timeout: 6.0) // Wait for the expectation to be fulfilled
        checkRecordedEventsForView(viewName: "View1")
    }
    
    func testStartMultipleViewsMoveAppToBackgroundAndReturnToForeground() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        Countly.sharedInstance().views().startView("View1")
        Countly.sharedInstance().views().startAutoStoppedView("View2")
        
        let waitForStart = XCTestExpectation(description: "Wait for 3 seconds before backgrounding app.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            // Simulating app going to background
            NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
            
            let waitForBackground = XCTestExpectation(description: "Wait for 4 seconds in background.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                // Simulating app returning to foreground
                NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
                
                let waitForForeground = XCTestExpectation(description: "Wait for 3 seconds after foregrounding.")
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    Countly.sharedInstance().views().stopView(withName: "View1")
                    Countly.sharedInstance().views().stopView(withName: "View2")
                    waitForForeground.fulfill()
                }
                self.wait(for: [waitForForeground], timeout: 5.0)
            }
            self.wait(for: [waitForBackground], timeout: 5.0)
        }
        
        wait(for: [waitForStart], timeout: 6.0) // Wait for the expectation to be fulfilled
        checkRecordedEventsForView(viewName: "View1")
        checkRecordedEventsForView(viewName: "View2")
    }
    
    func testStartViewBackgroundAppResumeViewWhenReturningToForeground() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        Countly.sharedInstance().views().startView("View1")
        
        let waitForStart = XCTestExpectation(description: "Wait for 3 seconds before backgrounding app.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            // Simulating app going to background
            NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
            
            let waitForBackground = XCTestExpectation(description: "Wait for 4 seconds in background.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                // Simulating app returning to foreground
                NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
                
                let waitForForeground = XCTestExpectation(description: "Wait for 3 seconds after foregrounding.")
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    Countly.sharedInstance().views().stopView(withName: "View1")
                    waitForForeground.fulfill()
                }
                self.wait(for: [waitForForeground], timeout: 5.0)
            }
            self.wait(for: [waitForBackground], timeout: 5.0)
        }
        
        wait(for: [waitForStart], timeout: 6.0) // Wait for the expectation to be fulfilled
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
    
    func testUpdateSegmentationMultipleTimesOnTheSameView() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        let viewID = Countly.sharedInstance().views().startView("View1")
        XCTAssertNotNil(viewID, "View should be started successfully.")
        
        let waitForStart = XCTestExpectation(description: "Wait for 4 seconds before adding segmentation.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            Countly.sharedInstance().views().addSegmentationToView(withName: "View1", segmentation: ["key": "value1"])
            
            let waitForSecondSegmentation = XCTestExpectation(description: "Wait for 4 seconds before adding second segmentation.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                Countly.sharedInstance().views().addSegmentationToView(withName: "View1", segmentation: ["key": "value2"])
                
                let waitForStop = XCTestExpectation(description: "Wait for 3 seconds before stopping the view.")
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    Countly.sharedInstance().views().stopView(withName: "View1")
                    waitForStop.fulfill()
                }
                self.wait(for: [waitForStop], timeout: 5.0)
            }
            self.wait(for: [waitForSecondSegmentation], timeout: 5.0)
        }
        
        wait(for: [waitForStart], timeout: 6.0) // Wait for the expectation to be fulfilled
        checkRecordedEventsForView(viewName: "View1", segmentation: ["key": "value2"]) // Last segmentation should apply
    }
    
    func testBackgroundAndForegroundTriggers() throws {
        let config = createBaseConfig()
        Countly.sharedInstance().start(with: config)
        
        Countly.sharedInstance().views().startView("View1")
        
        let waitForStart = XCTestExpectation(description: "Wait for 3 seconds before backgrounding app.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            // Simulating app going to background
            NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
            
            let waitForBackground = XCTestExpectation(description: "Wait for 4 seconds in background.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                // Simulating app returning to foreground
                NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
                
                let waitForForeground = XCTestExpectation(description: "Wait for 3 seconds after foregrounding.")
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    waitForForeground.fulfill()
                }
                self.wait(for: [waitForForeground], timeout: 5.0)
            }
            self.wait(for: [waitForBackground], timeout: 5.0)
        }
        
        wait(for: [waitForStart], timeout: 6.0) // Wait for the expectation to be fulfilled
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
