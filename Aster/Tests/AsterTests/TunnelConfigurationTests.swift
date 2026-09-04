import XCTest
import Libbox
@testable import Aster

final class TunnelConfigurationTests: XCTestCase {
    func testValidWebSocketConfigurationBuildsStructuredJSON() throws {
        let configuration = TunnelConfiguration(
            nodeID: "us-east-primary",
            serverAddress: "vpn.example.com",
            serverPort: 443,
            uuid: "550e8400-e29b-41d4-a716-446655440000",
            transport: .websocket,
            tlsEnabled: true,
            serverName: "vpn.example.com",
            websocketPath: "/secure",
            websocketHeaders: ["Host": "vpn.example.com"]
        )

        XCTAssertNoThrow(try configuration.validated())
        let json = try SingBoxConfigurationBuilder.makeJSON(from: configuration)
        let data = try XCTUnwrap(json.data(using: .utf8))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let inbounds = try XCTUnwrap(root["inbounds"] as? [[String: Any]])
        let outbounds = try XCTUnwrap(root["outbounds"] as? [[String: Any]])
        XCTAssertEqual(inbounds.first?["address"] as? [String], ["172.19.0.1/30", "fdfe:dcba:9876::1/126"])
        XCTAssertNil(inbounds.first?["inet4_address"])
        XCTAssertEqual(inbounds.first?["auto_route"] as? Bool, true)
        XCTAssertEqual(outbounds.first?["server"] as? String, "vpn.example.com")
        XCTAssertEqual((outbounds.first?["transport"] as? [String: Any])?["type"] as? String, "ws")

        let dns = try XCTUnwrap(root["dns"] as? [String: Any])
        let dnsServers = try XCTUnwrap(dns["servers"] as? [[String: Any]])
        XCTAssertEqual(dnsServers.first?["type"] as? String, "tcp")
        XCTAssertEqual(dnsServers.first?["server"] as? String, "1.1.1.1")
        XCTAssertEqual(dnsServers.first?["server_port"] as? Int, 53)
        XCTAssertEqual(dnsServers.first?["detour"] as? String, "proxy")

        let route = try XCTUnwrap(root["route"] as? [String: Any])
        let rules = try XCTUnwrap(route["rules"] as? [[String: Any]])
        XCTAssertEqual(rules.count, 4)
        XCTAssertEqual(rules[0]["port"] as? Int, 53)
        XCTAssertEqual(rules[0]["action"] as? String, "hijack-dns")
        XCTAssertEqual(rules[1]["protocol"] as? String, "quic")
        XCTAssertEqual(rules[1]["action"] as? String, "reject")
        XCTAssertEqual(rules[2]["network"] as? String, "udp")
        XCTAssertEqual(rules[2]["port"] as? Int, 443)
        XCTAssertEqual(rules[2]["action"] as? String, "reject")
        XCTAssertEqual(rules[3]["action"] as? String, "route-options")
        XCTAssertEqual(rules[3]["tls_record_fragment"] as? Bool, true)
    }

    func testPreResolvedEndpointIsUsedForDialWhileTLSNameIsPreserved() throws {
        let configuration = TunnelConfiguration(
            nodeID: "pre-resolved",
            serverAddress: "vpn.example.com",
            serverPort: 8443,
            uuid: "550e8400-e29b-41d4-a716-446655440000",
            tlsEnabled: true,
            serverName: "vpn.example.com",
            resolvedServerAddresses: ["203.0.113.10", "2001:db8::10"]
        )

        let outbound = try firstOutbound(configuration)
        XCTAssertEqual(outbound["server"] as? String, "203.0.113.10")
        let tls = try XCTUnwrap(outbound["tls"] as? [String: Any])
        XCTAssertEqual(tls["server_name"] as? String, "vpn.example.com")
    }

    func testResolvedEndpointMustBeNumeric() {
        let configuration = TunnelConfiguration(
            nodeID: "invalid-pre-resolved",
            serverAddress: "vpn.example.com",
            serverPort: 443,
            uuid: "550e8400-e29b-41d4-a716-446655440000",
            tlsEnabled: true,
            serverName: "vpn.example.com",
            resolvedServerAddresses: ["vpn.example.com"]
        )

        XCTAssertThrowsError(try configuration.validated()) { error in
            XCTAssertEqual(error as? TunnelConfigError, .invalidResolvedServerAddresses)
        }
    }

