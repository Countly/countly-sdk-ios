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
