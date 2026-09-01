import XCTest
@testable import Aster

final class NodeSubscriptionParserTests: XCTestCase {
    private let parser = NodeSubscriptionParser()

    func testParsesPlainVLESSWebSocketAndRealityGRPCEntries() throws {
        let publicKey = "jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0"
        let text = """
        vless://550e8400-e29b-41d4-a716-446655440000@us.example.com:443?encryption=none&security=tls&type=ws&host=edge.example.com&path=%2Fsecure&sni=edge.example.com#United%20States
        vless://550e8400-e29b-41d4-a716-446655440001@de.example.com:443?encryption=none&security=reality&type=grpc&serviceName=aster&sni=www.example.com&pbk=\(publicKey)&sid=0123456789abcdef&flow=xtls-rprx-vision&fp=chrome#Germany
        """

        let result = try parser.parse(Data(text.utf8))

        XCTAssertEqual(result.nodes.count, 2)
        XCTAssertEqual(result.discardedEntryCount, 0)
        XCTAssertEqual(result.nodes[0].displayName, "United States")
        XCTAssertEqual(result.nodes[0].configuration.transport, .websocket)
        XCTAssertEqual(result.nodes[0].configuration.websocketPath, "/secure")
        XCTAssertEqual(result.nodes[0].configuration.websocketHeaders, ["Host": "edge.example.com"])
        XCTAssertEqual(result.nodes[1].configuration.transport, .grpc)
        XCTAssertEqual(result.nodes[1].configuration.grpcServiceName, "aster")
        XCTAssertEqual(result.nodes[1].configuration.realityPublicKey, publicKey)
        XCTAssertEqual(result.nodes[1].configuration.flow, "xtls-rprx-vision")
    }

    func testParsesSecureAnyTLSPasswordEntry() throws {
        let entry = "anytls://p%40ssword@example.com:443?security=tls&sni=edge.example.com&fp=chrome#Singapore"

        let result = try parser.parse(Data(entry.utf8))

        XCTAssertEqual(result.nodes.count, 1)
        XCTAssertEqual(result.discardedEntryCount, 0)
        let node = try XCTUnwrap(result.nodes.first)
        XCTAssertEqual(node.displayName, "Singapore")
        XCTAssertEqual(node.configuration.protocolKind, .anytls)
        XCTAssertEqual(node.configuration.anyTLSPassword, "p@ssword")
        XCTAssertEqual(node.configuration.serverName, "edge.example.com")
        XCTAssertEqual(node.configuration.tlsFingerprint, "chrome")
    }

    func testParsesBase64SubscriptionWithVMessAndDropsUnsupportedEntries() throws {
        let vmess: [String: Any] = [
            "v": "2",
            "ps": "Japan",
            "add": "jp.example.com",
            "port": "443",
            "id": "550e8400-e29b-41d4-a716-446655440002",
            "aid": "0",
            "net": "ws",
            "host": "cdn.example.com",
            "path": "/vpn",
            "tls": "tls",
            "sni": "cdn.example.com",
            "scy": "auto"
        ]
        let vmessData = try JSONSerialization.data(withJSONObject: vmess, options: [.sortedKeys])
        let subscription = "vmess://\(vmessData.base64EncodedString())\nss://unsupported"
        let encoded = Data(subscription.utf8).base64EncodedData()

        let result = try parser.parse(encoded)

        XCTAssertEqual(result.nodes.count, 1)
        XCTAssertEqual(result.discardedEntryCount, 1)
        let node = try XCTUnwrap(result.nodes.first)
        XCTAssertEqual(node.displayName, "Japan")
        XCTAssertEqual(node.configuration.protocolKind, .vmess)
        XCTAssertEqual(node.configuration.transport, .websocket)
        XCTAssertEqual(node.configuration.vmessSecurity, "auto")
        XCTAssertEqual(node.configuration.vmessAlterID, 0)
    }

    func testRejectsInsecureOrEntirelyUnsupportedSubscription() throws {
        let insecure = "vless://550e8400-e29b-41d4-a716-446655440000@us.example.com:443?encryption=none&security=tls&allowInsecure=1#Unsafe"
        XCTAssertThrowsError(try parser.parse(Data(insecure.utf8))) { error in
            XCTAssertEqual(error as? NodeSubscriptionError, .noSupportedLocations)
        }

        let unencryptedVLESS = "vless://550e8400-e29b-41d4-a716-446655440000@us.example.com:80?encryption=none&security=none#Plaintext"
        XCTAssertThrowsError(try parser.parse(Data(unencryptedVLESS.utf8))) { error in
            XCTAssertEqual(error as? NodeSubscriptionError, .noSupportedLocations)
        }

        let unencryptedVMess: [String: Any] = [
            "ps": "Plaintext",
            "add": "us.example.com",
            "port": 80,
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "net": "tcp",
            "tls": "none",
            "scy": "none"
        ]
        let vmessData = try JSONSerialization.data(withJSONObject: unencryptedVMess)
        let vmessEntry = "vmess://\(vmessData.base64EncodedString())"
        XCTAssertThrowsError(try parser.parse(Data(vmessEntry.utf8))) { error in
            XCTAssertEqual(error as? NodeSubscriptionError, .noSupportedLocations)
        }

        XCTAssertThrowsError(try parser.parse(Data("trojan://unsupported".utf8))) { error in
            XCTAssertEqual(error as? NodeSubscriptionError, .invalidPayload)
        }

        let insecureAnyTLS = "anytls://password@example.com:443?security=none#Plaintext"
        XCTAssertThrowsError(try parser.parse(Data(insecureAnyTLS.utf8))) { error in
            XCTAssertEqual(error as? NodeSubscriptionError, .noSupportedLocations)
        }
    }

    func testDuplicateLocationsAreDeterministicallyDeduplicated() throws {
        let entry = "vless://550e8400-e29b-41d4-a716-446655440000@us.example.com:443?encryption=none&security=tls&type=tcp&sni=us.example.com#US"
        let result = try parser.parse(Data("\(entry)\n\(entry)".utf8))

        XCTAssertEqual(result.nodes.count, 1)
        XCTAssertEqual(result.discardedEntryCount, 1)
        XCTAssertTrue(result.nodes[0].id.hasPrefix("node-"))
        XCTAssertFalse(result.nodes[0].id.contains("550e8400"))
    }

    func testStatusRecordsAreDiscardedWhileRealLocationsRemain() throws {
        let status = "vless://550e8400-e29b-41d4-a716-446655440000@status.example.com:443?encryption=none&security=tls#剩余流量：1 GB"
        let location = "vless://550e8400-e29b-41d4-a716-446655440001@us.example.com:443?encryption=none&security=tls#United%20States"

        let result = try parser.parse(Data("\(status)\n\(location)".utf8))

        XCTAssertEqual(result.nodes.count, 1)
        XCTAssertEqual(result.nodes.first?.displayName, "United States")
        XCTAssertEqual(result.discardedEntryCount, 1)
    }

    func testProviderTierAndServerLabelsAreReducedToRegionOnly() {
        XCTAssertEqual(VPNNode.regionName(from: "HK-02｜VIP🇭🇰"), "Hong Kong")
        XCTAssertEqual(VPNNode.regionName(from: "US-01｜AI专线🇺🇸"), "United States")
        XCTAssertEqual(VPNNode.regionName(from: "🏡家"), "Home")
    }

}
