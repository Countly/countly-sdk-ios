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

/// Counts token reads, which happen on a background queue.
final class AttributionReadCounter {
    private let lock = NSLock()
    private var reads = 0
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return reads
    }
    func increment() {
        lock.lock()
        reads += 1
        lock.unlock()
    }
}

/// Helpers shared by the attribution test classes; it holds no tests.
class CountlyAttributionTestCase: CountlyBaseTestCase {

    let appID = "0123456789abcdef01234567"
    // A Countly smart link: /at/<app id>/<campaign code>/<deep-link path>
    var smartLink: String {
        "https://links.example.com/at/\(appID)/summer_sale/products/42?utm_source=newsletter&cly_clk=abc"
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        try TestPlatform.skipUnlessHTTPInterceptable()
    }

    override func tearDownWithError() throws {
        Countly.sharedInstance().halt(true)
        Countly.setAppleAdsTokenProvider(TestUtils.noAppleAdsToken)
        try super.tearDownWithError()
    }

    func offlineConfig() -> CountlyConfig {
        let config = createBaseConfig()
        config.manualSessionHandling = true
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.protocolClasses = [OfflineURLProtocol.self]
        config.urlSessionConfiguration = sessionConfig
        return config
    }

    /// Starts with Apple Ads attribution on and a token provider that counts its reads.
    func startWithAppleAds(_ config: CountlyConfig, token: @escaping () -> String?) -> AttributionReadCounter {
        let counter = AttributionReadCounter()
        Countly.setAppleAdsTokenProvider { error in
            counter.increment()
            let value = token()
            if value == nil {
                error?.pointee = NSError(domain: "AAAttributionErrorDomain", code: 3)
            }
            return value
        }
        config.disableAppleAdsAttribution = false
        Countly.sharedInstance().start(with: config)
        return counter
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

    func appleAdsTokens() -> [String] {
        return attributionSignals(ofType: "apple_ads").compactMap { $0["value"] as? String }
    }

    func waitForAppleAdsToken() -> Bool {
        return TestUtils.waitUntil("apple ads token queued", timeout: TestUtils.asyncTimeout) {
            !self.appleAdsTokens().isEmpty
        }
    }

    /// Pumps the run loop, so a token read or a main thread hop that would happen does.
    func settle(_ seconds: TimeInterval = 1.0) {
        TestUtils.waitUntil("settle", timeout: seconds) { false }
    }

}

class CountlyAttributionTests: CountlyAttributionTestCase {

    // MARK: - Direct and indirect attribution

    /**
     * A campaign id and campaign user with "&", "=", "+" and spaces reach the server whole.
     * Before the fix the values were not escaped and "&" split the request.
     */
    func test_directAttribution_escapesCampaignIDAndCampaignUser() throws {
        Countly.sharedInstance().start(with: offlineConfig())

        let data = "{\"cid\":\"spring sale&x=1+2\",\"cuid\":\"user &id=7\"}"
        Countly.sharedInstance().recordDirectAttribution(withCampaignType: "countly", andCampaignData: data)

        let requests = queuedRequests(with: "campaign_id")
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?["campaign_id"] as? String, "spring sale&x=1+2")
        XCTAssertEqual(requests.first?["campaign_user"] as? String, "user &id=7")
        XCTAssertNil(requests.first?["x"], "the campaign id must not split into another parameter")
        XCTAssertNil(requests.first?["id"], "the campaign user must not split into another parameter")
        let raw = TestUtils.getCurrentRQ()?.first { $0.contains("campaign_id=") } ?? ""
        XCTAssertFalse(raw.contains(" "), "spaces are percent encoded")
        XCTAssertTrue(raw.contains("1%2B2"), "a plus is percent encoded, or the server reads it as a space")
    }

