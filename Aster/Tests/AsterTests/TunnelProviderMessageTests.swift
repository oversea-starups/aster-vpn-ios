import XCTest
@testable import Aster

final class TunnelProviderMessageTests: XCTestCase {
    func testReadinessRequestRoundTripsWithVersionedCommand() throws {
        let data = try TunnelProviderMessageCodec.makeReadinessRequest()
        let request = try TunnelProviderMessageCodec.decodeRequest(data)

        XCTAssertEqual(request.schemaVersion, 1)
        XCTAssertEqual(request.command, .readiness)
    }

    func testProviderReadinessStatusRoundTrips() throws {
        let readyData = try TunnelProviderMessageCodec.makeStatus(dataPlaneReady: true)
        let waitingData = try TunnelProviderMessageCodec.makeStatus(dataPlaneReady: false)

        XCTAssertTrue(try TunnelProviderMessageCodec.decodeStatus(readyData).dataPlaneReady)
        XCTAssertFalse(try TunnelProviderMessageCodec.decodeStatus(waitingData).dataPlaneReady)
    }
}
