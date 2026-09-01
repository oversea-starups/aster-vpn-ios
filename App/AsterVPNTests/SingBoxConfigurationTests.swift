import Foundation
import XCTest
@testable import AsterVPN

final class SingBoxConfigurationTests: XCTestCase {
    func testBuildsVMessWebSocketConfiguration() throws {
        let node = VPNNode(
            id: "vmess-1",
            name: "VMess",
            region: "US",
            host: "vpn.example.net",
            port: 443,
            protocolName: "vmess",
            method: "auto",
            uuid: "550e8400-e29b-41d4-a716-446655440000",
            tls: true,
            network: "ws",
            webSocketPath: "/edge",
            protocolConfiguration: .object([
                "serverName": .string("cdn.example.net"),
                "wsHost": .string("cdn.example.net"),
            ])
        )

        let outbound = try outbound(from: node)

        XCTAssertEqual(outbound["type"] as? String, "vmess")
        XCTAssertEqual(outbound["security"] as? String, "auto")
        let transport = try XCTUnwrap(outbound["transport"] as? [String: Any])
        XCTAssertEqual(transport["type"] as? String, "ws")
        XCTAssertEqual(transport["path"] as? String, "/edge")
        let tls = try XCTUnwrap(outbound["tls"] as? [String: Any])
        XCTAssertEqual(tls["server_name"] as? String, "cdn.example.net")
    }

    func testBuildsVLESSRealityVisionConfiguration() throws {
        let node = VPNNode(
            id: "vless-1",
            name: "VLESS",
            region: "JP",
            host: "203.0.113.10",
            port: 443,
            protocolName: "vless",
            uuid: "550e8400-e29b-41d4-a716-446655440000",
            network: "tcp",
            protocolConfiguration: .object([
                "flow": .string("xtls-rprx-vision"),
                "serverName": .string("www.example.org"),
                "publicKey": .string("public-key"),
                "shortId": .string("0123456789abcdef"),
                "clientFingerprint": .string("chrome"),
            ])
        )

        let outbound = try outbound(from: node)

        XCTAssertEqual(outbound["type"] as? String, "vless")
        XCTAssertEqual(outbound["flow"] as? String, "xtls-rprx-vision")
        let tls = try XCTUnwrap(outbound["tls"] as? [String: Any])
        let reality = try XCTUnwrap(tls["reality"] as? [String: Any])
        XCTAssertEqual(reality["enabled"] as? Bool, true)
        XCTAssertEqual(reality["public_key"] as? String, "public-key")
        XCTAssertEqual(reality["short_id"] as? String, "0123456789abcdef")
    }

    func testBuildsAnyTLSConfiguration() throws {
        let node = VPNNode(
            id: "anytls-1",
            name: "AnyTLS",
            region: "SG",
            host: "vpn.example.net",
            port: 443,
            protocolName: "anytls",
            password: "password",
            protocolConfiguration: .object([
                "sni": .string("edge.example.net"),
                "client-fingerprint": .string("chrome"),
                "idleSessionTimeout": .string("30s"),
            ])
        )

        let outbound = try outbound(from: node)

        XCTAssertEqual(outbound["type"] as? String, "anytls")
        XCTAssertEqual(outbound["password"] as? String, "password")
        XCTAssertEqual(outbound["idle_session_timeout"] as? String, "30s")
        let tls = try XCTUnwrap(outbound["tls"] as? [String: Any])
        XCTAssertEqual(tls["enabled"] as? Bool, true)
        XCTAssertEqual(tls["server_name"] as? String, "edge.example.net")
    }

    private func outbound(from node: VPNNode) throws -> [String: Any] {
        let content = try SingBoxConfigurationBuilder.makeConfiguration(for: node)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any]
        )
        let outbounds = try XCTUnwrap(object["outbounds"] as? [[String: Any]])
        return try XCTUnwrap(outbounds.first)
    }
}
