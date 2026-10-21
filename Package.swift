// swift-tools-version:5.9

import PackageDescription

let package = Package(
    
    name: "Countly",

    platforms: 
    [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v9),
        .visionOS(.v1)
    ],
 
    products: 
    [
        .library(
            name: "Countly",
            targets: ["Countly"]),
    ],
        
    targets: 
    [
        .target( 
            name: "Countly", 
            dependencies: [],
            path: ".",

            exclude: 
            [
                "Info.plist",
                "Countly.podspec",
                "Countly-PL.podspec",
                "LICENSE",
                "README.md",
                "countly_dsym_uploader.sh",
                "format.sh",
                "CHANGELOG.md",
                "SECURITY.md",
                "CountlyTests/"
            ],

            resources:
            [
                .copy("PrivacyInfo.xcprivacy")
            ],

            linkerSettings: 
            [
                .linkedFramework("Foundation"),
                .linkedFramework("UIKit", .when(platforms: [.iOS, .tvOS, .visionOS])),
                .linkedFramework("WatchKit", .when(platforms: [.watchOS])),
                .linkedFramework("WatchConnectivity", .when(platforms: [.iOS, .watchOS])),
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("IOKit", .when(platforms: [.macOS])),
                .linkedFramework("UserNotifications", .when(platforms: [.iOS, .macOS, .visionOS])),
                .linkedFramework("CoreLocation"),
                .linkedFramework("WebKit", .when(platforms: [.iOS, .visionOS])),
                .linkedFramework("CoreTelephony", .when(platforms: [.iOS])),
            ]),
        .testTarget(
            name: "CountlyTests",
            dependencies: ["Countly"]
        ),
    ]
)
