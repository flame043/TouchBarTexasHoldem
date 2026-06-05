// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TouchBarTexasHoldem",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .executable(name: "TouchBarTexasHoldem", targets: ["TouchBarTexasHoldem"])
    ],
    targets: [
        .executableTarget(
            name: "TouchBarTexasHoldem",
            path: "Sources/TouchBarTexasHoldem"
        )
    ]
)
