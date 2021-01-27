//
// Wire
// Copyright (C) 2020 Wire Swiss GmbH
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

class ResetSessionRequestStrategyTests: MessagingTestBase {

    var sut: ResetSessionRequestStrategy!
    var mockApplicationStatus : MockApplicationStatus!
    
    override func setUp() {
        super.setUp()
        mockApplicationStatus = MockApplicationStatus()
        mockApplicationStatus.mockSynchronizationState = .online
        sut = ResetSessionRequestStrategy(managedObjectContext: self.syncMOC,
                                    applicationStatus: mockApplicationStatus,
                                    clientRegistrationDelegate: mockApplicationStatus.clientRegistrationDelegate)
    }
    
    override func tearDown() {
        mockApplicationStatus = nil
        sut = nil
        super.tearDown()
    }
    
    // MARK: Request generation
    
    func testThatItCreatesARequest_WhenUserClientNeedsToNotifyOtherUserAboutSessionReset() {
        syncMOC.performGroupedBlockAndWait {
            // GIVEN
            let otherUser = self.createUser()
            let conversation = self.setupOneToOneConversation(with: otherUser)
            let otherClient = self.createClient(user: otherUser)
            otherClient.needsToNotifyOtherUserAboutSessionReset = true
            
            
            // WHEN
            self.sut.contextChangeTrackers.forEach {
                $0.objectsDidChange(Set(arrayLiteral: otherClient))
            }
            
            // THEN
            XCTAssertEqual(self.sut.nextRequest()?.path, "/conversations/\(conversation.remoteIdentifier!.transportString())/otr/messages")
        }
    }

    // MARK: Response handling

    func testThatItResetsNeedsToNotifyOtherUserAboutSessionReset_WhenReceivingTheResponse() {
        var otherClient: UserClient!
        syncMOC.performGroupedBlockAndWait {
            // GIVEN
            let otherUser = self.createUser()
            _ = self.setupOneToOneConversation(with: otherUser)
            otherClient = self.createClient(user: otherUser)
            otherClient.needsToNotifyOtherUserAboutSessionReset = true
            
            self.sut.contextChangeTrackers.forEach {
                $0.objectsDidChange(Set(arrayLiteral: otherClient))
            }
            let request = self.sut.nextRequest()
            
            // WHEN
            request?.complete(with: ZMTransportResponse(payload: [:] as ZMTransportData, httpStatus: 200, transportSessionError: nil))
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))

        // THEN
        syncMOC.performGroupedBlockAndWait {
            XCTAssertFalse(otherClient.needsToNotifyOtherUserAboutSessionReset)
        }
    }
    
}
