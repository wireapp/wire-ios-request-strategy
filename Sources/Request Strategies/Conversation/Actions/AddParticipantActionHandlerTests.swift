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

class AddParticipantActionHandlerTests: MessagingTestBase {

    var sut: AddParticipantActionHandler!
    var user: ZMUser!
    var conversation: ZMConversation!

    override func setUp() {
        super.setUp()

        syncMOC.performGroupedBlockAndWait {
            let user = ZMUser.insertNewObject(in: self.syncMOC)
            let userID = UUID()
            user.remoteIdentifier = userID
            user.domain = self.owningDomain
            self.user = user

            let conversation = ZMConversation.insertGroupConversation(moc: self.syncMOC, participants: [])!
            let conversationID = UUID()
            conversation.remoteIdentifier = conversationID
            conversation.conversationType = .group
            conversation.domain = self.owningDomain
            self.conversation = conversation
        }

        sut = AddParticipantActionHandler(context: syncMOC)
    }

    override func tearDown() {
        sut = nil

        super.tearDown()
    }

    // MARK: - Request Generation

    func testThatItCreatesARequestForAddingAParticipant_NonFederated() throws {
        try syncMOC.performGroupedAndWait { syncMOC in
            // given
            let userID = self.user.remoteIdentifier!
            let conversationID = self.conversation.remoteIdentifier!
            let action = AddParticipantAction(users: [self.user], conversation: self.conversation)

            // when
            let request = try XCTUnwrap(self.sut.request(for: action))

            // then
            XCTAssertEqual(request.path, "/conversations/\(conversationID.transportString())/members")
            let payload = Payload.ConverationAddMember(request)
            XCTAssertEqual(payload?.userIDs, [userID])
        }
    }

    func testThatItCreatesARequestForAddingAParticipant_Federated() throws {
        try syncMOC.performGroupedAndWait { syncMOC in
            // given
            self.sut.useFederationEndpoint = true
            let conversationID = self.conversation.remoteIdentifier!
            let action = AddParticipantAction(users: [self.user], conversation: self.conversation)

            // when
            let request = try XCTUnwrap(self.sut.request(for: action))

            // then
            XCTAssertEqual(request.path, "/conversations/\(conversationID)/members/v2")
            let payload = Payload.ConverationAddMember(request)
            XCTAssertEqual(payload?.qualifiedUserIDs, [self.user.qualifiedID!])
        }
    }


    // MARK: - Request Processing

    func testThatItParsesAllKnownAddParticipantErrorResponses() {

        let errorResponses: [(ConversationAddParticipantsError, ZMTransportResponse)] = [
            (ConversationAddParticipantsError.invalidOperation, ZMTransportResponse(payload: ["label": "invalid-op"] as ZMTransportData, httpStatus: 403, transportSessionError: nil)),
            (ConversationAddParticipantsError.accessDenied, ZMTransportResponse(payload: ["label": "access-denied"] as ZMTransportData, httpStatus: 403, transportSessionError: nil)),
            (ConversationAddParticipantsError.notConnectedToUser, ZMTransportResponse(payload: ["label": "not-connected"] as ZMTransportData, httpStatus: 403, transportSessionError: nil)),
            (ConversationAddParticipantsError.conversationNotFound, ZMTransportResponse(payload: ["label": "no-conversation"] as ZMTransportData, httpStatus: 404, transportSessionError: nil)),
            (ConversationAddParticipantsError.missingLegalHoldConsent, ZMTransportResponse(payload: ["label": "missing-legalhold-consent"] as ZMTransportData, httpStatus: 412, transportSessionError: nil)),
        ]

        for (expectedError, response) in errorResponses {
            guard let error = ConversationAddParticipantsError(response: response) else { return XCTFail() }

            if case error = expectedError {
                // success
            } else {
                XCTFail()
            }
        }
    }

