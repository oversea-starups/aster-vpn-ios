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
            url: "https://github.com/oversea-starups/aster-vpn-ios/releases/download/1.13.16-aster.2/Libbox.xcframework.zip",
            checksum: "a2a0ba688e6b234666da6cda52a4bd7e15bd4620b23f4b14271c65a85bf0b77b"
        ),
    ]
)
