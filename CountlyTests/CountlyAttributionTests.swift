//
//  CountlyAttributionTests.swift
//  CountlyTests
//
//  Copyright © 2026 Countly. All rights reserved.
//

import XCTest
@testable import Countly

/// Answers every request with a connection error, so the requests the SDK queues stay in the
/// request queue where the tests read them.
private final class OfflineURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

class CountlyAttributionTests: CountlyBaseTestCase {

    // A Countly smart link: /at/<app id>/<campaign code>/<deep-link path>
    let smartLink = "https://links.example.com/at/0123456789abcdef01234567/summer_sale/products/42?utm_source=newsletter&cly_clk=abc"

    override func setUpWithError() throws {
        try super.setUpWithError()
        try TestPlatform.skipUnlessHTTPInterceptable()
    }

    override func tearDownWithError() throws {
        Countly.setAppleAdsTokenProvider(nil)
        Countly.sharedInstance().halt(true)
        try super.tearDownWithError()
    }

    func offlineConfig() -> CountlyConfig {
        let config = createBaseConfig()
        config.manualSessionHandling = true
        // the simulator has no Apple Ads token; tests that need one set a provider
        config.disableAppleAdsAttribution = true
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.protocolClasses = [OfflineURLProtocol.self]
        config.urlSessionConfiguration = sessionConfig
        return config
    }

    /// The queued requests that carry the given parameter, parsed.
    func queuedRequests(with key: String) -> [[String: Any]] {
        return (TestUtils.getCurrentRQ() ?? [])
            .map { TestUtils.parseQueryString($0) }
            .filter { $0[key] != nil }
    }

    func attributionSignals(ofType type: String) -> [[String: Any]] {
        return queuedRequests(with: "attribution")
            .compactMap { $0["attribution"] as? [String: Any] }
            .filter { $0["type"] as? String == type }
    }

    // MARK: - Direct attribution

