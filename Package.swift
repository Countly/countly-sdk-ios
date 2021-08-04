// swift-tools-version:5.3

import PackageDescription

let package = Package(
    
    name: "Countly",

    platforms: 
    [
        .iOS(.v8),
        .macOS(.v10_10),
        .tvOS(.v9),
        .watchOS(.v2)
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
