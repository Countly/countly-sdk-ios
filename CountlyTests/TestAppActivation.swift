//
//  TestAppActivation.swift
//  CountlyTests
//
//  macOS-only test support.
//
//  An `xctest` process is never a frontmost `NSApplication`, so `NSApp.isActive` is
//  always false. The SDK's macOS session guard
//  (`CountlyConnectionManager.beginSession`) refuses to open a session for an app that
//  is not active, which would make every automatic-session test fail on macOS for a
//  reason that never happens in a real app — a real macOS app is active by the time it
//  calls `startWithConfig:`.
//
//  This shim lets the test bundle report the activation state it wants, so macOS runs
//  the same assertions as every other platform by default. The genuinely-inactive path
//  (session dropped at start, then recovered when the app becomes active) is asserted
//  explicitly by `CountlyPlatformLifecycleTests` by flipping `isActive` to false.
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

#endif
