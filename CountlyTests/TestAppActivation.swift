//
//  TestAppActivation.swift
//  CountlyTests
//
//  Test support for the SDK's foreground guards.
//
//  `CountlyConnectionManager.beginSession` refuses to open an automatic session for an app
//  that is not in the foreground: on macOS while `NSApp.isActive` is false, and on iOS, tvOS
//  and visionOS while `UIApplication.applicationState` is `.background`. Inside a test run
//  what those report depends on how the bundle is hosted, never on the test itself:
//
//  - macOS: an `xctest` process is never a frontmost `NSApplication`, so `NSApp.isActive`
//    is always false.
//  - iOS: run hostless on a simulator, the bundle reads as active. Packaged into an
//    `XCTRunner` app, as the device farm runs it on a phone, the runner is a real application
//    that testmanagerd launches without bringing it to the foreground, so it reads
//    `.background`. Every automatic `begin_session` is then dropped, and a test that indexes
//    the request queue by position reads past its end and traps the whole runner.
//
//  Either way the automatic-session tests would fail for a reason that never happens in a
//  real app, which is in the foreground by the time it calls `startWithConfig:`.
//
//  This shim lets the test bundle report the activation state it wants, so every platform
//  and host runs the same assertions by default. The genuinely-inactive macOS path (session
//  dropped at start, then recovered when the app becomes active) is asserted explicitly by
//  `CountlyPlatformLifecycleTests` by flipping `isActive` to false.
//

#if os(macOS)

    import AppKit
    import ObjectiveC

    enum TestAppActivation {

        /// What `NSApp.isActive` reports to the SDK. Reset to `true` before every test.
        /// Writing it installs the stub, so there is no install-before-use ordering to get
        /// wrong from the various test base classes.
        static var isActive: Bool = true {
            didSet { _ = installed }
        }

        /// Swaps `NSApplication.isActive` for a stub backed by `isActive`. Idempotent.
        static func installIfNeeded() {
            _ = installed
        }

        private static let installed: Bool = {
            // Make sure the shared application exists before touching its class.
            _ = NSApplication.shared
            guard
                let original = class_getInstanceMethod(
                    NSApplication.self, #selector(getter:NSApplication.isActive)),
                let stub = class_getInstanceMethod(
                    NSApplication.self, #selector(getter:NSApplication.cly_testIsActive))
            else {
                return false
            }
            method_exchangeImplementations(original, stub)
            return true
        }()
    }

    extension NSApplication {
        @objc dynamic var cly_testIsActive: Bool {
            return TestAppActivation.isActive
        }
    }

#elseif os(iOS) || os(tvOS) || os(visionOS)

    import ObjectiveC
    import UIKit

    enum TestAppActivation {

        /// Whether `UIApplication.applicationState` reports `.active` (true) or `.background`
        /// (false) to the SDK. Reset to `true` before every test. Writing it installs the stub,
        /// so there is no install-before-use ordering to get wrong from the various test base
        /// classes.
        static var isActive: Bool = true {
            didSet { _ = installed }
        }

        /// Swaps `UIApplication.applicationState` for a stub backed by `isActive`. Idempotent.
        static func installIfNeeded() {
            _ = installed
        }

        // No `UIApplication.shared` here, unlike macOS: a hostless simulator run has none.
        private static let installed: Bool = {
            guard
                let original = class_getInstanceMethod(
                    UIApplication.self, #selector(getter:UIApplication.applicationState)),
                let stub = class_getInstanceMethod(
                    UIApplication.self, #selector(getter:UIApplication.cly_testApplicationState))
            else {
                return false
            }
            method_exchangeImplementations(original, stub)
            return true
        }()
    }

    extension UIApplication {
        /// Stands in for `applicationState` once swapped, reporting the state chosen through
        /// `TestAppActivation.isActive` instead of where the test host really is.
        @objc dynamic var cly_testApplicationState: UIApplication.State {
            return TestAppActivation.isActive ? .active : .background
        }
    }

#endif
