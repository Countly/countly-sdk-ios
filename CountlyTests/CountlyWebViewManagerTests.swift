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

class CountlyWebViewManagerTests: XCTestCase {

    var manager: CountlyWebViewManager!

    override func setUp() {
        super.setUp()
        manager = CountlyWebViewManager()
    }

    override func tearDown() {
        manager = nil
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

    func testLoadDidTimeout_setsWebViewClosedFlag() {
        manager.webViewClosed = false
        manager.hasAppeared = false

        manager.loadDidTimeout()

        // loadDidTimeout sets webViewClosed = YES synchronously before calling closeWebView
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
        manager.webViewClosed = false
        manager.hasAppeared = false
        manager.appearBlock = nil

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
        manager.dismissBlock = {
            dismissExpectation.fulfill()
        }

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

    func testDidReceiveScriptMessage_resourceLoadError_closesWebView() {
        manager.webViewClosed = false
        manager.hasAppeared = false

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
        manager.dismissBlock = {
            dismissExpectation.fulfill()
        }

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
        manager.webViewClosed = false
        manager.hasAppeared = false

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
        manager.dismissBlock = {
            dismissExpectation.fulfill()
        }

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
}

#endif
