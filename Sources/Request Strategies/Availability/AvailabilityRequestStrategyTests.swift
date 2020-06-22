//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
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
import WireRequestStrategy

class AvailabilityRequestStrategyTests: MessagingTestBase {
    
    var applicationStatus: MockApplicationStatus!
    var sut : AvailabilityRequestStrategy!
    
    override func setUp() {
        super.setUp()

        self.syncMOC.performGroupedAndWait { moc in
            self.applicationStatus = MockApplicationStatus()
            self.applicationStatus.mockSynchronizationState = .eventProcessing
            self.sut = AvailabilityRequestStrategy(withManagedObjectContext: moc, applicationStatus: self.applicationStatus)
        }
    }
    
    override func tearDown() {
        sut = nil
        applicationStatus = nil
        
        super.tearDown()
    }
    
    func testThatItGeneratesARequestWhenAvailabilityIsModified() {
        self.syncMOC.performGroupedAndWait { moc in

            // given
            let selfUser = ZMUser.selfUser(in: moc)
            selfUser.needsToBeUpdatedFromBackend = false
            selfUser.setLocallyModifiedKeys(Set(arrayLiteral: AvailabilityKey))
            self.sut.contextChangeTrackers.forEach({ $0.addTrackedObjects(Set<NSManagedObject>(arrayLiteral: selfUser)) })

            // when
            let request = self.sut.nextRequest()


            // then
            XCTAssertNotNil(request)
        }
    }
    
    func testThatItGeneratesARequestWhenAvailabilityIsModifiedAndGuestShouldCommunicateStatus() {
        self.syncMOC.performGroupedAndWait { moc in
            
            // given
            let selfUser = ZMUser.selfUser(in: moc)
            selfUser.needsToBeUpdatedFromBackend = false
            selfUser.setLocallyModifiedKeys(Set(arrayLiteral: AvailabilityKey))
            
            let team = Team.insertNewObject(in: moc)
          
            let membership = Member.insertNewObject(in: moc)
            membership.user = selfUser
            membership.team = team
            
            self.sut.contextChangeTrackers.forEach({ $0.addTrackedObjects(Set<NSManagedObject>(arrayLiteral: selfUser)) })
            
            // when
            let request = self.sut.nextRequest()
            
            // then
            XCTAssertNotNil(request)
        }
    }
    
    func testThatItDoesntGenerateARequestWhenAvailabilityIsModifiedForOtherUsers() {
        self.syncMOC.performGroupedAndWait { moc in
            // given
            self.otherUser.needsToBeUpdatedFromBackend = false
            self.otherUser.modifiedKeys = Set(arrayLiteral: AvailabilityKey)
            self.sut.contextChangeTrackers.forEach({ $0.addTrackedObjects(Set<NSManagedObject>(arrayLiteral: self.otherUser)) })

            // when
            let request = self.sut.nextRequest()

            // then
            XCTAssertNil(request)
        }
    }
    
    func testThatItUpdatesAvailabilityFromUpdateEvent() {
        self.syncMOC.performGroupedAndWait { moc in

            // given
            let selfUser = ZMUser.selfUser(in: moc)
            _ = ZMConversation(remoteID: selfUser.remoteIdentifier!, createIfNeeded: true, in: moc) // create self conversation

            let message = GenericMessage(content: WireProtos.Availability(.away))
            let messageData = try? message.serializedData()
            let dict = ["recipient": self.selfClient.remoteIdentifier!,
                        "sender": self.selfClient.remoteIdentifier!,
                        "text": messageData?.base64String()] as NSDictionary

            let updateEvent = ZMUpdateEvent(fromEventStreamPayload: ([
                "type": "conversation.otr-message-add",
                "data":dict,
                "from" : selfUser.remoteIdentifier!,
                "conversation":ZMConversation.selfConversation(in: moc).remoteIdentifier!.transportString(),
                "time":Date(timeIntervalSince1970: 555555).transportString()] as NSDictionary), uuid: nil)!

            // when
            self.sut.processEvents([updateEvent], liveEvents: true, prefetchResult: nil)

            // then
            XCTAssertEqual(selfUser.availability, .away)
        }
    }
    
    func testThatItRequestSlowSyncIfWeAreSendingToRedudantClients() {
        self.syncMOC.performGroupedAndWait { moc in
            // given
            let redundantUser = ZMUser(remoteID: UUID(), createIfNeeded: true, in: moc)!
            
            // when
            self.sut.detectedRedundantUsers([redundantUser])

            // then
            XCTAssertTrue(self.applicationStatus.slowSyncWasRequested)
        }
    }
    
}
