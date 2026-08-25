//
//  TestPlatform.swift
//  CountlyTests
//
//  What the SDK is expected to do on the platform this bundle is compiled for.
//
//  Every constant here mirrors a `TARGET_OS_*` guard in the SDK sources, so a guard changing
//  without this changing is a test failure rather than a silent behaviour drift. Tests read
//  from here instead of carrying their own per-platform copies.
//

import XCTest

@testable import Countly

enum TestPlatform {

    // MARK: - Identity

    /// `_os` metric, from `CountlyDeviceInfo.osName`.
    #if os(iOS)
        static let osName = "iOS"
    #elseif os(watchOS)
        static let osName = "watchOS"
    #elseif os(tvOS)
        static let osName = "tvOS"
    #elseif os(macOS)
        static let osName = "macOS"
    #elseif os(visionOS)
        static let osName = "visionOS"
    #endif

    /// `_device_type` metric, from `CountlyDeviceInfo.deviceType`. iOS reports the UI idiom,
    /// so every value it can produce is accepted there.
    #if os(iOS)
        static let deviceTypes: Set<String> = ["mobile", "tablet", "desktop"]
    #elseif os(watchOS)
        static let deviceTypes: Set<String> = ["wearable"]
    #elseif os(tvOS)
        static let deviceTypes: Set<String> = ["smarttv"]
    #elseif os(macOS)
        static let deviceTypes: Set<String> = ["desktop"]
    #elseif os(visionOS)
        static let deviceTypes: Set<String> = ["vr"]
    #endif

    /// `Countly.deviceIDType` when the host app supplies no device ID, and the `t` request
    /// parameter that goes with it. These two always change together.
    #if os(iOS) || os(tvOS) || os(visionOS)
        static let defaultDeviceIDType = CLYDeviceIDType.IDFV
        static let defaultDeviceIDTypeValue = "1"  // CLYDeviceIDTypeValueIDFV
    #else
        static let defaultDeviceIDType = CLYDeviceIDType.NSUUID
        static let defaultDeviceIDTypeValue = "2"  // CLYDeviceIDTypeValueNSUUID
    #endif

    /// `CountlyConfig.updateSessionPeriod` default: 20s on watchOS, 60s elsewhere.
    #if os(watchOS)
        static let defaultUpdateSessionPeriod: Double = 20.0
    #else
        static let defaultUpdateSessionPeriod: Double = 60.0
    #endif

    /// Where `Countly.dat` is written. tvOS has no Application Support directory.
    #if os(tvOS)
        static let storageDirectory = FileManager.SearchPathDirectory.cachesDirectory
    #else
        static let storageDirectory = FileManager.SearchPathDirectory.applicationSupportDirectory
    #endif

    // MARK: - Metrics

    /// `_resolution` / `_density` need a screen API. `CountlyDeviceInfo` has no visionOS branch.
    #if os(visionOS)
        static let reportsScreenMetrics = false
    #else
        static let reportsScreenMetrics = true
    #endif

    /// `_carrier` is CoreTelephony-backed, so iOS only, and not Mac Catalyst.
    #if os(iOS) && !targetEnvironment(macCatalyst)
        static let reportsCarrier = true
    #else
        static let reportsCarrier = false
    #endif

    // MARK: - Feature surface

    /// Feedback widgets, the star rating dialog and the content zone are WebKit-backed:
    /// `TARGET_OS_IOS || TARGET_OS_VISION`.
    #if os(iOS) || os(visionOS)
        static let hasWebKitFeatures = true
    #else
        static let hasWebKitFeatures = false
    #endif

    /// Push notifications: `TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_OSX`.
    #if os(iOS) || os(visionOS) || os(macOS)
        static let hasPushNotifications = true
    #else
        static let hasPushNotifications = false
    #endif

    /// The auto-view-tracking *public API* is declared for
    /// `TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_TV`.
    #if os(iOS) || os(tvOS) || os(visionOS)
        static let hasAutoViewTrackingAPI = true
    #else
        static let hasAutoViewTrackingAPI = false
    #endif

    /// Whether it is actually implemented. It swizzles `UIViewController` and is compiled only
    /// for iOS and tvOS, so on visionOS the public API is a logged no-op. The two must be
    /// tracked separately: every call site that reaches the internal methods has to be guarded
    /// to the narrower set, or a consent change is an unrecognized-selector crash.
    #if os(iOS) || os(tvOS)
        static let hasAutoViewTracking = true
    #else
        static let hasAutoViewTracking = false
    #endif

    // MARK: - Test environment capabilities

    /// Whether a custom `URLProtocol` registered through
    /// `URLSessionConfiguration.protocolClasses` actually intercepts the SDK's requests.
    ///
    /// watchOS hands URLSession traffic to a system proxy daemon (requests show up as
    /// `PDTask` in the log and reach the real network), so custom protocol classes are never
    /// consulted. Verified on the watchOS 26 simulator. Any test that fakes an HTTP response,
    /// or that depends on requests draining, has to be skipped there.
    #if os(watchOS)
        static let canInterceptHTTP = false
    #else
        static let canInterceptHTTP = true
    #endif

    /// Throws `XCTSkip` where `canInterceptHTTP` is false.
    static func skipUnlessHTTPInterceptable() throws {
        if !canInterceptHTTP {
            throw XCTSkip(
                "Custom URLProtocol interception does not work on \(osName); "
                    + "URLSession traffic is proxied by the system.")
        }
    }
}
