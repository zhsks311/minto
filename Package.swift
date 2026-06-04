// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "minto2",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.10.0"),
        // 원격 MCP 서버(Notion) OAuth 2.1(DCR+PKCE)·툴 호출용 공식 SDK. pre-1.0이라 minor 고정.
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", .upToNextMinor(from: "0.12.1")),
    ],
    targets: [
        .target(
            name: "MintoCore",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "MCP", package: "swift-sdk"),
            ],
            path: "Sources/Minto",
            exclude: ["Bridge"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "minto2",
            dependencies: ["MintoCore"],
            path: "Sources/MintoApp",
            exclude: ["Info.plist"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/MintoApp/Info.plist",
                ])
            ]
        ),
        .testTarget(
            name: "MintoTests",
            dependencies: ["MintoCore"],
            path: "Tests/MintoTests"
        )
    ]
)
