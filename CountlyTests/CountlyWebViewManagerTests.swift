//
//  CountlyWebViewManagerTests.swift
//  CountlyTests
//
//  Created on 13/03/2026.
//  Copyright © 2026 Countly. All rights reserved.
//

import XCTest
import WebKit
@testable import Countly

#if os(iOS)

/// Records how many times the SDK prompts the page with a `{type:'resize'}` message.
private final class ResizePromptSpy: PassThroughBackgroundView {
    var promptCount = 0
    override func updateWindowSize() { promptCount += 1 }
}

class CountlyWebViewManagerTests: XCTestCase {

    var manager: CountlyWebViewManager!

    override func setUp() {
        super.setUp()
        manager = CountlyWebViewManager()
        // Retry-on-failure is opt-in; enable it so the retry-path tests exercise it.
        CountlyContentBuilderInternal.sharedInstance().enableContentReloadOnStall = true
    }

    override func tearDown() {
        manager = nil
        CountlyContentBuilderInternal.sharedInstance().enableContentReloadOnStall = false
        super.tearDown()
    }

    // MARK: - parseQueryString tests

    func testParseQueryString_basicParams() {
        let url = "https://example.com?key1=value1&key2=value2"
        let result = manager.parseQueryString(url)!

        XCTAssertEqual(result["key1"] as? String, "value1")
        XCTAssertEqual(result["key2"] as? String, "value2")
    }

    func testParseQueryString_noParams() {
        let url = "https://example.com"
        let result = manager.parseQueryString(url)!

        XCTAssertTrue(result.isEmpty)
    }

    func testParseQueryString_closeParam() {
        let url = "https://countly_action_event?close=1&cly_x_action_event=1"
        let result = manager.parseQueryString(url)!

        XCTAssertEqual(result["close"] as? String, "1")
        XCTAssertEqual(result["cly_x_action_event"] as? String, "1")
    }

    func testParseQueryString_actionEvent() {
        let url = "https://countly_action_event?action=event&event=%5B%7B%22key%22%3A%22test%22%7D%5D&cly_x_action_event=1"
        let result = manager.parseQueryString(url)!

        XCTAssertEqual(result["action"] as? String, "event")
        XCTAssertEqual(result["cly_x_action_event"] as? String, "1")
    }

    func testParseQueryString_resizeAction() {
        let url = "https://countly_action_event?action=resize_me&resize_me=%7B%22p%22%3A%7B%22x%22%3A0%2C%22y%22%3A0%2C%22w%22%3A320%2C%22h%22%3A480%7D%7D&cly_x_action_event=1"
        let result = manager.parseQueryString(url)!

        XCTAssertEqual(result["action"] as? String, "resize_me")
    }

