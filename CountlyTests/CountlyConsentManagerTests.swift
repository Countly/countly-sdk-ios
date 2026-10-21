//
//  CountlyConsentManagerTests.swift
//  Countly
//
//  Created by Arif Burak Demiray on 18.11.2025.
//  Copyright © 2025 Countly. All rights reserved.
//
import Foundation

import XCTest
@testable import Countly

class CountlyConsentManagerTests: CountlyBaseTestCase {
    
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
    /**
     * Tests that consent requirement is properly handled when enabled.
     * Verifies that:
     * 1. Initial consent request is sent as none given
     * 2. No data is collected until consent is given
     * 3. Location is properly handled with empty value
     * 4. After giveAllConsent call, consent request sent as all given
     */
    func test_giveAllConsents() {
        let config = TestUtils.createBaseConfig()
        config.requiresConsent = true
        
        Countly.sharedInstance().start(with: config)
        XCTAssertEqual(2, TestUtils.getCurrentRQ()?.count)
        Countly.sharedInstance().giveAllConsents()
        XCTAssertEqual(4, TestUtils.getCurrentRQ()?.count)
        var consents: [String: Any?] = [
            "push": 0,
            "content": 0,
            "crashes": 0,
            "events": 0,
            "users": 0,
            "feedback": 0,
            "apm": 0,
            "location": 0,
            "remote-config": 0,
            "sessions": 0,
            "attribution": 0,
            "views": 0,
            "metrics": 0
        ]

        TestUtils.validateRequest(["consent": consents], 0)
        TestUtils.validateRequest(["location": ""], 1)
        TestUtils.validateRequest(["begin_session": "1"], 2)
        for key in consents.keys {
            consents[key] = 1
        }
        TestUtils.validateRequest(["consent": consents], 3)

    }

    /**
     * <pre>
     * Behavior settings that turn the consent requirement on can land after start sent its own consent state, while init
     * is still running. The consent state and the empty location still go out, once each.
     *
     * 1- Start without the consent requirement, against a server that requires it
     * 2- Hold the answer until start has handled consent, then hold start until the answer is applied
     * 3- Verify consent is required and the consent state and the empty location are queued once each
     * </pre>
     */
    func test_consentRequiredByBehaviorSettingsAtTheEndOfStart_sendsTheConsentState() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        MockURLProtocol.requestHandler = { request in
            if request.url?.absoluteString.contains("method=sc") == true {
                return (ServerConfigBuilder().consentRequired(true).build().data(using: .utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil), nil)
            }
            return (#"{"result":"fail"}"#.data(using: .utf8), HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil), nil)
        }
        defer { MockURLProtocol.replyEmptyToEveryRequest() }
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let config = TestUtils.createBaseConfig()
        config.manualSessionHandling = true
        config.urlSessionConfiguration = sessionConfig
        // the SDK holds its logger weakly
        let logger = EndOfStartAnswerLogger()
        config.loggerDelegate = logger
        withExtendedLifetime(logger) {
            Countly.sharedInstance().start(with: config)
            TestUtils.waitUntil("the consent state and the empty location are queued") { (TestUtils.getCurrentRQ()?.count ?? 0) >= 2 }
        }
        XCTAssertTrue(logger.didHoldStart, "the answer landed between start's consent handling and the end of init")
        let queue = TestUtils.getCurrentRQ() ?? []
        XCTAssertTrue(CountlyConsentManager.sharedInstance().requiresConsent, "the behavior settings require consent")
        XCTAssertEqual(1, queue.filter { $0.contains("consent=") }.count, "the consent state is queued once: \(queue)")
        XCTAssertEqual(1, queue.filter { TestUtils.parseQueryString($0)["location"] as? String == "" }.count, "the empty location is queued once: \(queue)")
    }

