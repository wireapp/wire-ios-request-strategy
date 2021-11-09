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

extension ConversationFetchError {
    
    init(response: ZMTransportResponse) {
        switch (response.httpStatus, response.payloadLabel()) {
        case (403, "no-team-member"?): self = .noTeamMember
        case (403, "access-denied"?): self = .accessDenied
        case (404, "no-conversation-code"?): self = .invalidCode
        case (404, "no-conversation"?): self = .noConversation
        default: self = .unknown
        }
    }
    
}

class FetchConversationActionHandler: ActionHandler<FetchConversationAction> {
    
    override func request(for action: FetchConversationAction) -> ZMTransportRequest? {
        var url = URLComponents()
        url.path = "/conversations/join"
        url.queryItems = [URLQueryItem(name: "key", value: action.key),
                          URLQueryItem(name: "code", value: action.code)]
        guard let urlString = url.string else {
            return nil
        }
        
        return ZMTransportRequest(path: urlString, method: .methodGET, payload: nil)
    }
    
    override func handleResponse(_ response: ZMTransportResponse, action: FetchConversationAction) {
        var action = action
        
        switch response.httpStatus {
        case 200:
            guard
                let payload = Payload.ConversationFetch(response),
                let conversationID = UUID(uuidString: payload.id),
                let conversationName = payload.name
            else {
                action.notifyResult(.failure(.unknown))
                return
            }
            
            let fetchResult = (conversationID, conversationName)
            action.notifyResult(.success(fetchResult))
        default:
            let error = ConversationFetchError(response: response)
            Logging.network.debug("Error fetching conversation ID and name using a reusable code: \(error)")
            action.notifyResult(.failure(error))
        }
    }
    
}
