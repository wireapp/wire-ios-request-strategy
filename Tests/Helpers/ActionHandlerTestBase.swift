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
import UIKit
@testable import WireRequestStrategy

class ActionHandlerTestBase<Action: EntityAction, Handler: ActionHandler<Action>>: MessagingTestBase {

    typealias ValidationBlock = (Swift.Result<Action.Result, Action.Failure>) -> Bool

    var action: Action!

    override func tearDown() {
        action = nil
        super.tearDown()
    }

    func test_itGeneratesARequest<Payload: Equatable>(
        for action: Action,
        expectedPath: String,
        expectedPayload: Payload,
        expectedMethod: ZMTransportRequestMethod,
        apiVersion: APIVersion = .v1) throws
    {
        // Given
        let sut = Handler(context: syncMOC)

        // When
        let request = try XCTUnwrap(sut.request(for: action, apiVersion: apiVersion))

        // Then
        XCTAssertEqual(request.path, expectedPath)
        XCTAssertEqual(request.method, expectedMethod)
        XCTAssertEqual(request.payload as? Payload, expectedPayload)
    }

    func test_itDoesntGenerateARequest(
        action: Action,
        apiVersion: APIVersion,
        validation: @escaping ValidationBlock
    ) {
        // Given
        var action = action
        let sut = Handler(context: syncMOC)

        // Expectation
        expect(action: &action, toPassValidation: validation)

        // When
        let request = sut.request(for: action, apiVersion: apiVersion)

        // Then
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
        XCTAssertNil(request)
    }

    func test_itHandlesResponse(
        status: Int,
        payload: ZMTransportData? = nil,
        label: String? = nil,
        validation: @escaping ValidationBlock
    ) {
        guard let action = self.action else {
            return XCTFail("action must be set in child class' setup")
        }

        test_itHandlesResponse(
            action: action,
            status: status,
            payload: payload,
            label: label,
            validation: validation
        )
    }

    func test_itHandlesResponse(
        action: Action,
        status: Int,
        payload: ZMTransportData? = nil,
        label: String? = nil,
        apiVersion: APIVersion = .v1,
        validation: @escaping ValidationBlock
    ) {
        // Given
        let sut = Handler(context: syncMOC)
        var action = action

        // Expectation
        expect(action: &action, toPassValidation: validation)

        // When
        let response = response(
            status: status,
            payload: payload,
            label: label,
            apiVersion: apiVersion
        )
        sut.handleResponse(response, action: action)

        // Then
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
    }

    private func expect(
        action: inout Action,
        toPassValidation validateResult: @escaping ValidationBlock
    ) {
        let expectation = self.expectation(description: "didPassValidation")

        action.onResult { result in
            guard validateResult(result) else { return }
            expectation.fulfill()
        }
    }

    private func response(
        status: Int,
        payload: ZMTransportData?,
        label: String?,
        apiVersion: APIVersion) -> ZMTransportResponse
    {
        var payload = payload

        if payload == nil, let label = label {
            payload = ["label": label] as ZMTransportData
        }

        return ZMTransportResponse(
            payload: payload,
            httpStatus: status,
            transportSessionError: nil,
            apiVersion: apiVersion.rawValue
        )
    }
}
