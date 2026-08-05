import Foundation
import XCTest
@testable import AsterVPN

final class VPNNodeTests: XCTestCase {
    func testDecodesPrismaDecimalAndLegacyStringTags() throws {
        let data = Data(
            """
            {
              "id": "node-1",
              "name": "Tokyo",
              "region": "JP",
              "host": "vpn.example.com",
              "port": 443,
              "protocol": "vmess",
              "uuid": "550e8400-e29b-41d4-a716-446655440000",
              "alterId": 0,
              "tls": true,
              "network": "ws",
              "wsPath": "/vmess",
              "protocolConfig": {"serverName": "vpn.example.com"},
              "tags": "[\\"低延迟\\",\\"流媒体\\"]",
              "rate": "1.5"
            }
            """.utf8
        )

        let node = try JSONDecoder().decode(VPNNode.self, from: data)

        XCTAssertEqual(node.normalizedProtocol, "vmess")
        XCTAssertEqual(node.tags, ["低延迟", "流媒体"])
        XCTAssertEqual(node.rate, 1.5)
        XCTAssertNil(node.configurationIssue)
    }

    func testRejectsMissingProtocolCredential() {
        let node = VPNNode(
            id: "node-1",
            name: "US",
            region: "US",
            host: "vpn.example.com",
            port: 443,
            protocolName: "trojan"
        )

        XCTAssertEqual(node.configurationIssue, "Trojan 节点缺少密码")
    }

    func testAcceptsAnyTLSWithPassword() {
        let node = VPNNode(
            id: "node-anytls",
            name: "Singapore",
            region: "SG",
            host: "vpn.example.net",
            port: 443,
            protocolName: "anytls",
            password: "test-password"
        )

        XCTAssertNil(node.configurationIssue)
    }
}