    func testParseQueryString_emptyQueryString() {
        let url = "https://example.com?"
        let result = manager.parseQueryString(url)!

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - link query-param preservation (backward-validating span)

    func testParseQueryString_linkWithSingleQueryParam_preserved() {
        let url = "https://countly_action_event/?cly_x_action_event=1&action=link&link=https://example.com/path?foo=bar"
        let result = manager.parseQueryString(url)!

        XCTAssertEqual(result["link"] as? String, "https://example.com/path?foo=bar")
        XCTAssertEqual(result["action"] as? String, "link")
    }

    func testParseQueryString_linkWithMultipleQueryParams_preserved() {
        let url = "https://countly_action_event/?cly_x_action_event=1&action=link&link=https://example.com/path?foo=bar&baz=qux&n=42"
        let result = manager.parseQueryString(url)!

        XCTAssertEqual(result["link"] as? String, "https://example.com/path?foo=bar&baz=qux&n=42")
        XCTAssertNil(result["baz"])
        XCTAssertNil(result["n"])
    }

    func testParseQueryString_deeplinkWithQueryParams_preserved() {
        let url = "https://countly_action_event/?cly_x_action_event=1&action=link&link=myapp://open?screen=home&id=42&ref=push"
        let result = manager.parseQueryString(url)!

        XCTAssertEqual(result["link"] as? String, "myapp://open?screen=home&id=42&ref=push")
    }

    func testParseQueryString_linkWithoutQueryParams_preserved() {
        let url = "https://countly_action_event/?cly_x_action_event=1&action=link&link=https://example.com/landing"
        let result = manager.parseQueryString(url)!

        XCTAssertEqual(result["link"] as? String, "https://example.com/landing")
    }

    func testParseQueryString_eventAfterLink_separatedFromLink() {
        let url = "https://countly_action_event/?cly_x_action_event=1&action=link&link=https://x.com/p?a=b&c=d&event=[{\"key\":\"e\",\"sg\":{\"x\":\"y\"}}]"
        let result = manager.parseQueryString(url)!

        XCTAssertEqual(result["link"] as? String, "https://x.com/p?a=b&c=d")
        XCTAssertEqual(result["event"] as? String, "[{\"key\":\"e\",\"sg\":{\"x\":\"y\"}}]")
    }

    func testParseQueryString_invalidReservedMarkerInLink_staysInLink() {
        let url = "https://countly_action_event/?cly_x_action_event=1&action=link&link=https://x.com/p?a=b&event=notjson"
        let result = manager.parseQueryString(url)!

        XCTAssertEqual(result["link"] as? String, "https://x.com/p?a=b&event=notjson")
        XCTAssertNil(result["event"])
    }

    func testParseQueryString_eventJsonContainingReservedText_parsedWhole() {
        let url = "https://countly_action_event/?cly_x_action_event=1&action=event&event=[{\"key\":\"k\",\"sg\":{\"u\":\"a&close=1\"}}]"
        let result = manager.parseQueryString(url)!

        XCTAssertEqual(result["event"] as? String, "[{\"key\":\"k\",\"sg\":{\"u\":\"a&close=1\"}}]")
        XCTAssertNil(result["close"])
    }

    func testParseQueryString_closeBeforeLink_separated() {
        let url = "https://countly_action_event/?cly_x_action_event=1&action=link&close=1&link=https://example.com/path?foo=bar&baz=qux"
        let result = manager.parseQueryString(url)!

        XCTAssertEqual(result["link"] as? String, "https://example.com/path?foo=bar&baz=qux")
        XCTAssertEqual(result["close"] as? String, "1")
    }

    func testParseQueryString_linkWithTrailingClose_separated() {
        let url = "https://countly_action_event/?cly_x_action_event=1&action=link&link=https://example.com/path?foo=bar&baz=qux&close=1"
        let result = manager.parseQueryString(url)!

        XCTAssertEqual(result["link"] as? String, "https://example.com/path?foo=bar&baz=qux")
        XCTAssertEqual(result["close"] as? String, "1")
    }

    func testParseQueryString_linkWithTrailingCloseZero_separated() {
        let url = "https://countly_action_event/?cly_x_action_event=1&action=link&link=https://example.com/path?a=1&b=2&close=0"
        let result = manager.parseQueryString(url)!

        XCTAssertEqual(result["link"] as? String, "https://example.com/path?a=1&b=2")
        XCTAssertEqual(result["close"] as? String, "0")
    }

    func testParseQueryString_linkEndingInReservedClose_consumedAsFlag() {
        let url = "https://countly_action_event/?cly_x_action_event=1&action=link&link=https://x.com?a=b&c=d&close=1&close=1"
        let result = manager.parseQueryString(url)!

        XCTAssertEqual(result["link"] as? String, "https://x.com?a=b&c=d")
        XCTAssertEqual(result["close"] as? String, "1")
    }

    func testParseQueryString_encodedEventValue_decodedAndAvailable() {
        // Encoded on the wire: [{"key":"test_key","sg":{"color":"blue"}}] — parseQueryString decodes.
        let url = "https://countly_action_event/?cly_x_action_event=1&action=event&event=%5B%7B%22key%22%3A%22test_key%22%2C%22sg%22%3A%7B%22color%22%3A%22blue%22%7D%7D%5D"
        let result = manager.parseQueryString(url)!

        XCTAssertEqual(result["action"] as? String, "event")
        XCTAssertEqual(result["event"] as? String, "[{\"key\":\"test_key\",\"sg\":{\"color\":\"blue\"}}]")
    }

    func testParseQueryString_linkWithFragment_preserved() {
        let url = "https://countly_action_event/?cly_x_action_event=1&action=link&link=https://example.com/path?a=b#section"
        let result = manager.parseQueryString(url)!

        XCTAssertEqual(result["link"] as? String, "https://example.com/path?a=b#section")
    }

    func testParseQueryString_linkWithRepeatedQuestionMark_preserved() {
        // Regression guard: the old parser used componentsSeparatedByString:"?"[1] and dropped
        // everything after the link's own "?".
        let url = "https://countly_action_event/?cly_x_action_event=1&action=link&link=https://example.com/p?a=b?c=d"
        let result = manager.parseQueryString(url)!

        XCTAssertEqual(result["link"] as? String, "https://example.com/p?a=b?c=d")
    }

    func testParseQueryString_linkEventAndClose_allSeparated() {
        let url = "https://countly_action_event/?cly_x_action_event=1&action=link&link=https://x.com/p?a=b&c=d&event=[{\"key\":\"e\"}]&close=1"
        let result = manager.parseQueryString(url)!

        XCTAssertEqual(result["link"] as? String, "https://x.com/p?a=b&c=d")
        XCTAssertEqual(result["close"] as? String, "1")
        XCTAssertEqual(result["event"] as? String, "[{\"key\":\"e\"}]")
    }

    func testParseQueryString_invalidCloseValue_staysInLink() {
        let url = "https://countly_action_event/?cly_x_action_event=1&action=link&link=https://x.com/p?a=b&close=2"
        let result = manager.parseQueryString(url)!

        XCTAssertEqual(result["link"] as? String, "https://x.com/p?a=b&close=2")
        XCTAssertNil(result["close"])
    }

    func testParseQueryString_schemelessLink_fallbackTruncates() {
        // A schemeless link fails link validation (no URI scheme), so the query falls back to the
        // plain '&' split, which truncates a multi-param link. The server always prepends "https://",
        // so this is an edge case; the test pins the current behavior.
        let url = "https://countly_action_event/?cly_x_action_event=1&action=link&link=example.com/p?a=b&c=d"
        let result = manager.parseQueryString(url)!

        XCTAssertEqual(result["link"] as? String, "example.com/p?a=b")
        XCTAssertEqual(result["c"] as? String, "d")
    }

    func testParseQueryString_linkWithPlus_preservesPlus() {
        // Characterization: stringByRemovingPercentEncoding leaves a literal '+' untouched, so the
        // link keeps its '+'. This differs from Android (URLDecoder decodes '+' to a space).
        let url = "https://countly_action_event/?cly_x_action_event=1&action=link&link=https://x.com/search?q=a+b&lang=en"
        let result = manager.parseQueryString(url)!

        XCTAssertEqual(result["link"] as? String, "https://x.com/search?q=a+b&lang=en")
    }

    // MARK: - notifyPageLoaded tests

    func testNotifyPageLoaded_callsAppearBlock() {
        let expectation = expectation(description: "Appear block called")

        manager.webViewClosed = false
        manager.hasAppeared = false
        manager.appearBlock = {
            expectation.fulfill()
        }

        manager.notifyPageLoaded()

        waitForExpectations(timeout: 1.0)
        XCTAssertTrue(manager.hasAppeared)
    }

    func testNotifyPageLoaded_skipsIfWebViewClosed() {
        manager.webViewClosed = true
        manager.hasAppeared = false
        var blockCalled = false
        manager.appearBlock = {
            blockCalled = true
        }

        manager.notifyPageLoaded()

        XCTAssertFalse(blockCalled)
        XCTAssertFalse(manager.hasAppeared)
    }

    func testNotifyPageLoaded_skipsIfAlreadyAppeared() {
        manager.webViewClosed = false
        manager.hasAppeared = true
        var callCount = 0
        manager.appearBlock = {
            callCount += 1
        }

        manager.notifyPageLoaded()

        XCTAssertEqual(callCount, 0)
    }

    func testNotifyPageLoaded_invalidatesTimer() {
        manager.webViewClosed = false
        manager.hasAppeared = false
        manager.loadTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false, block: { _ in })

        XCTAssertNotNil(manager.loadTimeoutTimer)

        manager.notifyPageLoaded()

        XCTAssertNil(manager.loadTimeoutTimer)
    }

