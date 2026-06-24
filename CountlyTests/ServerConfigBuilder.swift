import Foundation
import XCTest

class ServerConfigBuilder {
    private var config: [String: Any] = [:]

    // MARK: - Constants

    private enum Keys {
        static let sc = "sc"
        static let tracking = "tracking"
        static let networking = "networking"
        static let timestamp = "t"
        static let version = "v"
        static let config = "c"
        static let requestQueueSize = "rqs"
        static let eventQueueSize = "eqs"
        static let logging = "log"
        static let sessionUpdateInterval = "sui"
        static let sessionTracking = "st"
        static let viewTracking = "vt"
        static let locationTracking = "lt"
        static let refreshContentZone = "rcz"
        static let limitKeyLength = "lkl"
        static let limitValueSize = "lvs"
        static let limitSegValues = "lsv"
        static let limitBreadcrumb = "lbc"
        static let limitTraceLine = "ltlpt"
        static let limitTraceLength = "ltl"
        static let customEventTracking = "cet"
        static let enterContentZone = "ecz"
        static let contentZoneInterval = "czi"
        static let consentRequired = "cr"
        static let dropOldRequestTime = "dort"
        static let crashReporting = "crt"
        static let serverConfigUpdateInterval = "scui"
        static let eventBlacklist = "eb"
        static let eventWhitelist = "ew"
        static let userPropertyBlacklist = "upb"
        static let userPropertyWhitelist = "upw"
        static let userPropertyCacheLimit = "upcl"
        static let segmentationBlacklist = "sb"
        static let segmentationWhitelist = "sw"
        static let eventSegmentationBlacklist = "esb"
        static let eventSegmentationWhitelist = "esw"
        static let journeyTriggerEvents = "jte"
    }

    // MARK: - Feature Flags

    @discardableResult
    func tracking(_ enabled: Bool) -> ServerConfigBuilder {
        config[Keys.tracking] = enabled
        return this
    }

    @discardableResult
    func networking(_ enabled: Bool) -> ServerConfigBuilder {
        config[Keys.networking] = enabled
        return this
    }

    @discardableResult
    func crashReporting(_ enabled: Bool) -> ServerConfigBuilder {
        config[Keys.crashReporting] = enabled
        return this
    }

    @discardableResult
    func viewTracking(_ enabled: Bool) -> ServerConfigBuilder {
        config[Keys.viewTracking] = enabled
        return this
    }

    @discardableResult
    func sessionTracking(_ enabled: Bool) -> ServerConfigBuilder {
        config[Keys.sessionTracking] = enabled
        return this
    }

    @discardableResult
    func customEventTracking(_ enabled: Bool) -> ServerConfigBuilder {
        config[Keys.customEventTracking] = enabled
        return this
    }

    @discardableResult
    func contentZone(_ enabled: Bool) -> ServerConfigBuilder {
        config[Keys.enterContentZone] = enabled
        return this
    }

    @discardableResult
    func locationTracking(_ enabled: Bool) -> ServerConfigBuilder {
        config[Keys.locationTracking] = enabled
        return this
    }

    @discardableResult
    func refreshContentZone(_ enabled: Bool) -> ServerConfigBuilder {
        config[Keys.refreshContentZone] = enabled
        return this
    }

    // MARK: - Listing Filters

    @discardableResult
    func eventBlacklist(_ keys: [String]) -> ServerConfigBuilder {
        config[Keys.eventBlacklist] = keys
        return this
    }

    @discardableResult
    func eventWhitelist(_ keys: [String]) -> ServerConfigBuilder {
        config[Keys.eventWhitelist] = keys
        return this
    }

    @discardableResult
    func userPropertyBlacklist(_ keys: [String]) -> ServerConfigBuilder {
        config[Keys.userPropertyBlacklist] = keys
        return this
    }

    @discardableResult
    func userPropertyWhitelist(_ keys: [String]) -> ServerConfigBuilder {
        config[Keys.userPropertyWhitelist] = keys
        return this
    }

    @discardableResult
    func userPropertyCacheLimit(_ limit: UInt) -> ServerConfigBuilder {
        config[Keys.userPropertyCacheLimit] = limit
        return this
    }

    @discardableResult
    func segmentationBlacklist(_ keys: [String]) -> ServerConfigBuilder {
        config[Keys.segmentationBlacklist] = keys
        return this
    }

    @discardableResult
    func segmentationWhitelist(_ keys: [String]) -> ServerConfigBuilder {
        config[Keys.segmentationWhitelist] = keys
        return this
    }

    @discardableResult
    func eventSegmentationBlacklist(_ map: [String: [String]]) -> ServerConfigBuilder {
        config[Keys.eventSegmentationBlacklist] = map
        return this
    }

    @discardableResult
    func eventSegmentationWhitelist(_ map: [String: [String]]) -> ServerConfigBuilder {
        config[Keys.eventSegmentationWhitelist] = map
        return this
    }

