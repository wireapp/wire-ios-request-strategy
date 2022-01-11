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

final class JoinConversationActionHandlerTests: MessagingTestBase {

    private var conversation: ZMConversation!

    private var key: String!
    private var code: String!

    private var sut: JoinConversationActionHandler!

    override func setUp() {
        super.setUp()

        syncMOC.performGroupedBlockAndWait {
            let conversation = ZMConversation.insertGroupConversation(moc: self.syncMOC, participants: [])!
            let conversationID = UUID()
            conversation.remoteIdentifier = conversationID
            conversation.conversationType = .group
            conversation.domain = self.owningDomain
            conversation.addParticipantAndUpdateConversationState(user: self.otherUser, role: nil)
            self.conversation = conversation
        }

        key = UUID().uuidString
        code = UUID().uuidString

        sut = JoinConversationActionHandler(context: syncMOC)
    }

    override func tearDown() {
        sut = nil

        super.tearDown()
    }

    func testThatItCreatesAnExpectedRequestForJoiningConversation() throws {
        try syncMOC.performGroupedAndWait { [self] _ in
            // given
            let action = JoinConversationAction(key: key, code: code, viewContext: uiMOC)

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

            let selfUser = ZMUser.selfUser(in: syncMOC)

            var resultConversation: ZMConversation?
            var action = JoinConversationAction(key: key, code: code, viewContext: uiMOC)
            action.onResult { result in
                if case .success(let conversation) = result {
                    resultConversation = conversation
                    expectation.fulfill()
                }
            }

            let member = Payload.ConversationMember(id: otherUser.remoteIdentifier,
                                                    qualifiedID: otherUser.qualifiedID,
                                                    conversationRole: ZMConversation.defaultMemberRoleName)
            let eventData = Payload.UpdateConverationMemberJoin(userIDs: [otherUser.remoteIdentifier], users: [member])
            let conversationEvent = conversationEventPayload(from: eventData, conversationID: conversation.qualifiedID, senderID: otherUser.qualifiedID)
            let payloadAsString = String(bytes: conversationEvent.payloadData()!, encoding: .utf8)!
            let response = ZMTransportResponse(payload: payloadAsString as ZMTransportData, httpStatus: 200, transportSessionError: nil)

            // when
            self.sut.handleResponse(response, action: action)

            // then
            XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
            XCTAssertEqual(resultConversation!, conversation)
            XCTAssertTrue(self.conversation.localParticipantsContain(user: selfUser))
        }
    }

    func testThatItFailsWhenTheResponseIs204() {
        syncMOC.performGroupedAndWait { [self] _ in
            // given
            let expectation = self.expectation(description: "Result Handler was called")

            var action = JoinConversationAction(key: key, code: code, viewContext: uiMOC)
            action.onResult { result in
                if case .failure = result {
                    expectation.fulfill()
                }
            }

            let response = ZMTransportResponse(payload: nil, httpStatus: 204, transportSessionError: nil)

            // when
            self.sut.handleResponse(response, action: action)

            // then
            XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
        }
    }

    func testThatItFailsWhenTheRequestIsFailed() {
        syncMOC.performGroupedAndWait { [self] _ in
            // given
            let expectation = self.expectation(description: "Result Handler was called")

            var action = JoinConversationAction(key: key, code: code, viewContext: uiMOC)
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

    func testThatItParsesAllKnownConnectionToUserErrorResponses() {

        let errorResponses: [(ConversationJoinError, ZMTransportResponse)] = [
            (ConversationJoinError.tooManyMembers, ZMTransportResponse(payload: ["label": "too-many-members"] as ZMTransportData, httpStatus: 403, transportSessionError: nil)),
            (ConversationJoinError.invalidCode, ZMTransportResponse(payload: ["label": "no-conversation-code"] as ZMTransportData, httpStatus: 404, transportSessionError: nil)),
            (ConversationJoinError.noConversation, ZMTransportResponse(payload: ["label": "no-conversation"] as ZMTransportData, httpStatus: 404, transportSessionError: nil))
        ]

        for (expectedError, response) in errorResponses {
            if case ConversationJoinError(response: response) = expectedError {
                // success
            } else {
                XCTFail("Unexpected error found")
            }
        }
    }
}