    // MARK: - loadDidTimeout tests

    func testLoadDidTimeout_schedulesRetry() {
        manager.webViewClosed = false
        manager.hasAppeared = false

        manager.loadDidTimeout()

        // A stalled load now triggers a retry (reload) instead of an immediate close.
        XCTAssertFalse(manager.webViewClosed)
        XCTAssertEqual(manager.resourceRetryCount, 1)
        XCTAssertNotNil(manager.pendingReloadBlock)
    }

    func testLoadDidTimeout_closesAfterRetriesExhausted() {
        manager.webViewClosed = false
        manager.hasAppeared = false
        manager.resourceRetryCount = 99  // retries already used up

        let bgView = PassThroughBackgroundView(frame: .zero)
        bgView.webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        manager.backgroundView = bgView

        let dismissExpectation = expectation(description: "Dismiss block called")
        manager.dismissBlock = { dismissExpectation.fulfill() }

        manager.loadDidTimeout()

        waitForExpectations(timeout: 3.0)
        XCTAssertTrue(manager.webViewClosed)
    }

    func testLoadDidTimeout_skipsIfAlreadyAppeared() {
        manager.webViewClosed = false
        manager.hasAppeared = true
        var dismissCalled = false
        manager.dismissBlock = {
            dismissCalled = true
        }

        manager.loadDidTimeout()

        // Give dispatch_async a chance to run
        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        XCTAssertFalse(dismissCalled)
        XCTAssertFalse(manager.webViewClosed)
    }

    func testLoadDidTimeout_skipsIfAlreadyClosed() {
        manager.webViewClosed = true
        manager.hasAppeared = false
        var dismissCalled = false
        manager.dismissBlock = {
            dismissCalled = true
        }

        manager.loadDidTimeout()

        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        XCTAssertFalse(dismissCalled)
    }

    // MARK: - webViewClosed guard tests

    func testWebViewClosedGuard_notifyPageLoadedIsIdempotent() {
        manager.webViewClosed = false
        manager.hasAppeared = false
        var callCount = 0
        manager.appearBlock = {
            callCount += 1
        }

        manager.notifyPageLoaded()
        manager.notifyPageLoaded()
        manager.notifyPageLoaded()

        XCTAssertEqual(callCount, 1)
        XCTAssertTrue(manager.hasAppeared)
    }

    // MARK: - WKScriptMessageHandler tests