    func testThatItProcessMemberJoinEventInTheResponse() throws {
        syncMOC.performGroupedAndWait { [self] syncMOC in
            // given
            let selfUser = ZMUser.selfUser(in: self.syncMOC)
            let action = AddParticipantAction(users: [user], conversation: conversation)
            let member = Payload.ConversationMember(id: user.remoteIdentifier,
                                                    qualifiedID: user.qualifiedID,
                                                    conversationRole: ZMConversation.defaultMemberRoleName)
            let memberJoined = Payload.UpdateConverationMemberJoin(userIDs: [user.remoteIdentifier],
                                                                   users: [member])
            let conversationEvent = conversationEventPayload(from: memberJoined,
                                                             conversationID: conversation.qualifiedID,
                                                             senderID: selfUser.qualifiedID)
            let payloadAsString = String(bytes: conversationEvent, encoding: .utf8)!
            let response = ZMTransportResponse(payload: payloadAsString as ZMTransportData,
                                               httpStatus: 200,
                                               transportSessionError: nil)

            // when
            self.sut.handleResponse(response, action: action)

            // then
            XCTAssertTrue(conversation.localParticipants.contains(user))
        }
    }

    func testThatItRefetchTeamUsers_On403() {
        syncMOC.performGroupedAndWait { [self] syncMOC in
            // given
            let team = Team.insertNewObject(in: self.syncMOC)
            let selfUser = ZMUser.selfUser(in: self.syncMOC)

            let teamUser = ZMUser.insertNewObject(in: self.syncMOC)
            teamUser.remoteIdentifier = UUID()
            teamUser.needsToBeUpdatedFromBackend = false

            let nonTeamUser = ZMUser.insertNewObject(in: self.syncMOC)
            nonTeamUser.remoteIdentifier = UUID()
            nonTeamUser.needsToBeUpdatedFromBackend = false

            _ = Member.getOrCreateMember(for: selfUser, in: team, context: self.syncMOC)
            _ = Member.getOrCreateMember(for: teamUser, in: team, context: self.syncMOC)

            let action = AddParticipantAction(users: [teamUser, nonTeamUser], conversation: conversation)
            let response = ZMTransportResponse(payload: nil,
                                               httpStatus: 403,
                                               transportSessionError: nil)

            // when
            self.sut.handleResponse(response, action: action)

            // then
            XCTAssertTrue(teamUser.needsToBeUpdatedFromBackend)
            XCTAssertFalse(nonTeamUser.needsToBeUpdatedFromBackend)
        }
    }

    func testThatItCallsResultHandler_On200() {
        syncMOC.performGroupedAndWait { [self] syncMOC in
            // given
            let selfUser = ZMUser.selfUser(in: self.syncMOC)
            var action = AddParticipantAction(users: [user], conversation: conversation)
            let expectation = self.expectation(description: "Result Handler was called")
            action.onResult { (result) in
                if case .success = result {
                    expectation.fulfill()
                }
            }

            let member = Payload.ConversationMember(id: user.remoteIdentifier,
                                                    qualifiedID: user.qualifiedID,
                                                    conversationRole: ZMConversation.defaultMemberRoleName)
            let memberJoined = Payload.UpdateConverationMemberJoin(userIDs: [user.remoteIdentifier],
                                                                   users: [member])
            let conversationEvent = conversationEventPayload(from: memberJoined,
                                                             conversationID: conversation.qualifiedID,
                                                             senderID: selfUser.qualifiedID)
            let payloadAsString = String(bytes: conversationEvent, encoding: .utf8)!
            let response = ZMTransportResponse(payload: payloadAsString as ZMTransportData,
                                               httpStatus: 200,
                                               transportSessionError: nil)

            // when
            self.sut.handleResponse(response, action: action)

            // then
            XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
        }
    }

    func testThatItCallsResultHandler_On204() {
        syncMOC.performGroupedAndWait { [self] syncMOC in
            // given
            var action = AddParticipantAction(users: [user], conversation: conversation)

            let expectation = self.expectation(description: "Result Handler was called")
            action.onResult { (result) in
                if case .success = result {
                    expectation.fulfill()
                }
            }
            let response = ZMTransportResponse(payload: nil,
                                               httpStatus: 204,
                                               transportSessionError: nil)

            // when
            self.sut.handleResponse(response, action: action)

            // then
            XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
        }
    }

    func testThatItCallsResultHandler_OnError() {
        syncMOC.performGroupedAndWait { [self] syncMOC in
            // given
            var action = AddParticipantAction(users: [user], conversation: conversation)

            let expectation = self.expectation(description: "Result Handler was called")
            action.onResult { (result) in
                if case .failure = result {
                    expectation.fulfill()
                }
            }

            let response = ZMTransportResponse(payload: nil,
                                               httpStatus: 404,
                                               transportSessionError: nil)

            // when
            self.sut.handleResponse(response, action: action)

            // then
            XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
        }
    }

}