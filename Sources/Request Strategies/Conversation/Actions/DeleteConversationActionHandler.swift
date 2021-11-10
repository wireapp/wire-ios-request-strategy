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

extension ConversationDeleteError {
    
    init?(response: ZMTransportResponse) {
        switch (response.httpStatus, response.payloadLabel()) {
        case (403, "invalid-op"?): self = .invalidOperation
        case (404, "no-conversation"?): self = .conversationNotFound
        case (400..<499, _): self = .unknown
        default: return nil
        }
    }
    
}

class DeleteConversationActionHandler: ActionHandler<DeleteConversationAction> {
    
    override func request(for action: DeleteConversationAction) -> ZMTransportRequest? {
        let path = "/teams/\(action.teamID.transportString())/conversations/\(action.conversationID.transportString())"
        
        return ZMTransportRequest(path: path, method: .methodDELETE, payload: nil)
    }
    
    override func handleResponse(_ response: ZMTransportResponse, action: DeleteConversationAction) {
        var action = action
        
        if response.httpStatus == 200 {
            context.performGroupedBlock { [weak self] in
                guard
                    let self = self,
                    let conversation = ZMConversation.fetch(with: action.conversationID, domain: nil, in: self.context)
                else {
                    return
                }
                
                self.context.delete(conversation)
                self.context.saveOrRollback()
            }
            
            action.notifyResult(.success(()))
            
        } else {
            let error = ConversationDeleteError(response: response) ?? .unknown
            Logging.network.debug("Error deleting converation: \(error)")
            action.notifyResult(.failure(error))
        }
    }
    
}