    func testDidReceiveScriptMessage_resourceVerifyResult_allOK() {
        manager.webViewClosed = false
        manager.hasAppeared = false

        let expectation = expectation(description: "Appear block called")
        manager.appearBlock = {
            expectation.fulfill()
        }

        let config = WKWebViewConfiguration()
        let contentController = config.userContentController
        contentController.add(manager, name: "resourceLoadError")
        contentController.add(manager, name: "resourceVerifyResult")

        let webView = WKWebView(frame: .zero, configuration: config)

        let js = """
        window.webkit.messageHandlers.resourceVerifyResult.postMessage({
            results: [
                {tag: "SCRIPT", url: "https://example.com/app.js", status: 200},
                {tag: "LINK", url: "https://example.com/style.css", status: 200}
            ]
        });
        """
        webView.evaluateJavaScript(js, completionHandler: nil)

        waitForExpectations(timeout: 3.0)
        XCTAssertTrue(manager.hasAppeared)

        contentController.removeScriptMessageHandler(forName: "resourceLoadError")
        contentController.removeScriptMessageHandler(forName: "resourceVerifyResult")
    }

    func testDidReceiveScriptMessage_resourceVerifyResult_http500ClosesWebView() {
        // The post-load HEAD verification path closes on a >=400 resource and must NOT
        // retry (a reload would re-fire the page's on-load analytics).
        manager.webViewClosed = false
        manager.hasAppeared = false
        manager.appearBlock = nil

        let config = WKWebViewConfiguration()
        let contentController = config.userContentController
        contentController.add(manager, name: "resourceLoadError")
        contentController.add(manager, name: "resourceVerifyResult")

        let webView = WKWebView(frame: .zero, configuration: config)
        let bgView = PassThroughBackgroundView(frame: .zero)
        bgView.webView = webView
        manager.backgroundView = bgView

        let dismissExpectation = expectation(description: "Dismiss block called")
        manager.dismissBlock = { dismissExpectation.fulfill() }

        let js = """
        window.webkit.messageHandlers.resourceVerifyResult.postMessage({
            results: [
                {tag: "SCRIPT", url: "https://example.com/app.js", status: 200},
                {tag: "LINK", url: "https://example.com/style.css", status: 500}
            ]
        });
        """
        webView.evaluateJavaScript(js, completionHandler: nil)

        waitForExpectations(timeout: 3.0)
        XCTAssertTrue(manager.webViewClosed)
        XCTAssertFalse(manager.hasAppeared)
        XCTAssertEqual(manager.resourceRetryCount, 0)  // verify path does not retry

        contentController.removeScriptMessageHandler(forName: "resourceLoadError")
        contentController.removeScriptMessageHandler(forName: "resourceVerifyResult")
    }

    func testDidReceiveScriptMessage_resourceVerifyResult_defersWhileRetryInProgress() {
        // If a during-load retry (resourceLoadError path) is already scheduled, a post-load
        // verification failure must defer to it, not close. A non-nil pendingReloadBlock marks
        // a scheduled reload.
        manager.webViewClosed = false
        manager.hasAppeared = false
        manager.pendingReloadBlock = { }

        let config = WKWebViewConfiguration()
        let contentController = config.userContentController
        contentController.add(manager, name: "resourceLoadError")
        contentController.add(manager, name: "resourceVerifyResult")

        let webView = WKWebView(frame: .zero, configuration: config)
        let bgView = PassThroughBackgroundView(frame: .zero)
        bgView.webView = webView
        manager.backgroundView = bgView

        var dismissCalled = false
        manager.dismissBlock = { dismissCalled = true }

        let js = """
        window.webkit.messageHandlers.resourceVerifyResult.postMessage({
            results: [{tag: "SCRIPT", url: "https://example.com/missing.js", status: 404}]
        });
        """
        webView.evaluateJavaScript(js, completionHandler: nil)

        let settle = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { settle.fulfill() }
        waitForExpectations(timeout: 2.0)

        XCTAssertFalse(manager.webViewClosed)  // deferred to the in-flight retry
        XCTAssertFalse(dismissCalled)

        contentController.removeScriptMessageHandler(forName: "resourceLoadError")
        contentController.removeScriptMessageHandler(forName: "resourceVerifyResult")
    }

    func testDidReceiveScriptMessage_resourceVerifyResult_emptyResultsShowsView() {
        manager.webViewClosed = false
        manager.hasAppeared = false

        let expectation = expectation(description: "Appear block called")
        manager.appearBlock = {
            expectation.fulfill()
        }

        let config = WKWebViewConfiguration()
        let contentController = config.userContentController
        contentController.add(manager, name: "resourceLoadError")
        contentController.add(manager, name: "resourceVerifyResult")

        let webView = WKWebView(frame: .zero, configuration: config)

        let js = """
        window.webkit.messageHandlers.resourceVerifyResult.postMessage({
            results: []
        });
        """
        webView.evaluateJavaScript(js, completionHandler: nil)

        waitForExpectations(timeout: 3.0)
        XCTAssertTrue(manager.hasAppeared)

        contentController.removeScriptMessageHandler(forName: "resourceLoadError")
        contentController.removeScriptMessageHandler(forName: "resourceVerifyResult")
    }