    /**
     * <pre>
     * Behavior settings that turn the consent requirement on after start has finished send the consent state and the
     * empty location, once each.
     *
     * 1- Start without the consent requirement and hold the behavior settings answer until start has returned
     * 2- Let the answer, which requires consent, through
     * 3- Verify consent is required and the consent state and the empty location are queued once each
     * </pre>
     */
    func test_consentRequiredByBehaviorSettingsAfterStart_sendsTheConsentState() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        let release = holdBehaviorSettingsAnswer(ServerConfigBuilder().consentRequired(true))
        defer { MockURLProtocol.replyEmptyToEveryRequest() }
        Countly.sharedInstance().start(with: mockedConfig())
        XCTAssertFalse(CountlyConsentManager.sharedInstance().requiresConsent, "start finishes without the consent requirement")
        XCTAssertFalse(TestUtils.getCurrentRQ()?.contains { $0.contains("consent=") } ?? false, "and sends no consent state")

        release.signal()
        TestUtils.waitUntil("the consent state and the empty location are queued") {
            let queue = TestUtils.getCurrentRQ() ?? []
            return queue.contains { $0.contains("consent=") } && queue.contains { TestUtils.parseQueryString($0)["location"] as? String == "" }
        }
        let queue = TestUtils.getCurrentRQ() ?? []
        XCTAssertTrue(CountlyConsentManager.sharedInstance().requiresConsent, "the behavior settings require consent")
        XCTAssertEqual(1, queue.filter { $0.contains("consent=") }.count, "the consent state is queued once: \(queue)")
        XCTAssertEqual(1, queue.filter { TestUtils.parseQueryString($0)["location"] as? String == "" }.count, "the empty location is queued once: \(queue)")
    }

#if os(iOS) || os(tvOS)
    /**
     * <pre>
     * A consent requirement the behavior settings turned on is lifted again once they stop requiring consent, which
     * starts the features that were waiting for their consent, such as automatic view tracking.
     *
     * 1- Start without requiring consent, with built in behavior settings that require it and automatic view tracking,
     *    and hold the live behavior settings answer
     * 2- Verify consent is required and automatic view tracking waits for its consent
     * 3- Let the answer, which does not require consent, through and verify automatic view tracking starts
     * </pre>
     */
    func test_consentRequirementOfTheBehaviorSettingsLiftedAgain_startsTheFeaturesWaitingForConsent() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        let release = holdBehaviorSettingsAnswer(ServerConfigBuilder().consentRequired(false))
        defer { MockURLProtocol.replyEmptyToEveryRequest() }
        let config = mockedConfig()
        config.requiresConsent = false
        config.enableAutomaticViewTracking = true
        config.sdkBehaviorSettings = ServerConfigBuilder().consentRequired(true).build()
        Countly.sharedInstance().start(with: config)
        XCTAssertTrue(CountlyConsentManager.sharedInstance().requiresConsent,
                      "the built in behavior settings require consent")
        XCTAssertFalse(CountlyViewTrackingInternal.sharedInstance().isAutoViewTrackingActive, "automatic view tracking waits for its consent")

        release.signal()
        TestUtils.waitUntil("automatic view tracking starts") { CountlyViewTrackingInternal.sharedInstance().isAutoViewTrackingActive }
        XCTAssertFalse(CountlyConsentManager.sharedInstance().requiresConsent,
                       "without the server's requirement the developer's applies")
        XCTAssertTrue(CountlyViewTrackingInternal.sharedInstance().isAutoViewTrackingActive, "automatic view tracking starts once nothing waits for consent")
    }
