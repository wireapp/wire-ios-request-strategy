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

extension ConversationFetchIDAndNameError {
    
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

class FetchIDAndNameActionHandler: ActionHandler<FetchIDAndNameAction> {
    
    override func request(for action: FetchIDAndNameAction) -> ZMTransportRequest? {
        var url = URLComponents()
        url.path = "/conversations/join"
        url.queryItems = [URLQueryItem(name: "key", value: action.key),
                          URLQueryItem(name: "code", value: action.code)]
        guard let urlString = url.string else {
            return nil
        }
        
        return ZMTransportRequest(path: urlString, method: .methodGET, payload: nil)
    }
    
    override func handleResponse(_ response: ZMTransportResponse, action: FetchIDAndNameAction) {
        var action = action
        
        switch response.httpStatus {
        case 200:
            guard
                let payload = response.payload as? [AnyHashable : Any],
                let id = payload["id"] as? String,
                let conversationID = UUID(uuidString: id),
                let conversationName = payload["name"] as? String
            else {
                action.notifyResult(.failure(.unknown))
                return
            }
            
            let fetchResult = (conversationID, conversationName)
            action.notifyResult(.success(fetchResult))
        default:
            let error = ConversationFetchIDAndNameError(response: response)
            Logging.network.debug("Error fetching conversation ID and name using a reusable code: \(error)")
            action.notifyResult(.failure(error))
        }
    }
    
}
