// swift-tools-version:5.3

import PackageDescription

let package = Package(
    
    name: "Countly",

    platforms: 
    [
        .iOS(.v10),
        .macOS(.v10_14),
        .tvOS(.v10),
        .watchOS(.v4)
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
                "LICENSE.md",
                "README.md",
                "countly_dsym_uploader.sh",
                "CHANGELOG.md",
                "SECURITY.md"
            ],

            linkerSettings: 
            [
                .linkedFramework("Foundation"),
                .linkedFramework("UIKit", .when(platforms: [.iOS, .tvOS])),
                .linkedFramework("WatchKit", .when(platforms: [.watchOS])),
                .linkedFramework("WatchConnectivity", .when(platforms: [.iOS, .watchOS])),
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("IOKit", .when(platforms: [.macOS])),
                .linkedFramework("UserNotifications", .when(platforms: [.iOS, .macOS])),
                .linkedFramework("CoreLocation"),
                .linkedFramework("WebKit", .when(platforms: [.iOS])),
                .linkedFramework("CoreTelephony", .when(platforms: [.iOS])),
            ]),
    ]
)
