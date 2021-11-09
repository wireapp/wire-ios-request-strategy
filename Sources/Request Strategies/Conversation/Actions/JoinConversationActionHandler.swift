// Wire
// Copyright (C) 2021 Wire Swiss GmbH
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

extension ConversationJoinError {
    
    public init(response: ZMTransportResponse) {
        switch (response.httpStatus, response.payloadLabel()) {
        case (403, "too-many-members"?): self = .tooManyMembers
        case (404, "no-conversation-code"?): self = .invalidCode
        case (404, "no-conversation"?): self = .noConversation
        default: self = .unknown
        }
    }
    
}

class JoinConversationActionHandler: ActionHandler<JoinConversationAction> {
    
    override func request(for action: JoinConversationAction) -> ZMTransportRequest? {
        let path = "/conversations/join"
        let payload = Payload.ConversationJoin(key: action.key, code: action.code)
        
        guard
            let payloadData = payload.payloadData(encoder: .defaultEncoder),
            let payloadAsString = String(bytes: payloadData, encoding: .utf8)
        else {
            var action = action
            action.notifyResult(.failure(.unknown))
            return nil
        }
        
        
        return ZMTransportRequest(path: path, method: .methodPOST, payload: payloadAsString as ZMTransportData)
    }
    
    override func handleResponse(_ response: ZMTransportResponse, action: JoinConversationAction) {
        var action = action
        
        switch response.httpStatus {
        case 200:
            guard
                let payload = response.payload,
                let event = ZMUpdateEvent(fromEventStreamPayload: payload, uuid: nil),
                let rawData = response.rawData,
                let conversationEvent = Payload.ConversationEvent<Payload.UpdateConverationMemberJoin>(rawData, decoder: .defaultDecoder),
                let conversationID = conversationEvent.id?.uuidString
            else {
                action.notifyResult(.failure(.unknown))
                return
            }

            conversationEvent.process(in: context, originalEvent: event)
          
            action.notifyResult(.success(conversationID))

        /// The user is already a participant in the conversation
        case 204:
            /// If we get to this case, then we need to re-sync local conversations
            /// TODO: implement re-syncing conversations
            Logging.network.debug("Local conversations should be re-synced with remote ones")
            action.notifyResult(.failure(.unknown))

        default:
            let error = ConversationJoinError(response: response)
            Logging.network.debug("Error joining conversation using a reusable code: \(error)")
            action.notifyResult(.failure(error))
        }
    }
    
}