    @discardableResult
    func journeyTriggerEvents(_ keys: [String]) -> ServerConfigBuilder {
        config[Keys.journeyTriggerEvents] = keys
        return this
    }

    // MARK: - Intervals and Sizes

    @discardableResult
    func serverConfigUpdateInterval(_ interval: UInt) -> ServerConfigBuilder {
        config[Keys.serverConfigUpdateInterval] = interval
        return this
    }

    @discardableResult
    func requestQueueSize(_ size: UInt) -> ServerConfigBuilder {
        config[Keys.requestQueueSize] = size
        return this
    }

    @discardableResult
    func eventQueueSize(_ size: UInt) -> ServerConfigBuilder {
        config[Keys.eventQueueSize] = size
        return this
    }

    @discardableResult
    func logging(_ enabled: Bool) -> ServerConfigBuilder {
        config[Keys.logging] = enabled
        return this
    }

    @discardableResult
    func sessionUpdateInterval(_ interval: Int) -> ServerConfigBuilder {
        config[Keys.sessionUpdateInterval] = interval
        return this
    }

    @discardableResult
    func contentZoneInterval(_ interval: TimeInterval) -> ServerConfigBuilder {
        config[Keys.contentZoneInterval] = interval
        return this
    }

    @discardableResult
    func consentRequired(_ required: Bool) -> ServerConfigBuilder {
        config[Keys.consentRequired] = required
        return this
    }

    @discardableResult
    func dropOldRequestTime(_ time: UInt) -> ServerConfigBuilder {
        config[Keys.dropOldRequestTime] = time
        return this
    }

    // MARK: - Limits

    @discardableResult
    func limitKeyLength(_ limit: UInt) -> ServerConfigBuilder {
        config[Keys.limitKeyLength] = limit
        return this
    }

    @discardableResult
    func limitValueSize(_ limit: UInt) -> ServerConfigBuilder {
        config[Keys.limitValueSize] = limit
        return this
    }

    @discardableResult
    func limitSegmentationValues(_ limit: UInt) -> ServerConfigBuilder {
        config[Keys.limitSegValues] = limit
        return this
    }

    @discardableResult
    func limitBreadcrumb(_ limit: UInt) -> ServerConfigBuilder {
        config[Keys.limitBreadcrumb] = limit
        return this
    }

    @discardableResult
    func limitTraceLength(_ limit: UInt) -> ServerConfigBuilder {
        config[Keys.limitTraceLength] = limit
        return this
    }

    @discardableResult
    func limitTraceLines(_ limit: UInt) -> ServerConfigBuilder {
        config[Keys.limitTraceLine] = limit
        return this
    }

    // MARK: - Build Methods

    func defaults() -> ServerConfigBuilder {
        // Feature flags
        tracking(true)
        networking(true)
        crashReporting(true)
        viewTracking(true)
        sessionTracking(true)
        customEventTracking(true)
        contentZone(false)
        locationTracking(true)
        refreshContentZone(true)

        // Intervals and sizes
        serverConfigUpdateInterval(4)
        requestQueueSize(1000)
        eventQueueSize(100)
        logging(false)
        // CountlyServerConfig.sessionInterval defaults to 0 when no SBS is applied; 0 is the
        // sentinel meaning "fall back to config.updateSessionPeriod (60s)" (see CountlyServerConfig
        // populateConfig: `config.updateSessionPeriod = _sessionInterval ?: ...`). So the default
        // of the server-config field itself is 0, not 60.
        sessionUpdateInterval(0)
        contentZoneInterval(30)
        consentRequired(false)
        dropOldRequestTime(0)

        // Limits
        limitKeyLength(128)
        limitValueSize(256)
        limitSegmentationValues(100)
        limitBreadcrumb(100)
        limitTraceLength(200)
        limitTraceLines(30)

        return this
    }

    func build() -> String {
        let configDict: [String: Any] = [
            Keys.version: 1,
            Keys.timestamp: Int(Date().timeIntervalSince1970),
            Keys.config: config,
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: configDict),
            let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }

