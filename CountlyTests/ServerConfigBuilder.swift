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
        sessionUpdateInterval(60)
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
            Keys.config: config
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
            Keys.config: config
        ]
    }
    
    // MARK: - Validation
    
    func validateAgainst() {
        let moduleConfig = CountlyServerConfig.sharedInstance()
        let common = CountlyCommon.sharedInstance()
        let consentManager = CountlyConsentManager.sharedInstance()
        let persistency = CountlyPersistency.sharedInstance()
        let crashReporter = CountlyCrashReporter.sharedInstance()
        
        // Feature flags
        XCTAssertEqual(config[Keys.tracking] as? Bool, moduleConfig?.trackingEnabled())
        XCTAssertEqual(config[Keys.networking] as? Bool, moduleConfig?.networkingEnabled())
        XCTAssertEqual(config[Keys.crashReporting] as? Bool, moduleConfig?.crashReportingEnabled())
        XCTAssertEqual(config[Keys.viewTracking] as? Bool, moduleConfig?.viewTrackingEnabled())
        XCTAssertEqual(config[Keys.sessionTracking] as? Bool, moduleConfig?.sessionTrackingEnabled())
        XCTAssertEqual(config[Keys.customEventTracking] as? Bool, moduleConfig?.customEventTrackingEnabled())
        XCTAssertEqual(config[Keys.enterContentZone] as? Bool, moduleConfig?.enterContentZone())
        XCTAssertEqual(config[Keys.locationTracking] as? Bool, moduleConfig?.locationTrackingEnabled())
        XCTAssertEqual(config[Keys.refreshContentZone] as? Bool, moduleConfig?.refreshContentZoneEnabled())
        
        // Debug mode
        XCTAssertEqual(config[Keys.logging] as? Bool, common.enableDebug)
        
        // Limits
        XCTAssertEqual(config[Keys.limitKeyLength] as? UInt, common.maxKeyLength)
        XCTAssertEqual(config[Keys.limitValueSize] as? UInt, common.maxValueLength)
        XCTAssertEqual(config[Keys.limitSegValues] as? UInt, common.maxSegmentationValues)
        XCTAssertEqual(config[Keys.limitBreadcrumb] as? UInt, CountlyCrashReporter.sharedInstance()?.crashLogLimit)
        
        // Consent
        XCTAssertEqual(config[Keys.consentRequired] as? Bool, consentManager?.requiresConsent)
        
        // Queue sizes and intervals
        XCTAssertEqual(config[Keys.eventQueueSize] as? UInt, CountlyPersistency.sharedInstance().eventSendThreshold)
        XCTAssertEqual(config[Keys.requestQueueSize] as? UInt, CountlyPersistency.sharedInstance().storedRequestsLimit)
        XCTAssertEqual(config[Keys.dropOldRequestTime] as? UInt, CountlyPersistency.sharedInstance().requestDropAgeHours)
        XCTAssertEqual(config[Keys.sessionUpdateInterval] as? Int, moduleConfig?.sessionInterval())
        
        #if os(iOS)
        XCTAssertEqual(config[Keys.contentZoneInterval] as? TimeInterval, CountlyContentBuilderInternal.sharedInstance().zoneTimerInterval)
        
#endif
    }
    
    // MARK: - Helper Methods
    
    private var this: ServerConfigBuilder {
        return self
    }
} 