    func testInvalidUUIDIsRejected() {
        let configuration = TunnelConfiguration(
            nodeID: "node",
            serverAddress: "vpn.example.com",
            serverPort: 443,
            uuid: "not-a-uuid",
            tlsEnabled: true,
            serverName: "vpn.example.com"
        )

        XCTAssertThrowsError(try configuration.validated()) { error in
            XCTAssertEqual(error as? TunnelConfigError, .invalidCredential)
        }
    }

    func testTLSRequiresServerName() {
        let configuration = TunnelConfiguration(
            nodeID: "node",
            serverAddress: "vpn.example.com",
            serverPort: 443,
            uuid: "550e8400-e29b-41d4-a716-446655440000",
            tlsEnabled: true
        )

        XCTAssertThrowsError(try configuration.validated()) { error in
            XCTAssertEqual(error as? TunnelConfigError, .missingServerName)
        }
    }

    func testSchemaOneConfigurationMigratesWithoutLosingConnectionDetails() throws {
        let legacyJSON = """
        {
          "schemaVersion": 1,
          "nodeID": "legacy",
          "serverAddress": "legacy.example.com",
          "serverPort": 443,
          "uuid": "550e8400-e29b-41d4-a716-446655440000",
          "transport": "websocket",
          "tlsEnabled": true,
          "serverName": "legacy.example.com",
          "websocketPath": "/vpn",
          "websocketHeaders": {"Host": "edge.example.com"}
        }
        """

        let decoded = try JSONDecoder().decode(
            TunnelConfiguration.self,
            from: try XCTUnwrap(legacyJSON.data(using: .utf8))
        )
        let migrated = try decoded.validated()

        XCTAssertEqual(migrated.schemaVersion, TunnelConfiguration.currentSchemaVersion)
        XCTAssertEqual(migrated.protocolKind, .vless)
        XCTAssertEqual(migrated.transport, .websocket)
        XCTAssertEqual(migrated.websocketPath, "/vpn")
        XCTAssertEqual(migrated.websocketHeaders["Host"], "edge.example.com")
    }

    func testVMessConfigurationBuildsProtocolSpecificOutbound() throws {
        let configuration = TunnelConfiguration(
            nodeID: "vmess-node",
            serverAddress: "vmess.example.com",
            serverPort: 443,
            uuid: "550e8400-e29b-41d4-a716-446655440000",
            protocolKind: .vmess,
            tlsEnabled: true,
            serverName: "vmess.example.com",
            vmessSecurity: "auto",
            vmessAlterID: 0
        )

        let outbound = try firstOutbound(configuration)
        XCTAssertEqual(outbound["type"] as? String, "vmess")
        XCTAssertEqual(outbound["security"] as? String, "auto")
        XCTAssertEqual(outbound["alter_id"] as? Int, 0)
        XCTAssertNil(outbound["flow"])
    }

    func testAnyTLSConfigurationBuildsPasswordOutbound() throws {
        let configuration = TunnelConfiguration(
            nodeID: "anytls-node",
            serverAddress: "anytls.example.com",
            serverPort: 443,
            uuid: "00000000-0000-0000-0000-000000000000",
            protocolKind: .anytls,
            tlsEnabled: true,
            serverName: "anytls.example.com",
            tlsFingerprint: "chrome",
            tlsALPN: ["h2", "http/1.1"],
            anyTLSPassword: "secret-password"
        )

        let outbound = try firstOutbound(configuration)
        XCTAssertEqual(outbound["type"] as? String, "anytls")
        XCTAssertEqual(outbound["password"] as? String, "secret-password")
        XCTAssertNil(outbound["uuid"])
        let tls = try XCTUnwrap(outbound["tls"] as? [String: Any])
        XCTAssertEqual(tls["enabled"] as? Bool, true)
        XCTAssertEqual((tls["utls"] as? [String: Any])?["fingerprint"] as? String, "chrome")
        XCTAssertEqual(tls["alpn"] as? [String], ["h2", "http/1.1"])
    }