#endif

    /**
     * <pre>
     * Behavior settings can not lift a consent requirement the developer set, so consents given and
     * withdrawn keep their effect, and a device ID change without merge still removes them.
     *
     * 1- Start requiring consent with events consent given, and hold a behavior settings answer that
     *    does not require consent
     * 2- Let the answer through and verify consent is still required and the events consent still given
     * 3- Withdraw the events consent and verify it is withdrawn, then give it again and change the device
     *    ID without merge
     * 4- Verify the change removed the consent
     * </pre>
     */
    func test_behaviorSettingsCanNotLiftTheDevelopersConsentRequirement() throws {
        try TestPlatform.skipUnlessHTTPInterceptable()
        let release = holdBehaviorSettingsAnswer(ServerConfigBuilder().consentRequired(false))
        defer { MockURLProtocol.replyEmptyToEveryRequest() }
        let config = mockedConfig()
        config.requiresConsent = true
        config.consents = [CLYConsent.events]
        Countly.sharedInstance().start(with: config)

        release.signal()
        TestUtils.waitUntil("the behavior settings answer is stored") {
            let stored = CountlyPersistency.sharedInstance().retrieveServerConfig()?["c"] as? [String: Any]
            return (stored?["cr"] as? Bool) == false
        }
        XCTAssertTrue(CountlyConsentManager.sharedInstance().requiresConsent, "the developer's requirement stays")
        XCTAssertTrue(CountlyConsentManager.sharedInstance().consentForEvents, "and the consent given at start with it")

        Countly.sharedInstance().cancelConsent(forFeatures: [CLYConsent.events])
        XCTAssertFalse(CountlyConsentManager.sharedInstance().consentForEvents, "a withdrawal takes effect")

        Countly.sharedInstance().giveConsent(forFeatures: [CLYConsent.events])
        Countly.sharedInstance().changeDeviceIDWithoutMerge("next_user")
        XCTAssertFalse(CountlyConsentManager.sharedInstance().consentForEvents,
                       "the next user does not inherit the consent")
    }

    /// A configuration whose requests go to an in-process mock, with manual sessions.
    private func mockedConfig() -> CountlyConfig {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let config = TestUtils.createBaseConfig()
        config.manualSessionHandling = true
        config.urlSessionConfiguration = sessionConfig
        return config
    }

    /// Answers the behavior settings fetch with the given settings once the returned semaphore is signalled, and every
    /// other request with a failure, so requests stay queued.
    private func holdBehaviorSettingsAnswer(_ settings: ServerConfigBuilder) -> DispatchSemaphore {
        let release = DispatchSemaphore(value: 0)
        let answer = settings.build()
        MockURLProtocol.requestHandler = { request in
            if request.url?.absoluteString.contains("method=sc") == true {
                _ = release.wait(timeout: .now() + 10)
                return (answer.data(using: .utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil), nil)
            }
            return (#"{"result":"fail"}"#.data(using: .utf8), HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil), nil)
        }
        return release
    }
}

/// Makes the behavior settings answer land between start's own consent handling and the end of init: it holds the
/// answer until start logs its health check request, which comes right after consent, then holds start there until the
/// answer is applied.
private final class EndOfStartAnswerLogger: NSObject, CountlyLoggerDelegate {
    private let startHandledConsent = DispatchSemaphore(value: 0)
    private let answerApplied = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var hasHeldStart = false

    /// Whether start was held, so the answer did land at the end of start.
    var didHoldStart: Bool {
        lock.lock()
        defer { lock.unlock() }
        return hasHeldStart
    }

    /// Holds the thread that logs the answer or the health check request, as described above.
    func internalLog(_ log: String, with level: CLYInternalLogLevel) {
        if log.contains("behavior settings received from network") {
            _ = startHandledConsent.wait(timeout: .now() + 5)
        } else if log.contains("fetched behavior settings replaced the stored ones and were persisted") {
            answerApplied.signal()
        } else if Thread.isMainThread && log.contains("sending health check request") && holdsStartOnce() {
            startHandledConsent.signal()
            _ = answerApplied.wait(timeout: .now() + 5)
        }
    }

    /// Whether this is the first health check request, the one start sends.
    private func holdsStartOnce() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let isFirst = !hasHeldStart
        hasHeldStart = true
        return isFirst
    }
}



