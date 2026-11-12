//
//  CountlyAppleAdsAttributionTests.swift
//  CountlyTests
//
//  Copyright © 2026 Countly. All rights reserved.
//

import XCTest
@testable import Countly

/// Apple Ads attribution. The token provider is mocked through an internal hook, except in
/// the simulator test of the real lookup. Helpers are in CountlyAttributionTestCase.
#if os(iOS)
class CountlyAppleAdsAttributionTests: CountlyAttributionTestCase {

    func test_appleAds_sendsTheTokenOncePerInstall() throws {
        let token = "eyJ0b2tlbiI6IjEyMyJ9+/=&x"
        let config = offlineConfig()
        let reads = startWithAppleAds(config) { token }

        XCTAssertTrue(waitForAppleAdsToken())
        XCTAssertEqual(appleAdsTokens(), [token])
        XCTAssertEqual(attributionSignals(ofType: "apple_ads").first?.count, 2, "only type and value")
        XCTAssertEqual(reads.count, 1)

        // a later start, keeping the storage, does not read or send it again
        Countly.sharedInstance().halt(false)
        let readsAfterRestart = startWithAppleAds(config) { token }
        settle()
        XCTAssertEqual(appleAdsTokens(), [token])
        XCTAssertEqual(readsAfterRestart.count, 0)
    }

    func test_appleAds_tokenNotAvailable_sendsNothingAndIsReadAgainOnTheNextStart() throws {
        let config = offlineConfig()
        let reads = startWithAppleAds(config) { nil }
        XCTAssertTrue(TestUtils.waitUntil("token read", timeout: TestUtils.asyncTimeout) { reads.count == 1 })
        settle()
        XCTAssertTrue(appleAdsTokens().isEmpty)

        Countly.sharedInstance().halt(false)
        let readsAfterRestart = startWithAppleAds(config) { "later_token" }

        XCTAssertTrue(waitForAppleAdsToken())
        XCTAssertEqual(readsAfterRestart.count, 1)
        XCTAssertEqual(appleAdsTokens(), ["later_token"])
    }

    /// Behavior settings that turn tracking off make the queue refuse the request; the token is then
    /// not marked as sent, so it goes out on a later start once tracking is on again.
    func test_appleAds_requestRefusedByTheQueue_isNotMarkedSentAndGoesOutLater() throws {
        defer { CountlyServerConfig.sharedInstance()?.setValue(true, forKey: "trackingEnabled") }
        let config = offlineConfig()
        // no behavior settings fetch that could put tracking back on while the token is read
        config.disableSDKBehaviorSettingsUpdates = true
        let reads = startWithAppleAds(config) { "refused_token" }
        // before the token read hops back to the main thread to queue it
        CountlyServerConfig.sharedInstance()?.setValue(false, forKey: "trackingEnabled")

        XCTAssertTrue(TestUtils.waitUntil("token read", timeout: TestUtils.asyncTimeout) { reads.count == 1 })
        settle()
        XCTAssertTrue(appleAdsTokens().isEmpty)
        XCTAssertFalse(CountlyPersistency.sharedInstance().retrieveAppleAdsAttributionSent())

        Countly.sharedInstance().halt(false)
        CountlyServerConfig.sharedInstance()?.setValue(true, forKey: "trackingEnabled")
        let readsAfterRestart = startWithAppleAds(config) { "refused_token" }

        XCTAssertTrue(waitForAppleAdsToken())
        XCTAssertEqual(readsAfterRestart.count, 1)
        XCTAssertEqual(appleAdsTokens(), ["refused_token"])
        XCTAssertTrue(CountlyPersistency.sharedInstance().retrieveAppleAdsAttributionSent())
    }

    /// The sent flag is stored for good, so the request it stands for is saved to the queue file first.
    /// Networking is off, so nothing else saves the queue; without the save, a kill before the request
    /// goes out loses the token while the flag stops it from ever being read again.
    func test_appleAds_queuedRequestIsSavedBeforeItIsMarkedSent() throws {
        defer { CountlyServerConfig.sharedInstance()?.setValue(true, forKey: "networkingEnabled") }
        let config = offlineConfig()
        config.disableSDKBehaviorSettingsUpdates = true
        // read after the save that start schedules has finished
        _ = startWithAppleAds(config) {
            Thread.sleep(forTimeInterval: 0.3)
            return "durable_token"
        }
        CountlyServerConfig.sharedInstance()?.setValue(false, forKey: "networkingEnabled")

        XCTAssertTrue(TestUtils.waitUntil("marked sent", timeout: TestUtils.asyncTimeout) {
            CountlyPersistency.sharedInstance().retrieveAppleAdsAttributionSent()
        })
        XCTAssertTrue(try savedRequests().contains { $0.contains("durable_token") })
    }

    private func savedRequests() throws -> [String] {
        let url = try XCTUnwrap(CountlyPersistency.sharedInstance().value(forKey: "storageFileURL") as? URL)
        let data = try Data(contentsOf: url)
        let classes = [NSDictionary.self, NSArray.self, NSString.self, NSNumber.self]
        let saved = try NSKeyedUnarchiver.unarchivedObject(ofClasses: classes, from: data) as? NSDictionary
        return saved?["kCountlyQueuedRequestsPersistencyKey"] as? [String] ?? []
    }

    #if targetEnvironment(simulator)
    /// The real AdServices lookup: the simulator has no token, so nothing is sent.
    func test_appleAds_unsupportedDevice_sendsNothing() throws {
        Countly.setAppleAdsTokenProvider(nil)
        let config = offlineConfig()
        config.disableAppleAdsAttribution = false
        Countly.sharedInstance().start(with: config)

        settle(3.0)
        XCTAssertTrue(appleAdsTokens().isEmpty)
    }
    #endif

    func test_appleAds_waitsForAttributionConsent() throws {
        let config = offlineConfig()
        config.requiresConsent = true
        config.consents = [CLYConsent.sessions]
        let reads = startWithAppleAds(config) { "consented_token" }

        settle()
        XCTAssertEqual(reads.count, 0)
        XCTAssertTrue(appleAdsTokens().isEmpty)

        Countly.sharedInstance().giveConsent(forFeatures: [CLYConsent.attribution])

        XCTAssertTrue(waitForAppleAdsToken())
        XCTAssertEqual(appleAdsTokens(), ["consented_token"])
        XCTAssertEqual(reads.count, 1)

        // giving the consent again does not send it again
        Countly.sharedInstance().cancelConsent(forFeatures: [CLYConsent.attribution])
        Countly.sharedInstance().giveConsent(forFeatures: [CLYConsent.attribution])
        settle()
        XCTAssertEqual(appleAdsTokens(), ["consented_token"])
    }

    func test_appleAds_disabled_neverReadsTheToken() throws {
        let counter = AttributionReadCounter()
        Countly.setAppleAdsTokenProvider { _ in
            counter.increment()
            return "unused"
        }
        let config = offlineConfig()
        config.disableAppleAdsAttribution = true
        Countly.sharedInstance().start(with: config)

        settle()
        XCTAssertEqual(counter.count, 0)
        XCTAssertTrue(appleAdsTokens().isEmpty)
    }
}
#endif
