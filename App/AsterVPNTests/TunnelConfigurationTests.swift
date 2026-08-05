import XCTest
@testable import AsterVPN

final class TunnelConfigurationTests: XCTestCase {
    func testValidConfigurationRequiresServerAndNode() {
        let valid = TunnelConfiguration(
            node: VPNNode(
                id: "node-1",
                name: "Tokyo",
                region: "JP",
                host: "vpn.example.com",
                port: 443,
                protocolName: "anytls",
                password: "test-password",
                tls: true
            ),
            ownerUserIdentifier: "user-1"
        )
        let invalid = TunnelConfiguration(
            node: VPNNode(
                id: "node-2",
                name: "Invalid",
                region: "JP",
                host: " ",
                port: 443,
                protocolName: "anytls",
                password: "test-password"
            ),
            ownerUserIdentifier: ""
        )

        XCTAssertTrue(valid.isValid)
        XCTAssertFalse(invalid.isValid)
        XCTAssertEqual(valid.providerConfiguration["nodeIdentifier"] as? String, "node-1")
        XCTAssertEqual(
            valid.providerConfiguration["ownerUserIdentifier"] as? String,
            "user-1"
        )
        XCTAssertNotNil(
            valid.providerConfiguration["credentialReference"] as? String
        )
        XCTAssertNil(valid.providerConfiguration["nodeJSON"])
        XCTAssertEqual(
            valid.credentialRecord?.ownerUserIdentifier,
            "user-1"
        )
        XCTAssertEqual(valid.credentialRecord?.nodeIdentifier, "node-1")
        XCTAssertEqual(
            valid.credentialRecord?.serverAddress,
            "vpn.example.com:443"
        )
    }
}