    func testDidReceiveScriptMessage_resourceVerifyResult_unreachableDefersInsteadOfAppearing() {
        // A resource that is unreachable (HEAD status 0) is NOT verified-good: with reload-on-stall
        // enabled (setUp enables it) the SDK must NOT appear here (which would cancel a pending
        // reload); it defers so the reload/timeout can recover it.
        manager.webViewClosed = false
        manager.hasAppeared = false

        var appeared = false
        manager.appearBlock = { appeared = true }

        let config = WKWebViewConfiguration()
        let contentController = config.userContentController
        contentController.add(manager, name: "resourceLoadError")
        contentController.add(manager, name: "resourceVerifyResult")

        let webView = WKWebView(frame: .zero, configuration: config)
        let bgView = PassThroughBackgroundView(frame: .zero)
        bgView.webView = webView
        manager.backgroundView = bgView

        let js = """
        window.webkit.messageHandlers.resourceVerifyResult.postMessage({
            results: [{tag: "SCRIPT", url: "https://example.com/vendor.js", status: 0}]
        });
        """
        webView.evaluateJavaScript(js, completionHandler: nil)

        let settle = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { settle.fulfill() }
        waitForExpectations(timeout: 2.0)

        XCTAssertFalse(manager.hasAppeared)   // deferred, did not appear
        XCTAssertFalse(appeared)
        XCTAssertFalse(manager.webViewClosed) // and did not close from the verify path

        contentController.removeScriptMessageHandler(forName: "resourceLoadError")
        contentController.removeScriptMessageHandler(forName: "resourceVerifyResult")
    }

