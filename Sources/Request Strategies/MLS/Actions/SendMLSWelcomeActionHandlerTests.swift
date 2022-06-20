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

class SendMLSWelcomeActionHandlerTests: ActionHandlerTestBase<SendMLSWelcomeAction, SendMLSWelcomeActionHandler> {

    let body = "abc123"

    override func setUp() {
        super.setUp()
        action = SendMLSWelcomeAction(body: body)
    }

    // MARK: - Request generation

    func test_itGenerateARequest() throws {
        try test_itGeneratesARequest(
            for: SendMLSWelcomeAction(body: body),
            expectedPath: "/v1/mls/welcome",
            expectedPayload: body,
            expectedMethod: .methodPOST,
            apiVersion: .v1
        )
    }

    func test_itDoesntGenerateARequest_WhenAPIVersionIsNotSupported() {
        test_itDoesntGenerateARequest(
            action: SendMLSWelcomeAction(body: body),
            apiVersion: .v0,
            expectedError: .endpointUnavailable
        )
    }

    func test_itDoesntGenerateARequest_WhenParametersAreEmpty() {
        test_itDoesntGenerateARequest(
            action: SendMLSWelcomeAction(body: ""),
            apiVersion: .v1,
            expectedError: .emptyParameters
        )
    }

    // MARK: - Response handling

    func test_itHandlesResponse_201() {
        test_itHandlesSuccess(status: 201)
    }

    func test_itHandlesResponse_400() {
        test_itHandlesFailure(
            status: 400,
            expectedError: .invalidBody
        )
    }

    func test_itHandlesResponse_404() {
        test_itHandlesFailure(
            status: 404,
            label: "mls-key-package-ref-not-found",
            expectedError: .keyPackageRefNotFound
        )
    }

    func test_itHandlesResponse_UnkownError() {
        test_itHandlesFailure(
            status: 999,
            expectedError: .unknown(status: 999)
        )
    }
}
