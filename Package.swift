// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AlamofireNetworkActivityLogger",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "AlamofireNetworkActivityLogger",
            targets: ["AlamofireNetworkActivityLogger"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.11.1")
    ],
    targets: [
        .target(
            name: "AlamofireNetworkActivityLogger",
            dependencies: [
                .product(name: "Alamofire", package: "Alamofire")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        ),
        .testTarget(
            name: "AlamofireNetworkActivityLoggerTests",
            dependencies: ["AlamofireNetworkActivityLogger"]
        )
    ]
)
