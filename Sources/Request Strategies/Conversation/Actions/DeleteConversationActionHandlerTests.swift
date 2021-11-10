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

import XCTest
@testable import WireRequestStrategy

final class DeleteConversationActionHandlerTests: MessagingTestBase {
    
    private var sut: DeleteConversationActionHandler!
    
    override func setUp() {
        super.setUp()
        
        sut = DeleteConversationActionHandler(context: syncMOC)
    }
    
    override func tearDown() {
        sut = nil
        
        super.tearDown()
    }
    
    func testThatItCreatesARequestForDeletingConversation() throws {
        try syncMOC.performGroupedAndWait { syncMOC in
            // given
            let conversation = ZMConversation.insertGroupConversation(moc: self.syncMOC, participants: [])!
            let conversationID = UUID()
            let teamID = UUID()
            conversation.remoteIdentifier = conversationID
            conversation.teamRemoteIdentifier = teamID
            conversation.conversationType = .group
            conversation.domain = self.owningDomain
            
            let action = DeleteConversationAction(conversationID: conversationID, teamID: teamID)
            
            // when
            let request = try XCTUnwrap(self.sut.request(for: action))
            
            // then
            let expectedPath = "/teams/\(teamID.transportString())/conversations/\(conversationID.transportString())"
            XCTAssertEqual(request.path, expectedPath)
        }
    }
    
    func testThatItParsesAllKnownConnectionToUserErrorResponses() {
        let errorResponses: [(ConversationDeleteError, ZMTransportResponse)] = [
            (.invalidOperation, ZMTransportResponse(payload: ["label": "invalid-op"] as ZMTransportData, httpStatus: 403, transportSessionError: nil)),
            (.conversationNotFound, ZMTransportResponse(payload: ["label": "no-conversation"] as ZMTransportData, httpStatus: 404, transportSessionError: nil)),
            (.unknown, ZMTransportResponse(payload: nil, httpStatus: 400, transportSessionError: nil))
        ]
        
        for (expectedError, response) in errorResponses {
            if case ConversationDeleteError(response: response) = expectedError {
                // success
            } else {
                XCTFail()
            }
        }
    }
}