    func testRealityGRPCConfigurationBuildsNestedTLSAndTransport() throws {
        let configuration = TunnelConfiguration(
            nodeID: "reality-node",
            serverAddress: "de.example.com",
            serverPort: 443,
            uuid: "550e8400-e29b-41d4-a716-446655440000",
            transport: .grpc,
            tlsEnabled: true,
            serverName: "www.example.com",
            grpcServiceName: "aster",
            flow: "xtls-rprx-vision",
            realityPublicKey: "jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0",
            realityShortID: "0123456789abcdef",
            tlsFingerprint: "chrome"
        )

        let outbound = try firstOutbound(configuration)
        XCTAssertEqual(outbound["flow"] as? String, "xtls-rprx-vision")
        XCTAssertEqual((outbound["transport"] as? [String: Any])?["type"] as? String, "grpc")
        XCTAssertEqual((outbound["transport"] as? [String: Any])?["service_name"] as? String, "aster")
        let tls = try XCTUnwrap(outbound["tls"] as? [String: Any])
        XCTAssertEqual((tls["utls"] as? [String: Any])?["fingerprint"] as? String, "chrome")
        XCTAssertEqual(
            (tls["reality"] as? [String: Any])?["public_key"] as? String,
            "jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0"
        )
    }

    func testRealityInsecureCompatibilityFlagIsEmitted() throws {
        let configuration = TunnelConfiguration(
            nodeID: "reality-insecure-node",
            serverAddress: "reality.example.com",
            serverPort: 443,
            uuid: "550e8400-e29b-41d4-a716-446655440000",
            tlsEnabled: true,
            tlsInsecure: true,
            serverName: "www.bing.com",
            realityPublicKey: "jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0",
            realityShortID: "0123456789abcdef",
            tlsFingerprint: "chrome"
        )

        let outbound = try firstOutbound(configuration)
        let tls = try XCTUnwrap(outbound["tls"] as? [String: Any])
        XCTAssertEqual(tls["insecure"] as? Bool, true)
    }

    func testTLSInsecureFlagCannotBeUsedOutsideReality() {
        let configuration = TunnelConfiguration(
            nodeID: "ordinary-tls-insecure",
            serverAddress: "vpn.example.com",
            serverPort: 443,
            uuid: "550e8400-e29b-41d4-a716-446655440000",
            tlsEnabled: true,
            tlsInsecure: true,
            serverName: "vpn.example.com"
        )

        XCTAssertThrowsError(try configuration.validated()) { error in
            XCTAssertEqual(error as? TunnelConfigError, .invalidTLSInsecure)
        }
    }

    func testGeneratedConfigurationIsAcceptedByBundledLibbox() throws {
#if targetEnvironment(simulator) && arch(x86_64)
        throw XCTSkip(
            "The bundled Go runtime aborts inside an x86_64 XCTest host when XCTest installs signal handlers without SA_ONSTACK; run this compatibility check on arm64 and verify the tunnel on a signed device."
        )
#else
        let configuration = TunnelConfiguration(
            nodeID: "compatibility-check",
            serverAddress: "vpn.example.com",
            serverPort: 443,
            uuid: "550e8400-e29b-41d4-a716-446655440000",
            tlsEnabled: true,
            serverName: "vpn.example.com",
            tlsFingerprint: "chrome"
        )
        let json = try SingBoxConfigurationBuilder.makeJSON(from: configuration)
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let options = LibboxSetupOptions()
        options.basePath = temporaryURL.path
        options.workingPath = temporaryURL.path
        options.tempPath = temporaryURL.path
        options.logMaxLines = 0
        options.debug = false

        var setupError: NSError?
        XCTAssertTrue(
            LibboxSetup(options, &setupError),
            setupError?.localizedDescription ?? "Libbox setup failed."
        )

        var validationError: NSError?
        XCTAssertTrue(
            LibboxCheckConfig(json, &validationError),
            validationError?.localizedDescription ?? "Libbox rejected a generated uTLS configuration."
        )
#endif
    }

    private func firstOutbound(_ configuration: TunnelConfiguration) throws -> [String: Any] {
        let json = try SingBoxConfigurationBuilder.makeJSON(from: configuration)
        let data = try XCTUnwrap(json.data(using: .utf8))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let outbounds = try XCTUnwrap(root["outbounds"] as? [[String: Any]])
        return try XCTUnwrap(outbounds.first)
    }
}
