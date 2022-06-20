//
// Wire
// Copyright (C) 2022 Wire Swiss GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
//

import Foundation
@testable import WireRequestStrategy

class ClaimMLSKeyPackageActionHandlerTests: ActionHandlerTestBase<ClaimMLSKeyPackageAction, ClaimMLSKeyPackageActionHandler> {

    let domain = "example.com"
    let userId = UUID()
    let excludedSelfCliendId = UUID().transportString()
    let clientId = UUID().transportString()

    override func setUp() {
        super.setUp()
        action = ClaimMLSKeyPackageAction(
            domain: domain,
            userId: userId
        )
    }

    // MARK: - Request generation

    func test_itGenerateARequest() throws {
        try test_itGeneratesARequest(
            for: ClaimMLSKeyPackageAction(
                domain: domain,
                userId: userId,
                excludedSelfClientId: excludedSelfCliendId
            ),
            expectedPath: "/v1/mls/key-packages/claim/\(domain)/\(userId.transportString())",
            expectedPayload: ["skip_own": excludedSelfCliendId],
            expectedMethod: .methodPOST,
            apiVersion: .v1
        )
    }

    func test_itDoesntGenerateARequest_WhenAPIVersionIsNotSupported() {
        test_itDoesntGenerateARequest(
            action: ClaimMLSKeyPackageAction(domain: domain, userId: userId, excludedSelfClientId: excludedSelfCliendId),
            apiVersion: .v0
        ) {
            guard case .failure(.endpointUnavailable) = $0 else { return false }
            return true
        }
    }

    func test_itDoesntGenerateARequest_WhenDomainIsMissing() {
        APIVersion.domain = nil

        test_itDoesntGenerateARequest(
            action: ClaimMLSKeyPackageAction(domain: "", userId: userId, excludedSelfClientId: excludedSelfCliendId),
            apiVersion: .v1
        ) {
            guard case .failure(.missingDomain) = $0 else { return false }
            return true
        }
    }

    // MARK: - Response handling

    func test_itHandlesResponse_200() {
        let keyPackage = KeyPackage(
            client: clientId,
            domain: domain,
            keyPackage: "a2V5IHBhY2thZ2UgZGF0YQo=",
            keyPackageRef: "string",
            userID: userId
        )
        var receivedKeyPackages = [KeyPackage]()

        // When / Then
        test_itHandlesResponse(
            status: 200,
            payload: transportData(for: Payload(keyPackages: [keyPackage]))
        ) {
            guard case .success(let keyPackages) = $0 else { return false }
            receivedKeyPackages = keyPackages
            return true
        }

        XCTAssertEqual(receivedKeyPackages.count, 1)
        XCTAssertEqual(receivedKeyPackages.first, keyPackage)
    }

    func test_itHandlesResponse_200_MalformedResponse() {
        test_itHandlesResponse(status: 200) {
            guard case .failure(.malformedResponse) = $0 else { return false }
            return true
        }
    }

    func test_itHandlesResponse_400() {
        test_itHandlesResponse(status: 400) {
            guard case .failure(.invalidSelfClientId) = $0 else { return false }
            return true
        }
    }

    func test_itHandlesResponse_404() {
        test_itHandlesResponse(status: 404) {
            guard case .failure(.userOrDomainNotFound) = $0 else { return false }
            return true
        }
    }

    func test_itHandlesResponse_UnkownError() {
        test_itHandlesResponse(status: 999) {
            guard case .failure(.unknown(status: 999)) = $0 else { return false }
            return true
        }
    }

    // MARK: - Helpers

    private typealias Payload = ClaimMLSKeyPackageActionHandler.ResponsePayload

    private func transportData(for payload: Payload?) -> ZMTransportData? {
        let data = try! JSONEncoder().encode(payload)
        return String(bytes: data, encoding: .utf8) as ZMTransportData?
    }
}
