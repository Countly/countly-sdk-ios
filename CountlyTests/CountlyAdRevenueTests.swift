//
//  CountlyAdRevenueTests.swift
//  CountlyTests
//
//  Copyright © 2026 Countly. All rights reserved.
//

import XCTest
@testable import Countly

/// recordAdRevenue records one internal [CLY]_ad_revenue event per paid impression:
/// {"key": "[CLY]_ad_revenue", "count": 1, "sum": <amount>,
///  "segmentation": {network, placement, format, currency, precision}}, each segment only when given. Events stay in the event queue, where the tests read them.
class CountlyAdRevenueTests: CountlyAttributionTestCase {

    private let adRevenueKey = "[CLY]_ad_revenue"

    private func adRevenueEvents() -> [[String: Any]] {
        return (TestUtils.getCurrentEQ() ?? [])
            .map { $0.dictionaryRepresentation() as? [String: Any] ?? [:] }
            .filter { ($0["key"] as? String) == adRevenueKey }
    }

    func test_adRevenue_recordsOneEventWithTheAmountAsSumAndEveryDetail() throws {
        Countly.sharedInstance().start(with: offlineConfig())

        Countly.sharedInstance().recordAdRevenue(0.0123, network: "AppLovin", placement: "level_end",
                                                 format: "interstitial", currency: "USD", precision: "exact")

        let events = adRevenueEvents()
        XCTAssertEqual(events.count, 1)
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event["count"] as? Int, 1)
        XCTAssertEqual(event["sum"] as? Double, 0.0123)
        XCTAssertEqual(event["segmentation"] as? [String: String], [
            "network": "AppLovin", "placement": "level_end", "format": "interstitial",
            "currency": "USD", "precision": "exact"
        ])
        XCTAssertEqual(event["peid"] as? String ?? "", "", "an internal event does not join the previous event chain")
    }

    func test_adRevenue_segmentsNotGivenAreLeftOut() throws {
        Countly.sharedInstance().start(with: offlineConfig())

        Countly.sharedInstance().recordAdRevenue(1.5)
        Countly.sharedInstance().recordAdRevenue(2.5, network: "AdMob", placement: nil, format: "",
                                                 currency: "EUR", precision: nil)

        let events = adRevenueEvents()
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0]["sum"] as? Double, 1.5)
        XCTAssertNil(events[0]["segmentation"], "no segmentation when no detail is given")
        XCTAssertEqual(events[1]["sum"] as? Double, 2.5)
        XCTAssertEqual(events[1]["segmentation"] as? [String: String], ["network": "AdMob", "currency": "EUR"])
    }

    func test_adRevenue_zeroIsRecorded_negativeNaNAndInfiniteAreNot() throws {
        Countly.sharedInstance().start(with: offlineConfig())

        Countly.sharedInstance().recordAdRevenue(-0.01)
        Countly.sharedInstance().recordAdRevenue(Double.nan)
        Countly.sharedInstance().recordAdRevenue(Double.infinity)
        XCTAssertTrue(adRevenueEvents().isEmpty)

        Countly.sharedInstance().recordAdRevenue(0)
        XCTAssertEqual(adRevenueEvents().count, 1)
        XCTAssertEqual(adRevenueEvents().first?["sum"] as? Double, 0)
    }

    func test_adRevenue_needsTheEventsConsent() throws {
        let config = offlineConfig()
        config.requiresConsent = true
        config.consents = [CLYConsent.attribution]
        Countly.sharedInstance().start(with: config)

        Countly.sharedInstance().recordAdRevenue(0.5, network: "AppLovin", placement: nil, format: nil,
                                                 currency: nil, precision: nil)
        XCTAssertTrue(adRevenueEvents().isEmpty, "the attribution consent alone does not cover it")

        Countly.sharedInstance().giveConsent(forFeatures: [CLYConsent.events])
        Countly.sharedInstance().recordAdRevenue(0.5, network: "AppLovin", placement: nil, format: nil,
                                                 currency: nil, precision: nil)
        XCTAssertEqual(adRevenueEvents().count, 1)
    }

    /// The behavior settings that drop the app's own events do not drop this internal event,
    /// as with the other internal events.
    func test_adRevenue_isNotDroppedByTheCustomEventBehaviorSettings() throws {
        let serverConfig = try XCTUnwrap(CountlyServerConfig.sharedInstance())
        defer {
            serverConfig.setValue(true, forKey: "customEventTrackingEnabled")
            serverConfig.setValue(NSSet(), forKey: "eventFilterSet")
            serverConfig.setValue(false, forKey: "eventFilterIsWhitelist")
        }
        let config = offlineConfig()
        config.disableSDKBehaviorSettingsUpdates = true
        Countly.sharedInstance().start(with: config)

        serverConfig.setValue(false, forKey: "customEventTrackingEnabled")
        Countly.sharedInstance().recordAdRevenue(0.25)
        serverConfig.setValue(true, forKey: "customEventTrackingEnabled")
        // an allow list that does not name it
        serverConfig.setValue(NSSet(array: ["purchase"]), forKey: "eventFilterSet")
        serverConfig.setValue(true, forKey: "eventFilterIsWhitelist")
        Countly.sharedInstance().recordAdRevenue(0.75)

        XCTAssertEqual(adRevenueEvents().compactMap { $0["sum"] as? Double }, [0.25, 0.75])
    }

    /// With previous name recording on, the app's own events carry cly_pen and cly_cvn; this internal event does not.
    func test_adRevenue_carriesNoPreviousEventNameSegments() throws {
        let config = offlineConfig()
        config.experimental().enablePreviousNameRecording = true
        defer { config.experimental().enablePreviousNameRecording = false }
        Countly.sharedInstance().start(with: config)

        Countly.sharedInstance().recordEvent("level_end")
        Countly.sharedInstance().recordAdRevenue(0.1, network: "AdMob", placement: nil, format: nil,
                                                 currency: nil, precision: nil)

        XCTAssertEqual(adRevenueEvents().first?["segmentation"] as? [String: String], ["network": "AdMob"])
    }

    /// An app that records the same key through recordEvent keeps today's behavior: it is the app's own event.
    func test_adRevenue_appRecordingTheKeyItselfIsUnchanged() throws {
        let config = offlineConfig()
        config.requiresConsent = true
        config.consents = [CLYConsent.events]
        Countly.sharedInstance().start(with: config)

        Countly.sharedInstance().recordEvent("purchase")
        Countly.sharedInstance().recordEvent(adRevenueKey, sum: 3.0)

        let event = try XCTUnwrap(adRevenueEvents().first)
        XCTAssertEqual(event["sum"] as? Double, 3.0)
        XCTAssertFalse((event["peid"] as? String ?? "").isEmpty, "it joins the previous event chain as before")
    }
}
