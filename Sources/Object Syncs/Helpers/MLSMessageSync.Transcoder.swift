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

extension MLSMessageSync {

    class Transcoder<Message: MLSMessage>: EntityTranscoder {

        // MARK: - Types

        typealias OnRequestScheduledHandler = (_ message: Message, _ request: ZMTransportRequest) -> Void

        // MARK: - Properties

        let context: NSManagedObjectContext
        var onRequestScheduledHandler: OnRequestScheduledHandler?

        // MARK: - Life cycle {

        init(context: NSManagedObjectContext) {
            self.context = context
        }

        // MARK: - Request generation

        func request(forEntity entity: Message, apiVersion: APIVersion) -> ZMTransportRequest? {
            switch apiVersion {
            case .v0, .v1:
                return nil

            case .v2:
                return v2Request(for: entity)
            }
        }

        private func v2Request(for entity: Message) -> ZMTransportRequest? {
            guard
                let conversation = entity.conversation,
                conversation.messageProtocol == .mls,
                let mlsController = context.mlsController
            else {
                return nil
            }

            // mlsController.encryptMessage(...)

            let request = ZMTransportRequest(
                path: "/mls/messages",
                method: .methodPOST,
                binaryData: Data(),
                type: "message/mls",
                contentDisposition: nil,
                apiVersion: 2
            )

            if let expirationDate = entity.expirationDate {
                request.expire(at: expirationDate)
            }

            onRequestScheduledHandler?(entity, request)

            return request
        }

        // MARK: - Response handling

        func request(forEntity entity: Message, didCompleteWithResponse response: ZMTransportResponse) {
            guard let apiVersion = APIVersion(rawValue: response.apiVersion) else { return }

            switch apiVersion {
            case .v0, .v1:
                return

            case .v2:
                v2processResponse(response, for: entity)
            }
        }

        private func v2processResponse(_ response: ZMTransportResponse, for entity: Message) {
            entity.delivered(with: response)

            // TODO: anything else to do here?
        }

        func shouldTryToResend(entity: Entity, afterFailureWithResponse response: ZMTransportResponse) -> Bool {
            fatalError("not implmented")
        }

    }

}