    /**
     * A campaign id and campaign user with "&", "=" and "+" reach the server whole.
     * Before the fix the values were not escaped and "&" split the request.
     */
    func test_directAttribution_escapesCampaignIDAndCampaignUser() throws {
        Countly.sharedInstance().start(with: offlineConfig())

        Countly.sharedInstance().recordDirectAttribution(withCampaignType: "countly", andCampaignData: "{\"cid\":\"spring&sale=1+2\",\"cuid\":\"user&id=7\"}")

        let requests = queuedRequests(with: "campaign_id")
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?["campaign_id"] as? String, "spring&sale=1+2")
        XCTAssertEqual(requests.first?["campaign_user"] as? String, "user&id=7")
        XCTAssertNil(requests.first?["sale"], "the campaign id must not split into another parameter")
        XCTAssertNil(requests.first?["id"], "the campaign user must not split into another parameter")
    }

    func test_directAttribution_withoutCampaignUser_sendsCampaignIDOnly() throws {
        Countly.sharedInstance().start(with: offlineConfig())

        Countly.sharedInstance().recordDirectAttribution(withCampaignType: "countly", andCampaignData: "{\"cid\":\"plain_campaign\"}")

        let requests = queuedRequests(with: "campaign_id")
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?["campaign_id"] as? String, "plain_campaign")
        XCTAssertNil(requests.first?["campaign_user"])
    }

    // MARK: - Deep links

    func test_recordDeepLink_sendsTheURLAndCallsTheCallbackWithThePath() throws {
        let config = offlineConfig()
        let called = expectation(description: "deep link callback")
        var receivedPath: String?
        var receivedURL: URL?
        config.deepLinkCallback = { path, url in
            XCTAssertTrue(Thread.isMainThread)
            receivedPath = path
            receivedURL = url
            called.fulfill()
        }
        Countly.sharedInstance().start(with: config)

        Countly.sharedInstance().recordDeepLink(URL(string: smartLink)!)

        wait(for: [called], timeout: TestUtils.asyncTimeout)
        XCTAssertEqual(receivedPath, "/products/42")
        XCTAssertEqual(receivedURL?.absoluteString, smartLink)

        let signals = attributionSignals(ofType: "deeplink")
        XCTAssertEqual(signals.count, 1)
        XCTAssertEqual(signals.first?["value"] as? String, smartLink)
        XCTAssertEqual(signals.first?.count, 2, "the signal carries only type and value")
    }

    func test_recordDeepLink_eachCallSendsTheLink() throws {
        Countly.sharedInstance().start(with: offlineConfig())

        Countly.sharedInstance().recordDeepLink(URL(string: smartLink)!)
        Countly.sharedInstance().recordDeepLink(URL(string: "https://example.com/products/7?utm_campaign=retarget")!)

        let values = attributionSignals(ofType: "deeplink").compactMap { $0["value"] as? String }
        XCTAssertEqual(values, [smartLink, "https://example.com/products/7?utm_campaign=retarget"])
    }

    func test_recordDeepLink_withoutConsent_isNotSentButTheCallbackIsCalled() throws {
        let config = offlineConfig()
        config.requiresConsent = true
        config.consents = [CLYConsent.sessions]
        let called = expectation(description: "deep link callback")
        config.deepLinkCallback = { path, _ in
            XCTAssertEqual(path, "/products/42")
            called.fulfill()
        }
        Countly.sharedInstance().start(with: config)

        Countly.sharedInstance().recordDeepLink(URL(string: smartLink)!)

        wait(for: [called], timeout: TestUtils.asyncTimeout)
        XCTAssertTrue(attributionSignals(ofType: "deeplink").isEmpty)
    }

    func test_recordDeepLink_withAttributionConsent_isSent() throws {
        let config = offlineConfig()
        config.requiresConsent = true
        config.consents = [CLYConsent.attribution]
        Countly.sharedInstance().start(with: config)

        Countly.sharedInstance().recordDeepLink(URL(string: smartLink)!)

        XCTAssertEqual(attributionSignals(ofType: "deeplink").count, 1)
    }

    func test_recordDeepLink_beforeStart_isRecordedWhenTheSDKStarts() throws {
        Countly.sharedInstance().recordDeepLink(URL(string: smartLink)!)

        let config = offlineConfig()
        let called = expectation(description: "deep link callback")
        config.deepLinkCallback = { path, _ in
            XCTAssertEqual(path, "/products/42")
            called.fulfill()
        }
        Countly.sharedInstance().start(with: config)

        wait(for: [called], timeout: TestUtils.asyncTimeout)
        XCTAssertEqual(attributionSignals(ofType: "deeplink").count, 1)
    }

    func test_deepLinkPath_followsTheServersSmartLinkFormat() throws {
        let appID = "0123456789abcdef01234567"
        let cases: [(String, String?)] = [
            // smart link with the app id: the path after the campaign code
            ("https://h.com/at/\(appID)/code/a/b?x=1", "/a/b"),
            // short form without the app id
            ("https://h.com/at/code/products/42", "/products/42"),
            // no path: the dl parameter, else none
            ("https://h.com/at/\(appID)/code?dl=%2Fhome%3Ftab%3D2", "/home?tab=2"),
            ("https://h.com/at/code?dl=/home", "/home"),
            ("https://h.com/at/\(appID)/code", nil),
            ("https://h.com/at/code", nil),
            // the path wins over dl
            ("https://h.com/at/code/cart?dl=/home", "/cart"),
            // any other link: only dl
            ("https://example.com/products/7?dl=/promo", "/promo"),
            ("https://example.com/products/7", nil),
            ("myapp://open?dl=/settings", "/settings"),
            // a code the server does not accept is not a smart link
            ("https://h.com/at/bad.code/x", nil),
        ]

        for (link, expected) in cases {
            XCTAssertEqual(Countly.deepLinkPath(for: URL(string: link)!), expected, link)
        }
    }

    // MARK: - Apple Ads

    #if os(iOS)
    func test_appleAds_sendsTheTokenOncePerInstall() throws {
        var reads = 0
        let token = "eyJ0b2tlbiI6IjEyMyJ9+/=&x"
        Countly.setAppleAdsTokenProvider { _ in
            reads += 1
            return token
        }

        let config = offlineConfig()
        config.disableAppleAdsAttribution = false
        Countly.sharedInstance().start(with: config)

        XCTAssertTrue(TestUtils.waitUntil("apple ads token queued") { !self.attributionSignals(ofType: "apple_ads").isEmpty })
        let signals = attributionSignals(ofType: "apple_ads")
        XCTAssertEqual(signals.count, 1)
        XCTAssertEqual(signals.first?["value"] as? String, token)
        XCTAssertEqual(reads, 1)

        // a later start, keeping the storage, does not read or send it again
        Countly.sharedInstance().halt(false)
        Countly.sharedInstance().start(with: config)
        TestUtils.waitUntil("no second token", timeout: 1.0) { false }
        XCTAssertEqual(attributionSignals(ofType: "apple_ads").count, 1)
        XCTAssertEqual(reads, 1)
    }

    func test_appleAds_tokenNotAvailable_isReadAgainOnTheNextStart() throws {
        var reads = 0
        Countly.setAppleAdsTokenProvider { error in
            reads += 1
            error?.pointee = NSError(domain: "AAAttributionErrorDomain", code: 3)
            return nil
        }

        let config = offlineConfig()
        config.disableAppleAdsAttribution = false
        Countly.sharedInstance().start(with: config)
        XCTAssertTrue(TestUtils.waitUntil("token read") { reads == 1 })

        Countly.sharedInstance().halt(false)
        Countly.setAppleAdsTokenProvider { _ in
            reads += 1
            return "later_token"
        }
        Countly.sharedInstance().start(with: config)

        XCTAssertTrue(TestUtils.waitUntil("apple ads token queued") { !self.attributionSignals(ofType: "apple_ads").isEmpty })
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(attributionSignals(ofType: "apple_ads").first?["value"] as? String, "later_token")
    }

    func test_appleAds_waitsForAttributionConsent() throws {
        var reads = 0
        Countly.setAppleAdsTokenProvider { _ in
            reads += 1
            return "consented_token"
        }

        let config = offlineConfig()
        config.disableAppleAdsAttribution = false
        config.requiresConsent = true
        config.consents = [CLYConsent.sessions]
        Countly.sharedInstance().start(with: config)

        TestUtils.waitUntil("no token without consent", timeout: 1.0) { false }
        XCTAssertEqual(reads, 0)
        XCTAssertTrue(attributionSignals(ofType: "apple_ads").isEmpty)

        Countly.sharedInstance().giveConsent(forFeatures: [CLYConsent.attribution])

        XCTAssertTrue(TestUtils.waitUntil("apple ads token queued") { !self.attributionSignals(ofType: "apple_ads").isEmpty })
        XCTAssertEqual(attributionSignals(ofType: "apple_ads").first?["value"] as? String, "consented_token")
        XCTAssertEqual(reads, 1)
    }

    func test_appleAds_disabled_neverReadsTheToken() throws {
        var reads = 0
        Countly.setAppleAdsTokenProvider { _ in
            reads += 1
            return "unused"
        }

        Countly.sharedInstance().start(with: offlineConfig())

        TestUtils.waitUntil("no token when disabled", timeout: 1.0) { false }
        XCTAssertEqual(reads, 0)
        XCTAssertTrue(attributionSignals(ofType: "apple_ads").isEmpty)
    }
    #endif
}
