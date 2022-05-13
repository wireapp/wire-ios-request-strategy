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

class GetPushTokensActionHandlerTests: MessagingTestBase {

    // MARK: - Helpers

    typealias Payload = GetPushTokensActionHandler.ResponsePayload
    typealias Token = GetPushTokensActionHandler.Token

    let token = Data([0x01, 0x02, 0x03]).zmHexEncodedString()

    lazy var apns = Token(app: "app", client: "client1", token: token, transport: "APNS")
    lazy var apnsSandbox = Token(app: "app", client: "client2", token: token, transport: "APNS_SANDBOX")
    lazy var voIP = Token(app: "app", client: "client3", token: token, transport: "APNS_VOIP")
    lazy var voIPSandbox = Token(app: "app", client: "client4", token: token, transport: "APNS_VOIP_SANDBOX")
    lazy var gcm = Token(app: "app", client: "client5", token: token, transport: "GCM")

    func token(withData data: Data, type: String) -> Token {
        return Token(app: "app", client: "client", token: data.zmHexEncodedString(), transport: type)
    }

    func response(payload: GetPushTokensActionHandler.ResponsePayload, status: Int) -> ZMTransportResponse {
        let data = try! JSONEncoder().encode(payload)
        let payloadAsString = String(bytes: data, encoding: .utf8)!
        return response(payload: payloadAsString as ZMTransportData, status: status)
    }

    func response(payload: ZMTransportData?, status: Int) -> ZMTransportResponse {
        return ZMTransportResponse(
            payload: payload,
            httpStatus: status,
            transportSessionError: nil,
            apiVersion: APIVersion.v0.rawValue
        )
    }

    // MARK: - Request generation

    func test_itGeneratesARequest() throws {
        // Given
        let sut = GetPushTokensActionHandler(context: syncMOC)
        let action = GetPushTokensAction()

        // When
        let request = try XCTUnwrap(sut.request(for: action, apiVersion: .v0))

        // Then
        XCTAssertEqual(request.path, "/push/tokens")
        XCTAssertEqual(request.method, .methodGET)
    }

    // MARK: - Response handling

    func test_itHandlesResponse_200() throws {
        // Given
        let sut = GetPushTokensActionHandler(context: syncMOC)
        var action = GetPushTokensAction()

        // Expectation
        let didSucceed = expectation(description: "didSucceed")
        var receivedTokens = [PushToken]()

        action.onResult { result in
            guard case .success(let tokens) = result else { return }
            receivedTokens = tokens
            didSucceed.fulfill()
        }

        // When
        let payload = Payload(tokens: [
            token(withData: Data([0x01, 0x01, 0x01]), type: "APNS"),
            token(withData: Data([0x02, 0x02, 0x02]), type: "APNS_SANDBOX"),
            token(withData: Data([0x03, 0x03, 0x03]), type: "APNS_VOIP"),
            token(withData: Data([0x04, 0x04, 0x04]), type: "APNS_VOIP_SANDBOX"),
            token(withData: Data([0x05, 0x05, 0x05]), type: "GCM")
        ])

        sut.handleResponse(response(payload: payload, status: 200), action: action)
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))

        // Then
        XCTAssertEqual(receivedTokens.count, 4)

        let apns = PushToken(deviceToken: Data([0x01, 0x01, 0x01]), appIdentifier: "app", transportType: "APNS", tokenType: .standard, isRegistered: true)
        XCTAssertEqual(receivedTokens.element(atIndex: 0), apns)

        let apnsSandbox = PushToken(deviceToken: Data([0x02, 0x02, 0x02]), appIdentifier: "app", transportType: "APNS_SANDBOX", tokenType: .standard, isRegistered: true)
        XCTAssertEqual(receivedTokens.element(atIndex: 1), apnsSandbox)

        let voIP = PushToken(deviceToken: Data([0x03, 0x3, 0x03]), appIdentifier: "app", transportType: "APNS_VOIP", tokenType: .voip, isRegistered: true)
        XCTAssertEqual(receivedTokens.element(atIndex: 2), voIP)

        let voIPSandbox = PushToken(deviceToken: Data([0x04, 0x04, 0x04]), appIdentifier: "app", transportType: "APNS_VOIP_SANDBOX", tokenType: .voip, isRegistered: true)
        XCTAssertEqual(receivedTokens.element(atIndex: 3), voIPSandbox)
    }

    func test_itHandlesResponse_200_MalformedResponse() throws {
        // Given
        let sut = GetPushTokensActionHandler(context: syncMOC)
        var action = GetPushTokensAction()

        // Expectation
        let didFail = expectation(description: "didFail")

        action.onResult { result in
            guard case .failure(.malformedResponse) = result else { return }
            didFail.fulfill()
        }

        // When
        sut.handleResponse(response(payload: nil, status: 200), action: action)

        // Then
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
    }

    func test_itHandlesResponse_UnknownError() throws {
        // Given
        let sut = GetPushTokensActionHandler(context: syncMOC)
        var action = GetPushTokensAction()

        // Expectation
        let didFail = expectation(description: "didFail")

        action.onResult { result in
            guard case .failure(.unknown(status: 999)) = result else { return }
            didFail.fulfill()
        }

        // When
        sut.handleResponse(response(payload: nil, status: 999), action: action)

        // Then
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
    }

}