    func testDidReceiveScriptMessage_resourceLoadError_schedulesRetry() {
        manager.webViewClosed = false
        manager.hasAppeared = false

        let config = WKWebViewConfiguration()
        let contentController = config.userContentController
        contentController.add(manager, name: "resourceLoadError")
        contentController.add(manager, name: "resourceVerifyResult")

        let webView = WKWebView(frame: .zero, configuration: config)

        // Attach backgroundView with webView so a later reload is a clean no-op
        let bgView = PassThroughBackgroundView(frame: .zero)
        bgView.webView = webView
        manager.backgroundView = bgView

        var dismissCalled = false
        manager.dismissBlock = { dismissCalled = true }

        // Deliver the message from a genuinely loaded page: evaluateJavaScript on a web view
        // that never loaded a document delivers the postMessage only intermittently (no stable
        // JS context), which made this test flaky. An inline script in loaded HTML is reliable.
        let html = """
        <html><body><script>
        window.webkit.messageHandlers.resourceLoadError.postMessage({tag:"SCRIPT", url:"https://example.com/broken.js"});
        </script></body></html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://example.com"))

        let scheduled = XCTNSPredicateExpectation(predicate: NSPredicate(block: { [weak manager] _, _ in
            manager?.pendingReloadBlock != nil
        }), object: nil)
        wait(for: [scheduled], timeout: 5.0)

        XCTAssertFalse(manager.webViewClosed)
        XCTAssertFalse(dismissCalled)
        XCTAssertEqual(manager.resourceRetryCount, 1)
        XCTAssertNotNil(manager.pendingReloadBlock)

        contentController.removeScriptMessageHandler(forName: "resourceLoadError")
        contentController.removeScriptMessageHandler(forName: "resourceVerifyResult")
    }

    func testDidReceiveScriptMessage_resourceLoadError_closesWhenReloadDisabled() {
        // With enableContentReloadOnStall off, a critical-resource failure closes (original behavior).
        CountlyContentBuilderInternal.sharedInstance().enableContentReloadOnStall = false
        manager.webViewClosed = false
        manager.hasAppeared = false

        let config = WKWebViewConfiguration()
        let contentController = config.userContentController
        contentController.add(manager, name: "resourceLoadError")
        contentController.add(manager, name: "resourceVerifyResult")

        let webView = WKWebView(frame: .zero, configuration: config)
        let bgView = PassThroughBackgroundView(frame: .zero)
        bgView.webView = webView
        manager.backgroundView = bgView

        let dismissExpectation = expectation(description: "Dismiss block called")
        manager.dismissBlock = { dismissExpectation.fulfill() }

        let js = """
        window.webkit.messageHandlers.resourceLoadError.postMessage({tag: "SCRIPT", url: "https://example.com/broken.js"});
        """
        webView.evaluateJavaScript(js, completionHandler: nil)

        waitForExpectations(timeout: 3.0)
        XCTAssertTrue(manager.webViewClosed)
        XCTAssertEqual(manager.resourceRetryCount, 0)  // did not retry

        contentController.removeScriptMessageHandler(forName: "resourceLoadError")
        contentController.removeScriptMessageHandler(forName: "resourceVerifyResult")
    }

    func testDidReceiveScriptMessage_resourceLoadError_closesAfterRetriesExhausted() {
        manager.webViewClosed = false
        manager.hasAppeared = false
        // Simulate retries already used up so the next failure closes immediately.
        manager.resourceRetryCount = 99

        let config = WKWebViewConfiguration()
        let contentController = config.userContentController
        contentController.add(manager, name: "resourceLoadError")
        contentController.add(manager, name: "resourceVerifyResult")

        let webView = WKWebView(frame: .zero, configuration: config)

        // Attach backgroundView with webView so closeWebView doesn't bail early
        let bgView = PassThroughBackgroundView(frame: .zero)
        bgView.webView = webView
        manager.backgroundView = bgView

        let dismissExpectation = expectation(description: "Dismiss block called")
        manager.dismissBlock = { dismissExpectation.fulfill() }

        let js = """
        window.webkit.messageHandlers.resourceLoadError.postMessage({
            tag: "SCRIPT",
            url: "https://example.com/broken.js"
        });
        """
        webView.evaluateJavaScript(js, completionHandler: nil)

        waitForExpectations(timeout: 3.0)
        XCTAssertTrue(manager.webViewClosed)
    }

    func testRetryOrClose_ignoredAfterContentAppeared() {
        // Once content is visible, a late resource failure must NOT reload or close it.
        manager.webViewClosed = false
        manager.hasAppeared = true
        manager.resourceRetryCount = 0

        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let bgView = PassThroughBackgroundView(frame: .zero)
        bgView.webView = webView
        manager.backgroundView = bgView

        var dismissCalled = false
        manager.dismissBlock = { dismissCalled = true }

        manager.retryOrCloseWebView(forReason: "late failure after appearance")

        let settle = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { settle.fulfill() }
        waitForExpectations(timeout: 2.0)

        XCTAssertFalse(manager.webViewClosed)
        XCTAssertFalse(dismissCalled)
        XCTAssertNil(manager.pendingReloadBlock)
        XCTAssertEqual(manager.resourceRetryCount, 0)
    }

    func testNotifyPageLoaded_cancelsPendingReloadAfterSuccess() {
        // A reload scheduled from an earlier failure in the same load cycle must be cancelled
        // once the load succeeds, so a stale reload can't reload the good page (which would
        // re-fire the page's on-load [CLY]_content_shown).
        manager.webViewClosed = false
        manager.hasAppeared = false

        // A stall/resource failure schedules a retry.
        manager.retryOrCloseWebView(forReason: "stall")
        XCTAssertNotNil(manager.pendingReloadBlock)
        XCTAssertEqual(manager.resourceRetryCount, 1)

        // The load then verifies good / appears.
        manager.notifyPageLoaded()
        XCTAssertTrue(manager.hasAppeared)
        XCTAssertNil(manager.pendingReloadBlock)  // scheduled block cancelled and cleared

        // Wait past the retry delay (0.6s): the cancelled reload must not fire or close the view.
        let settle = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { settle.fulfill() }
        waitForExpectations(timeout: 2.0)
        XCTAssertFalse(manager.webViewClosed)
        XCTAssertTrue(manager.hasAppeared)
    }

    func testCancelPendingReload_clearsScheduledRetry() {
        manager.webViewClosed = false
        manager.hasAppeared = false

        manager.retryOrCloseWebView(forReason: "stall")
        XCTAssertNotNil(manager.pendingReloadBlock)

        manager.cancelPendingReload()
        XCTAssertNil(manager.pendingReloadBlock)

        // The reload must not fire after cancellation.
        let settle = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { settle.fulfill() }
        waitForExpectations(timeout: 2.0)
        XCTAssertFalse(manager.webViewClosed)
        XCTAssertFalse(manager.hasAppeared)
    }

    func testContentShownDeadlineReached_closesWebView() {
        // The absolute deadline closes the web view when content_shown never arrived, even if
        // the view had (blankly) "appeared" - content_shown would otherwise have cancelled it.
        manager.webViewClosed = false
        manager.hasAppeared = true

        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let bgView = PassThroughBackgroundView(frame: .zero)
        bgView.webView = webView
        manager.backgroundView = bgView

        let dismissExpectation = expectation(description: "Dismiss block called")
        manager.dismissBlock = { dismissExpectation.fulfill() }

        manager.contentShownDeadlineReached()

        waitForExpectations(timeout: 3.0)
        XCTAssertTrue(manager.webViewClosed)
    }

    func testContentShownEvent_cancelsDeadlineTimer() {
        // Receiving a [CLY]_content_shown event cancels the absolute deadline, so genuinely
        // shown content is never torn down by it.
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { _ in }
        manager.contentShownDeadlineTimer = timer

        let json = "[{\"key\":\"[CLY]_content_shown\",\"segmentation\":{\"content_id\":\"abc\"}}]"
        manager.recordEvents(withJSONString: json)

        XCTAssertNil(manager.contentShownDeadlineTimer)
        XCTAssertFalse(timer.isValid)
    }

    func testIsFeedbackWidgetURL_recognizesFeedbackWidgetURLs() {
        // Feedback widget URLs (host/feedback/<type>?...&widget_id=...) must be recognized so the
        // content-shown deadline is NOT armed for them (widgets never emit [CLY]_content_shown).
        XCTAssertTrue(manager.isFeedbackWidgetURL(URL(string: "https://example.count.ly/feedback/nps?app_key=k&widget_id=abc123")!))
        XCTAssertTrue(manager.isFeedbackWidgetURL(URL(string: "https://example.count.ly/feedback/survey?widget_id=x")!))
        XCTAssertTrue(manager.isFeedbackWidgetURL(URL(string: "https://example.count.ly/feedback/rating?widget_id=x")!))
        // Base-path host still matches (uses a path-segment contains check, not a prefix).
        XCTAssertTrue(manager.isFeedbackWidgetURL(URL(string: "https://example.com/base/feedback/nps?widget_id=x")!))
    }

    func testIsFeedbackWidgetURL_rejectsContentURLs() {
        // Content URLs (host/_external/content?...) must NOT be treated as feedback widgets, so
        // the content-shown deadline stays armed for real content.
        XCTAssertFalse(manager.isFeedbackWidgetURL(URL(string: "https://countly.teb.com.tr/_external/content?app_id=1&id=2&journeyId=3")!))
        XCTAssertFalse(manager.isFeedbackWidgetURL(URL(string: "https://example.count.ly/o/sdk/content?method=queue")!))
        XCTAssertFalse(manager.isFeedbackWidgetURL(URL(string: "about:blank")!))
    }

    func testNonContentShownEvent_leavesDeadlineTimerRunning() {
        // A different event must NOT cancel the deadline.
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { _ in }
        manager.contentShownDeadlineTimer = timer

        let json = "[{\"key\":\"some_other_event\",\"segmentation\":{\"a\":\"b\"}}]"
        manager.recordEvents(withJSONString: json)

        XCTAssertNotNil(manager.contentShownDeadlineTimer)
        XCTAssertTrue(timer.isValid)
        timer.invalidate()
    }

    func testDidReceiveScriptMessage_ignoredWhenWebViewClosed() {
        manager.webViewClosed = true
        manager.hasAppeared = false

        var appearCalled = false
        manager.appearBlock = {
            appearCalled = true
        }
        var dismissCalled = false
        manager.dismissBlock = {
            dismissCalled = true
        }

        let config = WKWebViewConfiguration()
        let contentController = config.userContentController
        contentController.add(manager, name: "resourceLoadError")
        contentController.add(manager, name: "resourceVerifyResult")

        let webView = WKWebView(frame: .zero, configuration: config)

        let js = """
        window.webkit.messageHandlers.resourceVerifyResult.postMessage({
            results: [{tag: "SCRIPT", url: "https://example.com/app.js", status: 200}]
        });
        """
        webView.evaluateJavaScript(js, completionHandler: nil)

        let exp = expectation(description: "wait for JS")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            exp.fulfill()
        }
        waitForExpectations(timeout: 2.0)

        XCTAssertFalse(appearCalled)
        XCTAssertFalse(dismissCalled)
        XCTAssertFalse(manager.hasAppeared)

        contentController.removeScriptMessageHandler(forName: "resourceLoadError")
        contentController.removeScriptMessageHandler(forName: "resourceVerifyResult")
    }

    func testDidReceiveScriptMessage_http404ClosesWebView() {
        // Post-load verification 404 closes without retrying.
        manager.webViewClosed = false
        manager.hasAppeared = false

        let config = WKWebViewConfiguration()
        let contentController = config.userContentController
        contentController.add(manager, name: "resourceLoadError")
        contentController.add(manager, name: "resourceVerifyResult")

        let webView = WKWebView(frame: .zero, configuration: config)
        let bgView = PassThroughBackgroundView(frame: .zero)
        bgView.webView = webView
        manager.backgroundView = bgView

        let dismissExpectation = expectation(description: "Dismiss block called")
        manager.dismissBlock = { dismissExpectation.fulfill() }

        let js = """
        window.webkit.messageHandlers.resourceVerifyResult.postMessage({
            results: [
                {tag: "SCRIPT", url: "https://example.com/missing.js", status: 404}
            ]
        });
        """
        webView.evaluateJavaScript(js, completionHandler: nil)

        waitForExpectations(timeout: 3.0)
        XCTAssertTrue(manager.webViewClosed)
        XCTAssertFalse(manager.hasAppeared)
        XCTAssertEqual(manager.resourceRetryCount, 0)  // verify path does not retry

        contentController.removeScriptMessageHandler(forName: "resourceLoadError")
        contentController.removeScriptMessageHandler(forName: "resourceVerifyResult")
    }

    func testDidReceiveScriptMessage_status399DoesNotClose() {
        manager.webViewClosed = false
        manager.hasAppeared = false

        let expectation = expectation(description: "Appear block called")
        manager.appearBlock = {
            expectation.fulfill()
        }

        let config = WKWebViewConfiguration()
        let contentController = config.userContentController
        contentController.add(manager, name: "resourceLoadError")
        contentController.add(manager, name: "resourceVerifyResult")

        let webView = WKWebView(frame: .zero, configuration: config)

        let js = """
        window.webkit.messageHandlers.resourceVerifyResult.postMessage({
            results: [
                {tag: "SCRIPT", url: "https://example.com/redirect.js", status: 399}
            ]
        });
        """
        webView.evaluateJavaScript(js, completionHandler: nil)

        waitForExpectations(timeout: 3.0)
        XCTAssertTrue(manager.hasAppeared)
        XCTAssertFalse(manager.webViewClosed)

        contentController.removeScriptMessageHandler(forName: "resourceLoadError")
        contentController.removeScriptMessageHandler(forName: "resourceVerifyResult")
    }

    // MARK: - Rotation

    /// A manager holding a presented web view, without a network load.
    private func makeManagerWithWebView() -> (CountlyWebViewManager, ResizePromptSpy) {
        let m = CountlyWebViewManager()
        let spy = ResizePromptSpy(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        spy.webView = WKWebView(frame: CGRect(x: 0, y: 500, width: 393, height: 300))
        m.backgroundView = spy
        m.isFeedbackWidget = false
        return (m, spy)
    }

    /// An interface size change prompts the page; its resize_me reply is what re-places the content.
    func testRotation_promptsThePage() {
        CountlyContentBuilderInternal.sharedInstance().disableRotation = false
        let (m, spy) = makeManagerWithWebView()

        m.handleInterfaceSizeChange(CGSize(width: 852, height: 393))

        XCTAssertEqual(spy.promptCount, 1)
    }

    /// A pinned content IS re-prompted — that is what corrects a page which laid out for the wrong
    /// orientation. It is safe because the size reported to it is always portrait.
    func testRotation_disableRotationStillPromptsThePage() {
        CountlyContentBuilderInternal.sharedInstance().disableRotation = true
        let (m, spy) = makeManagerWithWebView()

        m.handleInterfaceSizeChange(CGSize(width: 852, height: 393))

        XCTAssertEqual(spy.promptCount, 1, "a pinned content must still be re-prompted")

        CountlyContentBuilderInternal.sharedInstance().disableRotation = false
    }

    /// With the portrait pin on, a landscape measurement is transposed before the page is told.
    func testPortraitAdjustedSize_transposesOnlyWhenPinned() {
        let view = PassThroughBackgroundView(frame: .zero)
        let landscape = CGSize(width: 852, height: 393)
        let portrait = CGSize(width: 393, height: 852)

        view.reportPortraitSizeOnly = false
        XCTAssertEqual(view.portraitAdjustedSize(landscape), landscape, "unpinned reports the real size")

        view.reportPortraitSizeOnly = true
        XCTAssertEqual(view.portraitAdjustedSize(landscape), portrait, "pinned transposes a landscape size")
        XCTAssertEqual(view.portraitAdjustedSize(portrait), portrait, "an already-portrait size is untouched")
    }

    /// disableRotation is content-only: a widget still rotates while content is pinned.
    func testRotation_disableRotationDoesNotAffectFeedbackWidgets() {
        CountlyContentBuilderInternal.sharedInstance().disableRotation = true
        let (m, spy) = makeManagerWithWebView()
        m.isFeedbackWidget = true

        m.handleInterfaceSizeChange(CGSize(width: 852, height: 393))

        let expected = CGRect(origin: .zero, size: CountlyCommon.sharedInstance().getWindowSize())
        XCTAssertEqual(m.backgroundView.webView.frame, expected, "a widget must not be gated by the content option")
        XCTAssertEqual(spy.promptCount, 1)

        CountlyContentBuilderInternal.sharedInstance().disableRotation = false
    }

    /// A closed web view is never prompted.
    func testRotation_closedWebViewIsNotPrompted() {
        CountlyContentBuilderInternal.sharedInstance().disableRotation = false
        let (m, spy) = makeManagerWithWebView()
        m.webViewClosed = true

        m.handleInterfaceSizeChange(CGSize(width: 852, height: 393))

        XCTAssertEqual(spy.promptCount, 0)
    }

    /// The page's resize_me reply sets the frame for the orientation it is in.
    func testResize_appliesTheGeometryThePageReports() {
        CountlyContentBuilderInternal.sharedInstance().disableRotation = false
        let (m, _) = makeManagerWithWebView()

        m.resizeWebView(withJSONString: "{\"p\":{\"x\":1,\"y\":2,\"w\":3,\"h\":4},\"l\":{\"x\":90,\"y\":90,\"w\":90,\"h\":90}}")

        XCTAssertEqual(m.backgroundView.webView.frame, CGRect(x: 1, y: 2, width: 3, height: 4))
    }

    /// disableRotation pins content to portrait even when the page reports landscape dimensions.
    func testResize_disableRotationPinsToPortraitDimensions() {
        CountlyContentBuilderInternal.sharedInstance().disableRotation = true
        let (m, _) = makeManagerWithWebView()

        // A landscape window, so the orientation pick would otherwise choose the landscape rect.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 852, height: 393))
        window.addSubview(m.backgroundView)

        m.resizeWebView(withJSONString: "{\"p\":{\"x\":1,\"y\":2,\"w\":3,\"h\":4},\"l\":{\"x\":90,\"y\":90,\"w\":90,\"h\":90}}")

        XCTAssertEqual(m.backgroundView.webView.frame, CGRect(x: 1, y: 2, width: 3, height: 4),
                       "the portrait rect must win while rotation is disabled")

        m.backgroundView.removeFromSuperview()
        CountlyContentBuilderInternal.sharedInstance().disableRotation = false
    }
}

#endif