        return "{}"
    }

    func buildJson() -> [String: Any] {
        return [
            Keys.version: 1,
            Keys.timestamp: Int(Date().timeIntervalSince1970),
            Keys.config: config,
        ]
    }

    // MARK: - Validation

    func validateAgainst() {
        let moduleConfig = CountlyServerConfig.sharedInstance()
        let common = CountlyCommon.sharedInstance()
        let consentManager = CountlyConsentManager.sharedInstance()
        let persistency = CountlyPersistency.sharedInstance()
        let crashReporter = CountlyCrashReporter.sharedInstance()

        // Feature flags (only validate if explicitly set in builder)
        if let val = config[Keys.tracking] as? Bool {
            XCTAssertEqual(val, moduleConfig?.trackingEnabled())
        }
        if let val = config[Keys.networking] as? Bool {
            XCTAssertEqual(val, moduleConfig?.networkingEnabled())
        }
        if let val = config[Keys.crashReporting] as? Bool {
            XCTAssertEqual(val, moduleConfig?.crashReportingEnabled())
        }
        if let val = config[Keys.viewTracking] as? Bool {
            XCTAssertEqual(val, moduleConfig?.viewTrackingEnabled())
        }
        if let val = config[Keys.sessionTracking] as? Bool {
            XCTAssertEqual(val, moduleConfig?.sessionTrackingEnabled())
        }
        if let val = config[Keys.customEventTracking] as? Bool {
            XCTAssertEqual(val, moduleConfig?.customEventTrackingEnabled())
        }
        if let val = config[Keys.enterContentZone] as? Bool {
            XCTAssertEqual(val, moduleConfig?.enterContentZone())
        }
        if let val = config[Keys.locationTracking] as? Bool {
            XCTAssertEqual(val, moduleConfig?.locationTrackingEnabled())
        }
        if let val = config[Keys.refreshContentZone] as? Bool {
            XCTAssertEqual(val, moduleConfig?.refreshContentZoneEnabled())
        }

        // Debug mode
        if let val = config[Keys.logging] as? Bool {
            XCTAssertEqual(val, common.enableDebug)
        }

        // Limits
        if let val = config[Keys.limitKeyLength] as? UInt {
            XCTAssertEqual(val, common.maxKeyLength)
        }
        if let val = config[Keys.limitValueSize] as? UInt {
            XCTAssertEqual(val, common.maxValueLength)
        }
        if let val = config[Keys.limitSegValues] as? UInt {
            XCTAssertEqual(val, common.maxSegmentationValues)
        }
        if let val = config[Keys.limitBreadcrumb] as? UInt {
            XCTAssertEqual(val, CountlyCrashReporter.sharedInstance()?.crashLogLimit)
        }

        // Consent
        if let val = config[Keys.consentRequired] as? Bool {
            XCTAssertEqual(val, consentManager?.requiresConsent)
        }

        // Queue sizes and intervals
        if let val = config[Keys.eventQueueSize] as? UInt {
            XCTAssertEqual(val, CountlyPersistency.sharedInstance().eventSendThreshold)
        }
        if let val = config[Keys.requestQueueSize] as? UInt {
            XCTAssertEqual(val, CountlyPersistency.sharedInstance().storedRequestsLimit)
        }
        if let val = config[Keys.dropOldRequestTime] as? UInt {
            XCTAssertEqual(val, CountlyPersistency.sharedInstance().requestDropAgeHours)
        }
        if let val = config[Keys.sessionUpdateInterval] as? Int {
            XCTAssertEqual(val, moduleConfig?.sessionInterval())
        }

        #if os(iOS)
            if let val = config[Keys.contentZoneInterval] as? TimeInterval {
                XCTAssertEqual(val, CountlyContentBuilderInternal.sharedInstance().zoneTimerInterval)
            }
        #endif

        // User property cache limit
        if let upcl = config[Keys.userPropertyCacheLimit] as? UInt {
            XCTAssertEqual(Int(upcl), moduleConfig?.userPropertyCacheLimit())
        }

        // Listing filter validation: event filter
        if let eventBlacklist = config[Keys.eventBlacklist] as? [String] {
            XCTAssertFalse(moduleConfig!.shouldRecordEvent(eventBlacklist.first ?? ""))
            XCTAssertTrue(moduleConfig!.shouldRecordEvent("nonexistent_event_xyz"))
        } else if let eventWhitelist = config[Keys.eventWhitelist] as? [String] {
            XCTAssertTrue(moduleConfig!.shouldRecordEvent(eventWhitelist.first ?? ""))
            XCTAssertFalse(moduleConfig!.shouldRecordEvent("nonexistent_event_xyz"))
        }

        // User property filter
        if let userPropertyBlacklist = config[Keys.userPropertyBlacklist] as? [String] {
            XCTAssertFalse(moduleConfig!.shouldRecordUserProperty(userPropertyBlacklist.first ?? ""))
            XCTAssertTrue(moduleConfig!.shouldRecordUserProperty("nonexistent_prop_xyz"))
        } else if let userPropertyWhitelist = config[Keys.userPropertyWhitelist] as? [String] {
            XCTAssertTrue(moduleConfig!.shouldRecordUserProperty(userPropertyWhitelist.first ?? ""))
            XCTAssertFalse(moduleConfig!.shouldRecordUserProperty("nonexistent_prop_xyz"))
        }

        // Journey trigger events
        if let journeyTriggerEvents = config[Keys.journeyTriggerEvents] as? [String] {
            for key in journeyTriggerEvents {
                XCTAssertTrue(moduleConfig!.isJourneyTriggerEvent(key))
            }
            XCTAssertFalse(moduleConfig!.isJourneyTriggerEvent("nonexistent_jte_xyz"))
        }
    }

    // MARK: - Helper Methods

    private var this: ServerConfigBuilder {
        return self
    }
}
