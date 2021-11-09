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

final class JoinActionHandlerTests: MessagingTestBase {
    
    private var conversation: ZMConversation!
    
    private var key: String!
    private var code: String!
    
    private var sut: JoinActionHandler!
    
    override func setUp() {
        super.setUp()
        
        syncMOC.performGroupedBlockAndWait {
            let conversation = ZMConversation.insertGroupConversation(moc: self.syncMOC, participants: [])!
            let conversationID = UUID()
            conversation.remoteIdentifier = conversationID
            conversation.conversationType = .group
            conversation.domain = self.owningDomain
            self.conversation = conversation
        }
        
        key = UUID().uuidString
        code = UUID().uuidString
        
        sut = JoinActionHandler(context: syncMOC)
    }
    
    override func tearDown() {
        sut = nil
        
        super.tearDown()
    }
    
    func testThatItCreatesAnExpectedRequestForJoiningConversation() throws {
        try syncMOC.performGroupedAndWait { [self] syncMOC in
            // given
            let action = JoinAction(key: key, code: code)
            
            // when
            let request = try XCTUnwrap(sut.request(for: action))
            
            // then
            XCTAssertEqual(request.path, "/conversations/join")
            let expectedPayload: [String: String] = ["key": key, "code": code]
            XCTAssertEqual(request.payload!.asDictionary()! as! [String: String], expectedPayload)
        }
    }
    
    func testThatItShouldJoinConversationAndReturnsConversationIDWhenTheRequestSucceeded() {
        syncMOC.performGroupedAndWait { [self] syncMOC in
            // given
            let expectation = self.expectation(description: "Result Handler was called")
            
            let expectedConversationID = self.conversation.remoteIdentifier
            
            let selfUser = ZMUser.selfUser(in: syncMOC)
            
            var resultConversationID: String?
            var action = JoinAction(key: key, code: code)
            action.onResult { result in
                if case .success(let id) = result {
                    resultConversationID = id
                    expectation.fulfill()
                }
            }
            
            let eventData = Payload.UpdateConverationMemberJoin(userIDs: nil, users: nil)
            let conversationID = QualifiedID(uuid: expectedConversationID!, domain: "bcd")
            let conversationEvent = conversationEventPayload(from: eventData, conversationID: conversationID, senderID: nil, timestamp: nil)
            let payloadAsString = String(bytes: conversationEvent.payloadData()!, encoding: .utf8)!
            let response = ZMTransportResponse(payload: payloadAsString as ZMTransportData, httpStatus: 200, transportSessionError: nil)
            
            // when
            self.sut.handleResponse(response, action: action)
            
            // then
            XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
            XCTAssertEqual(resultConversationID!, expectedConversationID!.uuidString)
            XCTAssertTrue(self.conversation.localParticipantsContain(user: selfUser))
        }
    }
    
    func testThatItFailsWhenTheResponseIs204() {
        syncMOC.performGroupedAndWait { [self] syncMOC in
            // given
            let expectation = self.expectation(description: "Result Handler was called")
            
            var action = JoinAction(key: key, code: code)
            action.onResult { result in
                if case .failure = result {
                    expectation.fulfill()
                }
            }
            
            let response = ZMTransportResponse(payload: nil, httpStatus: 200, transportSessionError: nil)
            
            // when
            self.sut.handleResponse(response, action: action)
            
            // then
            XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
        }
    }
    
    func testThatItFailsWhenTheRequestIsFailed() {
        syncMOC.performGroupedAndWait { [self] syncMOC in
            // given
            let expectation = self.expectation(description: "Result Handler was called")
            
            var action = JoinAction(key: key, code: code)
            action.onResult { result in
                if case .failure = result {
                    expectation.fulfill()
                }
            }
            
            let response = ZMTransportResponse(payload: nil, httpStatus: 400, transportSessionError: nil)
            
            // when
            self.sut.handleResponse(response, action: action)
            
            // then
            XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
        }
    }
}
