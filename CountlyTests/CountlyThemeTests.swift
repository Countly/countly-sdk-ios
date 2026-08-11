//
//  CountlyThemeTests.swift
//  CountlyTests
//
//  Covers the theme ("th") reporting added to the URLs loaded into the WebView for feedback
//  widgets, rating widgets, and content. The logic lives in CountlyDeviceInfo:
//   - themeMode: resolves the app's current interface style to "d"/"l"/nil.
//   - URLString(_:byAppendingThemeMode:): the pure separator/omission primitive.
//   - URLStringByAppendingThemeMode(_:): the convenience that resolves themeMode and appends.
//
//  The primitive is tested deterministically (theme passed explicitly). themeMode itself is
//  environment-dependent, so it is tested for invariants plus, when a key window is available,
//  driven deterministically through overrideUserInterfaceStyle.
//

import XCTest
@testable import Countly

#if os(iOS)
class CountlyThemeTests: CountlyBaseTestCase {

    // MARK: - URLString(_:byAppendingThemeMode:) — deterministic primitive

    /// The separator depends on whether the URL already has a query, and the resolved theme value
    /// is echoed verbatim. Covers dark/light across both separator cases in one flow.
    func test_appendThemeMode_appliesCorrectSeparatorAndValue() {
        // no existing query -> "?"
        XCTAssertEqual(
            CountlyDeviceInfo.urlString("https://c.ly/feedback/nps", byAppendingThemeMode: "d"),
            "https://c.ly/feedback/nps?th=d")
        // existing query -> "&"
        XCTAssertEqual(
            CountlyDeviceInfo.urlString("https://c.ly/feedback/nps?widget_id=abc&app_key=k", byAppendingThemeMode: "d"),
            "https://c.ly/feedback/nps?widget_id=abc&app_key=k&th=d")
        // light value is echoed just the same
        XCTAssertEqual(
            CountlyDeviceInfo.urlString("https://c.ly/o/feedback/widget?a=1", byAppendingThemeMode: "l"),
            "https://c.ly/o/feedback/widget?a=1&th=l")
    }

    /// When the theme can not be resolved (nil) or is empty, the URL must be returned untouched -
    /// no dangling "?th=" or "&th=".
    func test_appendThemeMode_omittedWhenThemeUndefined() {
        let withQuery = "https://c.ly/content?cid=1"
        let withoutQuery = "https://c.ly/content"

        XCTAssertEqual(CountlyDeviceInfo.urlString(withQuery, byAppendingThemeMode: nil), withQuery)
        XCTAssertEqual(CountlyDeviceInfo.urlString(withoutQuery, byAppendingThemeMode: nil), withoutQuery)
        XCTAssertEqual(CountlyDeviceInfo.urlString(withQuery, byAppendingThemeMode: ""), withQuery)
    }

    // MARK: - themeMode — invariants that hold in any test host

    /// themeMode must only ever return "d", "l", or nil, and the convenience appender must be
    /// exactly equivalent to feeding themeMode into the primitive.
    func test_themeMode_isConstrainedAndConvenienceIsConsistent() {
        let mode = CountlyDeviceInfo.themeMode()
        if let mode = mode {
            XCTAssertTrue(mode == "d" || mode == "l", "themeMode must be d, l, or nil; got \(mode)")
        }

        let url = "https://c.ly/feedback/rating?widget_id=abc"
        XCTAssertEqual(
            CountlyDeviceInfo.urlStringByAppendingThemeMode(url),
            CountlyDeviceInfo.urlString(url, byAppendingThemeMode: mode),
            "the convenience method must resolve themeMode and delegate to the primitive")
    }

    // MARK: - themeMode — deterministic via window override (hosted test only)

    /// Forcing the key window's interface style must flip themeMode and, through it, the appended
    /// parameter. Skipped when the test host has no key window (logic-test bundle).
    func test_themeMode_reflectsWindowInterfaceStyleOverride() throws {
        guard #available(iOS 13.0, *), let window = Self.firstKeyWindow() else {
            throw XCTSkip("requires iOS 13+ and a hosted key window")
        }

        let original = window.overrideUserInterfaceStyle
        defer {
            window.overrideUserInterfaceStyle = original
            Self.settle()
        }

        window.overrideUserInterfaceStyle = .dark
        Self.settle()
        XCTAssertEqual(CountlyDeviceInfo.themeMode(), "d")
        XCTAssertEqual(
            CountlyDeviceInfo.urlStringByAppendingThemeMode("https://c.ly/feedback/nps?widget_id=x"),
            "https://c.ly/feedback/nps?widget_id=x&th=d")

        window.overrideUserInterfaceStyle = .light
        Self.settle()
        XCTAssertEqual(CountlyDeviceInfo.themeMode(), "l")
        XCTAssertEqual(
            CountlyDeviceInfo.urlStringByAppendingThemeMode("https://c.ly/content"),
            "https://c.ly/content?th=l")
    }

    // MARK: - helpers

    @available(iOS 13.0, *)
    private static func firstKeyWindow() -> UIWindow? {
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene {
                return windowScene.windows.first
            }
        }
        return nil
    }

    /// Let UIKit propagate the trait-collection change before reading it back.
    private static func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
}
#endif
