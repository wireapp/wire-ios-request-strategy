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

class SendMLSMessagesActionHandler: ActionHandler<SendMLSMessagesAction> {

    // MARK: - Methods

    override func request(
        for action: ActionHandler<SendMLSMessagesAction>.Action,
        apiVersion: APIVersion
    ) -> ZMTransportRequest? {

        var action = action

        guard apiVersion > .v0 else {
            action.notifyResult(.failure(.endpointNotAvailable))
            return nil
        }

        guard !action.body.isEmpty else {
            action.notifyResult(.failure(.invalidBody))
            return nil
        }

        return ZMTransportRequest(
            path: "/mls/messages",
            method: .methodPOST,
            payload: action.body as ZMTransportData,
            apiVersion: apiVersion.rawValue
        )
    }

    override func handleResponse(
        _ response: ZMTransportResponse,
        action: ActionHandler<SendMLSMessagesAction>.Action
    ) {
        var action = action

        switch (response.httpStatus, response.payloadLabel()) {
        case (201, _):
            action.notifyResult(.success(()))

        case (400, "mls-protocol-error"):
            action.notifyResult(.failure(.mlsProtocolError))

        case (400, _):
            action.notifyResult(.failure(.invalidBody))

        case (403, "missing-legalhold-consent"):
            action.notifyResult(.failure(.missingLegalHoldConsent))

        case (403, "legalhold-not-enabled"):
            action.notifyResult(.failure(.legalHoldNotEnabled))

        case (404, "mls-proposal-not-found"):
            action.notifyResult(.failure(.mlsProposalNotFound))

        case (404, "mls-key-package-ref-not-found"):
            action.notifyResult(.failure(.mlsKeyPackageRefNotFound))

        case (404, "no-conversation"):
            action.notifyResult(.failure(.noConversation))

        case (409, "mls-stale-message"):
            action.notifyResult(.failure(.mlsStaleMessage))

        case (409, "mls-client-mismatch"):
            action.notifyResult(.failure(.mlsClientMismatch))

        case (422, "mls-unsupported-proposal"):
            action.notifyResult(.failure(.mlsUnsupportedProposal))

        case (422, "mls-unsupported-message"):
            action.notifyResult(.failure(.mlsUnsupportedMessage))

        default:
            action.notifyResult(.failure(.unknown(status: response.httpStatus)))
        }
    }
}

extension SendMLSMessagesActionHandler {

}
