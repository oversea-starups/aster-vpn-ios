// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AsterLibbox",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "Libbox", targets: ["Libbox"]),
    ],
    targets: [
        .binaryTarget(
            name: "Libbox",
            url: "https://github.com/oversea-starups/aster-vpn-ios/releases/download/1.13.16-aster.1/Libbox.xcframework.zip",
            checksum: "aafddf839a8b0341b34bbc4a8e57d5f919181901f00146c01fe8558fbea1168c"
        ),
    ]
)
