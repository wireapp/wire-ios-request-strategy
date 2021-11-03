//
//  UpdateRoleActionHandlerTests.swift
//  WireRequestStrategyTests
//
//  Created by Sun Bin Kim on 03.11.21.
//  Copyright © 2021 Wire GmbH. All rights reserved.
//

import XCTest
@testable import WireRequestStrategy

final class UpdateRoleActionHandlerTests: MessagingTestBase {
    
    var sut: UpdateRoleActionHandler!
    var user: ZMUser!
    var conversation: ZMConversation!
    var role: Role!
    
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
            
            let role = Role.insertNewObject(in: self.syncMOC)
            role.name = UUID().uuidString
            role.conversation = self.conversation
            self.role = role
        }
        
        sut = UpdateRoleActionHandler(context: syncMOC)
    }
    
    override func tearDown() {
        sut = nil
        
        super.tearDown()
    }
    
    func testThatItCreatesAnExpectedRequestForUpdatingRole() throws {
        try syncMOC.performGroupedAndWait { syncMOC in
            // given
            let userID = self.user.remoteIdentifier!
            let conversationID = self.conversation.remoteIdentifier!
            let action = UpdateRoleAction(user: self.user, conversation: self.conversation, role: self.role)
            
            // when
            let request = try XCTUnwrap(self.sut.request(for: action))
            
            // then
            XCTAssertEqual(request.path, "/conversations/\(conversationID.transportString())/members/\(userID.transportString())")
            let payload = Payload.ConversationUpdateRole(request)
            XCTAssertEqual(payload?.role, self.role.name)
        }
    }
    
    func testThatItFailsCreatingRequestWhenUserIDIsMissing() {
        syncMOC.performGroupedAndWait { syncMOC in
            // given
            self.user.remoteIdentifier = nil
            let action = UpdateRoleAction(user: self.user, conversation: self.conversation, role: self.role)
            
            // when
            let request = self.sut.request(for: action)
            
            // then
            XCTAssertNil(request)
        }
    }
    
    func testThatItFailesCreatingRequestWhenConversationIDIsMissing() {
        syncMOC.performGroupedAndWait { syncMOC in
            // given
            self.conversation.remoteIdentifier = nil
            let action = UpdateRoleAction(user: self.user, conversation: self.conversation, role: self.role)
            
            // when
            let request = self.sut.request(for: action)
            
            // then
            XCTAssertNil(request)
        }
    }
    
    func testThatItFailesCreatingRequestWhenRoleNameIsMissing() {
        syncMOC.performGroupedAndWait { syncMOC in
            // given
            self.role.name = nil
            let action = UpdateRoleAction(user: self.user, conversation: self.conversation, role: self.role)
            
            // when
            let request = self.sut.request(for: action)
            
            // then
            XCTAssertNil(request)
        }
    }
    
    func testThatTheSucceededRequestUpdatesTheDatabase() {
        syncMOC.performGroupedAndWait { syncMOC in
            // given
            let action = UpdateRoleAction(user: self.user, conversation: self.conversation, role: self.role)
            let response = ZMTransportResponse(payload: nil, httpStatus: 200, transportSessionError: nil)
            
            // when
            self.sut.handleResponse(response, action: action)
            
            // then
            XCTAssertEqual(self.user.participantRoles.first { $0.conversation == self.conversation }?.role, self.role)
        }
    }
    
    func testThatTheFailedRequestDoesNotUpdateTheDatabase() {
        syncMOC.performGroupedAndWait { syncMOC in
            // given
            let action = UpdateRoleAction(user: self.user, conversation: self.conversation, role: self.role)
            let response = ZMTransportResponse(payload: nil, httpStatus: 400, transportSessionError: nil)
            
            // when
            self.sut.handleResponse(response, action: action)
            
            // then
            XCTAssertTrue(self.user.participantRoles.isEmpty)
        }
    }
}
