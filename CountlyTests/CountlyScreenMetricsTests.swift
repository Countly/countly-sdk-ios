//
//  CountlyScreenMetricsTests.swift
//  CountlyTests
//
//  Covers screen-metric helpers refactored on the `mainscreen_dpc` branch:
//  - CountlyCommon.getWindowSize() — used for content/feedback view sizing.
//  - CountlyDeviceInfo.resolution() — used for the `_resolution` metric.
//
//  These tests are written to work both in a hosted XCTest bundle (where
//  UIApplication has connected window scenes) and in a logic-test bundle
//  (where no scene is attached). They assert *property* invariants rather
//  than concrete sizes so they hold across hosts and devices.
//

import XCTest
@testable import Countly

#if os(iOS)
class CountlyScreenMetricsTests: CountlyBaseTestCase {

    override func setUp() {
        super.setUp()
        Countly.sharedInstance().halt(true)
    }

    override func tearDown() {
        Countly.sharedInstance().halt(true)
        super.tearDown()
    }

    // MARK: - getWindowSize

    /**
     * Regression guard: getWindowSize must not crash and must return a
     * finite, non-negative CGSize. The `mainscreen_dpc` refactor previously
     * broke the build by referencing `size` after removing its declaration;
     * this test exists primarily so the build/runtime path stays exercised.
     */
    func test_getWindowSize_returnsFiniteNonNegativeSize() {
        let size = CountlyCommon.sharedInstance().getWindowSize()

        XCTAssertFalse(size.width.isNaN, "width should not be NaN")
        XCTAssertFalse(size.height.isNaN, "height should not be NaN")
        XCTAssertGreaterThanOrEqual(size.width, 0, "width should be >= 0")
        XCTAssertGreaterThanOrEqual(size.height, 0, "height should be >= 0")
    }

    /**
     * getWindowSize must be deterministic — repeated calls without any
     * window-scene churn should return the same value.
     */
    func test_getWindowSize_isStableAcrossCalls() {
        let first = CountlyCommon.sharedInstance().getWindowSize()
        let second = CountlyCommon.sharedInstance().getWindowSize()
        let third = CountlyCommon.sharedInstance().getWindowSize()

        XCTAssertEqual(first.width, second.width, accuracy: 0.0001)
        XCTAssertEqual(first.height, second.height, accuracy: 0.0001)
        XCTAssertEqual(second.width, third.width, accuracy: 0.0001)
        XCTAssertEqual(second.height, third.height, accuracy: 0.0001)
    }

    /**
     * If a UIWindowScene is present (hosted test), getWindowSize should not
     * exceed the underlying window's bounds — safe-area adjustments may
     * shrink the size but never grow it. If no scene is present, the
     * function returns CGSizeZero, which satisfies the same invariant.
     */
    func test_getWindowSize_doesNotExceedWindowBounds() {
        let size = CountlyCommon.sharedInstance().getWindowSize()

        if let window = firstWindow() {
            XCTAssertLessThanOrEqual(size.width, window.bounds.width,
                                     "Reported width should not exceed window width")
            XCTAssertLessThanOrEqual(size.height, window.bounds.height,
                                     "Reported height should not exceed window height")
        } else {
            XCTAssertEqual(size.width, 0, accuracy: 0.0001,
                           "Expected CGSizeZero when no window scene is attached")
            XCTAssertEqual(size.height, 0, accuracy: 0.0001,
                           "Expected CGSizeZero when no window scene is attached")
        }
    }

    // MARK: - resolution

    /**
     * resolution() must return a "WIDTHxHEIGHT" formatted string with two
     * non-negative numeric components. This is the contract consumed by the
     * `_resolution` metric and by the content-builder query parameters.
     */
    func test_resolution_isWellFormedString() {
        guard let resolution = CountlyDeviceInfo.resolution() else {
            XCTFail("resolution() returned nil on iOS")
            return
        }

        let parts = resolution.components(separatedBy: "x")
        XCTAssertEqual(parts.count, 2,
                       "Expected WIDTHxHEIGHT format, got: \(resolution)")
        guard parts.count == 2 else { return }

        guard let width = Double(parts[0]), let height = Double(parts[1]) else {
            XCTFail("resolution() components should be numeric, got: \(resolution)")
            return
        }
        XCTAssertGreaterThanOrEqual(width, 0, "resolution width should be >= 0 (got: \(resolution))")
        XCTAssertGreaterThanOrEqual(height, 0, "resolution height should be >= 0 (got: \(resolution))")
    }

    /**
     * On iOS 13+ the refactor reads bounds/scale from the first
     * UIWindowScene's window. When a scene is connected, the returned
     * string must match `bounds.size * displayScale` for that window.
     * When no scene is connected, the implementation falls through with
     * zero values and emits "0x0" — locks in the iOS 13+ no-fallback
     * behavior so regressions are visible.
     */
    func test_resolution_matchesFirstSceneOrIsZero() {
        guard let resolution = CountlyDeviceInfo.resolution() else {
            XCTFail("resolution() returned nil on iOS")
            return
        }

        if let window = firstWindow() {
            let scale = window.traitCollection.displayScale
            let expected = "\(percentG(window.bounds.width * scale))x\(percentG(window.bounds.height * scale))"
            XCTAssertEqual(resolution, expected,
                           "resolution should reflect first window scene's pixel size")
        } else {
            XCTAssertEqual(resolution, "0x0",
                           "iOS 13+ without a window scene should report 0x0 (no UIScreen fallback)")
        }
    }

    /**
     * The metrics dictionary returned by CountlyDeviceInfo.metrics()
     * must include the `_resolution` key — this is the SDK-facing
     * contract that ends up in `/i` requests.
     */
    func test_resolution_appearsInMetricsString() {
        guard let metricsString = CountlyDeviceInfo.metrics() else {
            XCTFail("metrics() returned nil")
            return
        }
        XCTAssertTrue(metricsString.contains("_resolution"),
                      "metrics() should include the _resolution key, got: \(metricsString)")
    }

    // MARK: - Helpers

    private func firstWindow() -> UIWindow? {
        if #available(iOS 13.0, *) {
            for scene in UIApplication.shared.connectedScenes {
                if let windowScene = scene as? UIWindowScene,
                   let window = windowScene.windows.first {
                    return window
                }
            }
            return nil
        } else {
            return UIApplication.shared.delegate?.window ?? nil
        }
    }

    /// Mirrors Objective-C `%g` formatting used by `CountlyDeviceInfo.resolution`.
    /// `%g` uses the shorter of `%e` or `%f`, trims trailing zeros, and drops
    /// the decimal point when not needed. `String(format:)` with `%g` matches
    /// this behavior on Apple platforms.
    private func percentG(_ value: CGFloat) -> String {
        return String(format: "%g", Double(value))
    }
}
#endif
