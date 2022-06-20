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

import XCTest
@testable import WireRequestStrategy

class SendMLSMessageActionHandlerTests: ActionHandlerTestBase<SendMLSMessageAction, SendMLSMessageActionHandler> {

    let mlsMessage = "mlsMessage"

    override func setUp() {
        super.setUp()
        action = SendMLSMessageAction(mlsMessage: mlsMessage)
    }

    // MARK: - Request generation
    func test_itGenerateARequest() throws {
        try test_itGeneratesARequest(
            for: action,
            expectedPath: "/v1/mls/messages",
            expectedPayload: mlsMessage,
            expectedMethod: .methodPOST,
            apiVersion: .v1
        )
    }

    func test_itFailsToGenerateRequests() {
        test_itDoesntGenerateARequest(
            action: action,
            apiVersion: .v0,
            expectedError: .endpointUnavailable
        )

        test_itDoesntGenerateARequest(
            action: SendMLSMessageAction(mlsMessage: ""),
            apiVersion: .v1,
            expectedError: .invalidBody
        )
    }

    // MARK: - Response handling
    func test_itHandlesSuccess() {
        test_itHandlesSuccess(status: 201)
    }

    func test_itHandlesFailures() {

        test_itHandlesFailure(
            status: 400,
            expectedError: .invalidBody
        )

        test_itHandlesFailure(
            status: 400,
            label: "mls-protocol-error",
            expectedError: .mlsProtocolError
        )

        test_itHandlesFailure(
            status: 403,
            label: "missing-legalhold-consent",
            expectedError: .missingLegalHoldConsent
        )

        test_itHandlesFailure(
            status: 403,
            label: "legalhold-not-enabled",
            expectedError: .legalHoldNotEnabled
        )

        test_itHandlesFailure(
            status: 404,
            label: "mls-proposal-not-found",
            expectedError: .mlsProposalNotFound
        )

        test_itHandlesFailure(
            status: 404,
            label: "mls-key-package-ref-not-found",
            expectedError: .mlsKeyPackageRefNotFound
        )

        test_itHandlesFailure(
            status: 404,
            label: "no-conversation",
            expectedError: .noConversation
        )

        test_itHandlesFailure(
            status: 409,
            label: "mls-stale-message",
            expectedError: .mlsStaleMessage
        )

        test_itHandlesFailure(
            status: 409,
            label: "mls-client-mismatch",
            expectedError: .mlsClientMismatch
        )

        test_itHandlesFailure(
            status: 422,
            label: "mls-unsupported-proposal",
            expectedError: .mlsUnsupportedProposal
        )

        test_itHandlesFailure(
            status: 422,
            label: "mls-unsupported-message",
            expectedError: .mlsUnsupportedMessage
        )

        test_itHandlesFailure(
            status: 999,
            expectedError: .unknown(status: 999)
        )
    }
}