    func test_directAttribution_withoutCampaignUser_sendsCampaignIDOnly() throws {
        Countly.sharedInstance().start(with: offlineConfig())

        let data = "{\"cid\":\"plain_campaign\"}"
        Countly.sharedInstance().recordDirectAttribution(withCampaignType: "countly", andCampaignData: data)

        let requests = queuedRequests(with: "campaign_id")
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?["campaign_id"] as? String, "plain_campaign")
        XCTAssertNil(requests.first?["campaign_user"])
    }

    func test_directAttribution_specialTestType_sendsTheRawData() throws {
        Countly.sharedInstance().start(with: offlineConfig())

        Countly.sharedInstance().recordDirectAttribution(withCampaignType: "_special_test", andCampaignData: "raw&data")

        let requests = queuedRequests(with: "attribution_data")
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?["attribution_data"] as? String, "raw&data")
        XCTAssertTrue(queuedRequests(with: "campaign_id").isEmpty)
    }

    func test_indirectAttribution_sendsTheAidParameter() throws {
        Countly.sharedInstance().start(with: offlineConfig())

        Countly.sharedInstance().recordIndirectAttribution(["idfa": "idfa&value"])

        let requests = queuedRequests(with: "aid")
        XCTAssertEqual(requests.count, 1)
        let aid = requests.first?["aid"] as? [String: Any]
        XCTAssertEqual(aid?["idfa"] as? String, "idfa&value")
        XCTAssertEqual(aid?.count, 1)
    }

    func test_directAndIndirectAttribution_withoutConsent_areNotSent() throws {
        let config = offlineConfig()
        config.requiresConsent = true
        config.consents = [CLYConsent.sessions]
        Countly.sharedInstance().start(with: config)

        let data = "{\"cid\":\"c\"}"
        Countly.sharedInstance().recordDirectAttribution(withCampaignType: "countly", andCampaignData: data)
        Countly.sharedInstance().recordIndirectAttribution(["idfa": "idfa"])

        XCTAssertTrue(queuedRequests(with: "campaign_id").isEmpty)
        XCTAssertTrue(queuedRequests(with: "aid").isEmpty)
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

    func test_recordDeepLink_smartLinkWithoutPath_callbackGetsTheDlParameter() throws {
        let link = "https://links.example.com/at/\(appID)/summer_sale?dl=%2Fcart%3Fitem%3D3&utm_source=qr"
        let config = offlineConfig()
        let called = expectation(description: "deep link callback")
        config.deepLinkCallback = { path, url in
            XCTAssertEqual(path, "/cart?item=3")
            XCTAssertEqual(url.absoluteString, link)
            called.fulfill()
        }
        Countly.sharedInstance().start(with: config)

        Countly.sharedInstance().recordDeepLink(URL(string: link)!)

        wait(for: [called], timeout: TestUtils.asyncTimeout)
        XCTAssertEqual(attributionSignals(ofType: "deeplink").first?["value"] as? String, link)
    }

    func test_recordDeepLink_eachCallSendsTheLink() throws {
        Countly.sharedInstance().start(with: offlineConfig())
        let other = "https://example.com/products/7?utm_campaign=retarget"

        Countly.sharedInstance().recordDeepLink(URL(string: smartLink)!)
        Countly.sharedInstance().recordDeepLink(URL(string: other)!)

        let values = attributionSignals(ofType: "deeplink").compactMap { $0["value"] as? String }
        XCTAssertEqual(values, [smartLink, other])
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

    func test_recordDeepLink_afterConsentIsGiven_isSent() throws {
        let config = offlineConfig()
        config.requiresConsent = true
        config.consents = [CLYConsent.sessions]
        Countly.sharedInstance().start(with: config)

        Countly.sharedInstance().recordDeepLink(URL(string: smartLink)!)
        XCTAssertTrue(attributionSignals(ofType: "deeplink").isEmpty)

        Countly.sharedInstance().giveConsent(forFeatures: [CLYConsent.attribution])
        Countly.sharedInstance().recordDeepLink(URL(string: smartLink)!)

        XCTAssertEqual(attributionSignals(ofType: "deeplink").count, 1, "only the link opened after the consent")
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
            ("https://h.com/at/bad.code/x", nil)
        ]

        for (link, expected) in cases {
            XCTAssertEqual(Countly.deepLinkPath(for: URL(string: link)!), expected, link)
        }
    }

}

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
