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

import Foundation
import XCTest
@testable import WireRequestStrategy

class ConversationRequestStrategyTests: MessagingTestBase {

    var sut: ConversationRequestStrategy!
    var mockApplicationStatus: MockApplicationStatus!
    var mockSyncProgress: MockSyncProgress!

    override func setUp() {
        super.setUp()

        mockApplicationStatus = MockApplicationStatus()
        mockApplicationStatus.mockSynchronizationState = .online
        mockSyncProgress = MockSyncProgress()

        sut = ConversationRequestStrategy(withManagedObjectContext: syncMOC,
                                          applicationStatus: mockApplicationStatus,
                                          syncProgress: mockSyncProgress)
    }

    override func tearDown() {
        sut = nil
        mockSyncProgress = nil
        mockApplicationStatus = nil

        super.tearDown()
    }

    // MARK: - Request generation

    func testThatRequestToFetchConversationIsGenerated_WhenNeedsToBeUpdatedFromBackendIsTrue() {
        syncMOC.performGroupedBlockAndWait {
            // given
            let domain = "example.com"
            let conversationID = self.groupConversation.remoteIdentifier!
            self.groupConversation.domain = domain
            self.groupConversation.needsToBeUpdatedFromBackend = true
            self.sut.objectsDidChange(Set([self.groupConversation]))

            // when
            let request = self.sut.nextRequest()!

            // then
            XCTAssertEqual(request.path, "/conversations/\(domain)/\(conversationID.transportString())")
            XCTAssertEqual(request.method, .methodGET)
        }
    }

    func testThatLegacyRequestToFetchConversationIsGenerated_WhenDomainIsNotSet() {
        syncMOC.performGroupedBlockAndWait {
            // given
            let conversationID = self.groupConversation.remoteIdentifier!
            self.groupConversation.domain = nil
            self.groupConversation.needsToBeUpdatedFromBackend = true
            self.sut.objectsDidChange(Set([self.groupConversation]))

            // when
            let request = self.sut.nextRequest()!

            // then
            XCTAssertEqual(request.path, "/conversations/\(conversationID.transportString())")
            XCTAssertEqual(request.method, .methodGET)
        }
    }

    func testThatRequestToCreateConversationIsGenerated_WhenRemoteIdentifierIsNotSet() {
        syncMOC.performGroupedBlockAndWait {
            // given
            let selfUser = ZMUser.selfUser(in: self.syncMOC)
            let conversation = ZMConversation.insertNewObject(in: self.syncMOC)
            conversation.conversationType = .group
            conversation.userDefinedName = "Hello World"
            conversation.addParticipantAndUpdateConversationState(user: self.otherUser, role: nil)
            conversation.addParticipantAndUpdateConversationState(user: selfUser, role: nil)
            self.sut.contextChangeTrackers.forEach({ $0.objectsDidChange(Set([conversation])) })

            // when
            let request = self.sut.nextRequest()!
            let payload = Payload.NewConversation(request)

            // then
            XCTAssertEqual(request.path, "/conversations")
            XCTAssertEqual(request.method, .methodPOST)
            XCTAssertEqual(payload?.name, conversation.userDefinedName)
            XCTAssertEqual(Set(payload!.qualifiedUsers!.qualifiedIDs), Set(conversation.localParticipantsExcludingSelf.qualifiedUserIDs!))
        }
    }

    func testThatRequestToUpdateConversationNameIsGenerated_WhenModifiedKeyIsSet() {
        syncMOC.performGroupedBlockAndWait {
            // given
            let domain = self.groupConversation.domain!
            let conversationID = self.groupConversation.remoteIdentifier!
            self.groupConversation.userDefinedName = "Hello World"
            self.groupConversation.setLocallyModifiedKeys(Set(arrayLiteral: ZMConversationUserDefinedNameKey))
            self.sut.contextChangeTrackers.forEach({ $0.objectsDidChange(Set([self.groupConversation])) })

            // when
            let request = self.sut.nextRequest()!
            let payload = Payload.UpdateConversationName(request)

            // then
            XCTAssertEqual(request.path, "/conversations/\(domain)/\(conversationID.transportString())/name")
            XCTAssertEqual(request.method, .methodPUT)
            XCTAssertEqual(payload?.name, self.groupConversation.userDefinedName)
        }
    }

    func testThatRequestToUpdateArchiveStatusIsGenerated_WhenModifiedKeyIsSet() {
        syncMOC.performGroupedBlockAndWait {
            // given
            let domain = self.groupConversation.domain!
            let conversationID = self.groupConversation.remoteIdentifier!
            self.groupConversation.isArchived = true
            self.groupConversation.setLocallyModifiedKeys(Set(arrayLiteral: ZMConversationArchivedChangedTimeStampKey))
            self.sut.contextChangeTrackers.forEach({ $0.objectsDidChange(Set([self.groupConversation])) })

            // when
            let request = self.sut.nextRequest()!
            let payload = Payload.UpdateConversationStatus(request)

            // then
            XCTAssertEqual(request.path, "/conversations/\(domain)/\(conversationID.transportString())/self")
            XCTAssertEqual(request.method, .methodPUT)
            XCTAssertEqual(payload?.archived, true)
        }
    }

    func testThatRequestToUpdateMutedStatusIsGenerated_WhenModifiedKeyIsSet() {
        syncMOC.performGroupedBlockAndWait {
            // given
            let domain = self.groupConversation.domain!
            let conversationID = self.groupConversation.remoteIdentifier!
            self.groupConversation.mutedMessageTypes = .all
            self.groupConversation.setLocallyModifiedKeys(Set(arrayLiteral: ZMConversationSilencedChangedTimeStampKey))
            self.sut.contextChangeTrackers.forEach({ $0.objectsDidChange(Set([self.groupConversation])) })

            // when
            let request = self.sut.nextRequest()!
            let payload = Payload.UpdateConversationStatus(request)

            // then
            XCTAssertEqual(request.path, "/conversations/\(domain)/\(conversationID.transportString())/self")
            XCTAssertEqual(request.method, .methodPUT)
            XCTAssertEqual(payload?.mutedStatus, Int(MutedMessageTypes.all.rawValue))
        }
    }

    // MARK: - Slow Sync

    func testThatRequestToListConversationsIsGenerated_DuringFetchingConversationsSyncPhase() {
        syncMOC.performGroupedBlockAndWait {
            // given
            self.mockSyncProgress.currentSyncPhase = .fetchingConversations

            // when
            let request = self.sut.nextRequest()!

            // then
            XCTAssertEqual(request.path, "/conversations/list-ids")
        }
    }

    func testThatRequestToListConversationsIsNotGenerated_WhenFetchIsAlreadyInProgress() {
        syncMOC.performGroupedBlockAndWait {
            // given
            self.mockSyncProgress.currentSyncPhase = .fetchingConversations
            _ = self.sut.nextRequest()!

            // when
            XCTAssertNil(self.sut.nextRequest())
        }
    }

    func testThatRequestToFetchConversationsIsGenerated_DuringFetchingConversationsSyncPhase() {
        // given
        startSlowSync()
        fetchConversationListDuringSlowSync()

        syncMOC.performGroupedBlockAndWait {
            // when
            let fetchRequest = self.sut.nextRequest()!

            // then
            guard let fetchPayload = Payload.QualifiedUserIDList(fetchRequest) else {
                return XCTFail()
            }

            let qualifiedConversationID = Payload.QualifiedUserID(uuid: self.groupConversation.remoteIdentifier!,
                                                                  domain: self.groupConversation.domain!)
            XCTAssertEqual(fetchPayload.qualifiedIDs.count, 1)
            XCTAssertEqual(fetchPayload.qualifiedIDs, [qualifiedConversationID])
        }
    }

    func testThatFetchingConversationsSyncPhaseIsFinished_WhenFetchIsCompleted() {
        // given
        startSlowSync()
        fetchConversationListDuringSlowSync()

        // when
        fetchConversationsDuringSlowSync()

        // then
        syncMOC.performGroupedBlockAndWait {
            XCTAssertEqual(self.mockSyncProgress.didFinishCurrentSyncPhase, .fetchingConversations)
        }
    }

    func testThatFetchingConversationsSyncPhaseIsFinished_WhenThereIsNoConversationsToFetch() {
        // given
        startSlowSync()

        // when
        fetchConversationListDuringSlowSyncWithEmptyResponse()

        // then
        syncMOC.performGroupedBlockAndWait {
            XCTAssertEqual(self.mockSyncProgress.didFinishCurrentSyncPhase, .fetchingConversations)
        }
    }

    func testThatFetchingConversationsSyncPhaseIsFailed_WhenReceivingAPermanentError() {
        // given
        startSlowSync()

        // when
        fetchConversationListDuringSlowSyncWithPermanentError()

        // then
        syncMOC.performGroupedBlockAndWait {
            XCTAssertEqual(self.mockSyncProgress.didFailCurrentSyncPhase, .fetchingConversations)
        }
    }

    func testThatConversationMembershipStatusIsQueried_WhenNotFoundDuringSlowSyncPhase() {
        // given
        startSlowSync()
        fetchConversationListDuringSlowSync()

        // when
        fetchConversationsDuringSlowSync(notFound: [qualifiedID(for: oneToOneConversation)])

        // then
        syncMOC.performGroupedBlockAndWait {
            XCTAssertTrue(self.oneToOneConversation.needsToBeUpdatedFromBackend)
        }
    }

    func testThatConversationIsCreatedAndMarkedToFetched_WhenFailingDuringSlowSyncPhase() throws {
        // given
        let conversationID = Payload.QualifiedUserID(uuid: UUID(), domain: owningDomain)
        startSlowSync()
        fetchConversationListDuringSlowSync()

        // when
        fetchConversationsDuringSlowSync(failed: [conversationID])

        // then
        try syncMOC.performGroupedAndWait { syncMOC in
            let conversation = try XCTUnwrap(ZMConversation.fetch(with: conversationID.uuid,
                                                              domain: conversationID.domain,
                                                              in: syncMOC))
            XCTAssertTrue(conversation.needsToBeUpdatedFromBackend)
        }
    }

    // MARK: - Response processing

    func testThatConversationResetsNeedsToBeUpdatedFromBackend_OnPermanentErrors() {
        // given
        let response = responseFailure(code: 403, label: .unknown)

        // when
        fetchConversation(with: response)

        // then
        self.syncMOC.performGroupedBlockAndWait {
            XCTAssertFalse(self.groupConversation.needsToBeUpdatedFromBackend)
        }
    }

    func testThatConversationIsDeleted_WhenResponseIs_404() {
        // given
        let response = responseFailure(code: 404, label: .notFound)

        // when
        fetchConversation(with: response)

        // then
        self.syncMOC.performGroupedBlockAndWait {
            XCTAssertTrue(self.groupConversation.isZombieObject)
        }
    }

    func testThatSelfUserIsRemovedFromParticipantsList_WhenResponseIs_403() {
        // given
        let response = responseFailure(code: 403, label: .unknown)

        // when
        fetchConversation(with: response)

        // then
        self.syncMOC.performGroupedBlockAndWait {
            XCTAssertFalse(self.groupConversation.isSelfAnActiveMember)
        }
    }

    // MARK: - Event processing

    // MARK: Conversation Creation

    func testThatItProcessesConversationCreateEvents() {
        syncMOC.performAndWait {
            // given
            let selfUserID = ZMUser.selfUser(in: self.syncMOC).remoteIdentifier!
            let qualifiedID = Payload.QualifiedUserID(uuid: UUID(), domain: self.owningDomain)
            let payload = Payload.Conversation(qualifiedID: qualifiedID,
                                               type: BackendConversationType.group.rawValue,
                                               name: "Hello World",
                                               members: .init(selfMember: Payload.ConversationMember(id: selfUserID),
                                                              others: []))
            let event = updateEvent(from: payload,
                                    conversationID: .init(uuid: UUID(), domain: owningDomain),
                                    senderID: otherUser.qualifiedID!,
                                    timestamp: Date())

            // when
            self.sut.processEvents([event], liveEvents: true, prefetchResult: nil)

            // then
            let conversation = ZMConversation.fetch(with: qualifiedID.uuid, domain: qualifiedID.domain, in: self.syncMOC)
            XCTAssertNotNil(conversation)
        }
    }

    // MARK: Conversation deletion

    func testThatItHandlesConversationDeletedUpdateEvent() {

        syncMOC.performAndWait {
            let selfUser = ZMUser.selfUser(in: self.syncMOC)
            selfUser.remoteIdentifier = UUID.create()

            // GIVEN
            let payload: [String: Any] = [
                "from": selfUser.remoteIdentifier!.transportString(),
                "conversation": self.groupConversation!.remoteIdentifier!.transportString(),
                "time": NSDate(timeIntervalSinceNow: 100).transportString(),
                "data": NSNull(),
                "type": "conversation.delete"
            ]

            // WHEN
            let event = ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!
            self.sut?.processEvents([event], liveEvents: true, prefetchResult: nil)

            // THEN
            XCTAssertTrue(self.groupConversation.isDeleted)
        }
    }

    // MARK: Conversation renaming

    func testThatItHandlesConverationNameUpdateEvent() {
        syncMOC.performAndWait {
            // given
            let newName = "Hello World"
            let payload = Payload.UpdateConversationName(name: newName)
            let event = updateEvent(from: payload,
                                    conversationID: self.groupConversation.qualifiedID,
                                    senderID: self.otherUser.qualifiedID!,
                                    timestamp: Date())

            // when
            self.sut.processEvents([event], liveEvents: true, prefetchResult: nil)

            // then
            XCTAssertEqual(self.groupConversation.userDefinedName, newName)
        }
    }

    // MARK: Receipt Mode

    func receiptModeUpdateEvent(enabled: Bool) -> ZMUpdateEvent {
        let payload = [
            "from": self.otherUser.remoteIdentifier!.transportString(),
            "conversation": self.groupConversation.remoteIdentifier!.transportString(),
            "time": NSDate().transportString(),
            "data": ["receipt_mode": enabled ? 1 : 0],
            "type": "conversation.receipt-mode-update"
            ] as [String: Any]
        return ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!
    }


    func testThatItUpdatesHasReadReceiptsEnabled_WhenReceivingReceiptModeUpdateEvent() {
        self.syncMOC.performAndWait {
            // GIVEN
            let event = receiptModeUpdateEvent(enabled: true)

            // WHEN
            self.sut.processEvents([event], liveEvents: true, prefetchResult: nil)

            // THEN
            XCTAssertEqual(self.groupConversation.hasReadReceiptsEnabled, true)
        }
    }

    func testThatItInsertsSystemMessageEnabled_WhenReceivingReceiptModeUpdateEvent() {
        self.syncMOC.performAndWait {
            // GIVEN
            let event = receiptModeUpdateEvent(enabled: true)

            // WHEN
            self.sut.processEvents([event], liveEvents: true, prefetchResult: nil)

            // THEN
            guard let message = self.groupConversation?.lastMessage as? ZMSystemMessage else { return XCTFail() }
            XCTAssertEqual(message.systemMessageType, .readReceiptsEnabled)
        }
    }

    func testThatItInsertsSystemMessageDisabled_WhenReceivingReceiptModeUpdateEvent() {
        self.syncMOC.performAndWait {
            // GIVEN
            let event = receiptModeUpdateEvent(enabled: false)

            // WHEN
            self.sut.processEvents([event], liveEvents: true, prefetchResult: nil)

            // THEN
            guard let message = self.groupConversation?.lastMessage as? ZMSystemMessage else { return XCTFail() }
            XCTAssertEqual(message.systemMessageType, .readReceiptsDisabled)
        }
    }

    func testThatItDoesntInsertsSystemMessage_WhenReceivingReceiptModeUpdateEventWhichHasAlreadybeenApplied() {
        self.syncMOC.performAndWait {
            // GIVEN
            let event = receiptModeUpdateEvent(enabled: true)
            groupConversation.lastServerTimeStamp = event.timestamp

            // WHEN
            performIgnoringZMLogError {
                self.sut.processEvents([event], liveEvents: true, prefetchResult: nil)
            }

            // THEN
            XCTAssertEqual(self.groupConversation?.allMessages.count, 0)
        }
    }

    // MARK: Access Mode

    func testThatItHandlesAccessModeUpdateEvent() {
        self.syncMOC.performAndWait {

            let newAccessMode = ConversationAccessMode(values: ["code", "invite"])
            let newAccessRole = ConversationAccessRole.team

            XCTAssertNotEqual(self.groupConversation.accessMode, newAccessMode)
            XCTAssertNotEqual(self.groupConversation.accessRole, newAccessRole)

            // GIVEN
            let payload = [
                "from": self.otherUser.remoteIdentifier!.transportString(),
                "conversation": self.groupConversation.remoteIdentifier!.transportString(),
                "time": NSDate().transportString(),
                "data": [
                    "access": newAccessMode.stringValue,
                    "access_role": newAccessRole.rawValue
                ],
                "type": "conversation.access-update"
                ] as [String: Any]
            let event = ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!

            // WHEN
            self.sut.processEvents([event], liveEvents: true, prefetchResult: nil)

            // THEN
            XCTAssertEqual(self.groupConversation.accessMode, newAccessMode)
            XCTAssertEqual(self.groupConversation.accessRole, newAccessRole)
        }
    }

    // MARK: Message Timer

    func testThatItHandlesMessageTimerUpdateEvent_Value() {
        syncMOC.performGroupedBlockAndWait {
            XCTAssertNil(self.groupConversation.messageDestructionTimeout)

            // Given
            let payload: [String: Any] = [
                "from": self.otherUser!.remoteIdentifier!.transportString(),
                "conversation": self.groupConversation!.remoteIdentifier!.transportString(),
                "time": NSDate().transportString(),
                "data": ["message_timer": 31536000000],
                "type": "conversation.message-timer-update"
                ]
            let event = ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!

            // WHEN
            self.sut?.processEvents([event], liveEvents: true, prefetchResult: nil)

            // THEN
            XCTAssertEqual(self.groupConversation?.messageDestructionTimeout!, MessageDestructionTimeout.synced(31536000))
            guard let message = self.groupConversation?.lastMessage as? ZMSystemMessage else { return XCTFail() }
            XCTAssertEqual(message.systemMessageType, .messageTimerUpdate)
        }
    }

    func testThatItHandlesMessageTimerUpdateEvent_NoValue() {
        syncMOC.performGroupedBlockAndWait {
            self.groupConversation.messageDestructionTimeout = .synced(300)
            XCTAssertEqual(self.groupConversation.messageDestructionTimeout!, MessageDestructionTimeout.synced(.fiveMinutes))

            // Given
            let payload: [String: Any] = [
                "from": self.otherUser!.remoteIdentifier!.transportString(),
                "conversation": self.groupConversation!.remoteIdentifier!.transportString(),
                "time": NSDate().transportString(),
                "data": ["message_timer": NSNull()],
                "type": "conversation.message-timer-update"
            ]
            let event = ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!

            // WHEN
            self.sut?.processEvents([event], liveEvents: true, prefetchResult: nil)

            // THEN
            XCTAssertNil(self.groupConversation.messageDestructionTimeout)
            guard let message = self.groupConversation.lastMessage as? ZMSystemMessage else { return XCTFail() }
            XCTAssertEqual(message.systemMessageType, .messageTimerUpdate)
        }
    }

    func testThatItGeneratesCorrectSystemMessageWhenSyncedTimeoutTurnedOff() {
        // GIVEN: local & synced timeouts exist
        syncMOC.performGroupedBlockAndWait {
            self.groupConversation.messageDestructionTimeout = .local(.fiveMinutes)
        }

        syncMOC.performGroupedBlockAndWait {
            self.groupConversation.messageDestructionTimeout = .synced(.oneHour)
        }

        syncMOC.performGroupedBlockAndWait {
            XCTAssertNotNil(self.groupConversation.messageDestructionTimeout)

            // "turn off" synced timeout
            let payload: [String: Any] = [
                "from": self.otherUser!.remoteIdentifier!.transportString(),
                "conversation": self.groupConversation!.remoteIdentifier!.transportString(),
                "time": NSDate().transportString(),
                "data": ["message_timer": 0],
                "type": "conversation.message-timer-update"
            ]

            let event = ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!

            // WHEN
            self.sut?.processEvents([event], liveEvents: true, prefetchResult: nil)

            // THEN: the local timeout still exists
            XCTAssertEqual(self.groupConversation?.messageDestructionTimeout!, MessageDestructionTimeout.local(.fiveMinutes))
            guard let message = self.groupConversation?.lastMessage as? ZMSystemMessage else { return XCTFail() }
            XCTAssertEqual(message.systemMessageType, .messageTimerUpdate)

            // but the system message timer reflects the update to the synced timeout
            XCTAssertEqual(0, message.messageTimer)
        }
    }

    func testThatItDiscardsDoubleSystemMessageWhenSyncedTimeoutChanges_Value() {

        syncMOC.performGroupedBlockAndWait {
            XCTAssertNil(self.groupConversation.messageDestructionTimeout)

            // Given
            let messageTimerMillis = 31536000000
            let messageTimer = MessageDestructionTimeoutValue(rawValue: TimeInterval(messageTimerMillis / 1000))
            let selfUser = ZMUser.selfUser(in: self.syncMOC)
            selfUser.remoteIdentifier = UUID.create()

            let payload: [String: Any] = [
                "from": selfUser.remoteIdentifier!.transportString(),
                "conversation": self.groupConversation!.remoteIdentifier!.transportString(),
                "time": NSDate().transportString(),
                "data": ["message_timer": messageTimerMillis],
                "type": "conversation.message-timer-update"
            ]

            let event = ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!

            // WHEN
            self.sut?.processEvents([event], liveEvents: true, prefetchResult: nil) //First event

            XCTAssertEqual(self.groupConversation?.messageDestructionTimeout!, MessageDestructionTimeout.synced(messageTimer))
            guard let firstMessage = self.groupConversation?.lastMessage as? ZMSystemMessage else { return XCTFail() }
            XCTAssertEqual(firstMessage.systemMessageType, .messageTimerUpdate)

            self.sut?.processEvents([event], liveEvents: true, prefetchResult: nil) //Second duplicated event

            // THEN
            XCTAssertEqual(self.groupConversation?.messageDestructionTimeout!, MessageDestructionTimeout.synced(messageTimer))
            guard let secondMessage = self.groupConversation?.lastMessage as? ZMSystemMessage else { return XCTFail() }
            XCTAssertEqual(firstMessage, secondMessage) //Check that no other messages are appended in the conversation
        }
    }

    func testThatItDiscardsDoubleSystemMessageWhenSyncedTimeoutChanges_NoValue() {

        syncMOC.performGroupedBlockAndWait {
            XCTAssertNil(self.groupConversation.messageDestructionTimeout)

            // Given
            let valuedMessageTimerMillis = 31536000000
            let valuedMessageTimer = MessageDestructionTimeoutValue(rawValue: TimeInterval(valuedMessageTimerMillis / 1000))

            let selfUser = ZMUser.selfUser(in: self.syncMOC)
            selfUser.remoteIdentifier = UUID.create()

            let valuedPayload: [String: Any] = [
                "from": selfUser.remoteIdentifier!.transportString(),
                "conversation": self.groupConversation!.remoteIdentifier!.transportString(),
                "time": NSDate(timeIntervalSinceNow: 0).transportString(),
                "data": ["message_timer": valuedMessageTimerMillis],
                "type": "conversation.message-timer-update"
            ]

            let payload: [String: Any] = [
                "from": selfUser.remoteIdentifier!.transportString(),
                "conversation": self.groupConversation!.remoteIdentifier!.transportString(),
                "time": NSDate(timeIntervalSinceNow: 100).transportString(),
                "data": ["message_timer": 0],
                "type": "conversation.message-timer-update"
            ]

            let valuedEvent = ZMUpdateEvent(fromEventStreamPayload: valuedPayload as ZMTransportData, uuid: nil)!
            let event = ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!

            // WHEN

            //First event with valued timer
            self.sut?.processEvents([valuedEvent], liveEvents: true, prefetchResult: nil)
            XCTAssertEqual(self.groupConversation?.messageDestructionTimeout!, MessageDestructionTimeout.synced(valuedMessageTimer))

            //Second event with timer = nil
            self.sut?.processEvents([event], liveEvents: true, prefetchResult: nil)
            XCTAssertNil(self.groupConversation?.messageDestructionTimeout)

            guard let firstMessage = self.groupConversation?.lastMessage as? ZMSystemMessage else { return XCTFail() }
            XCTAssertEqual(firstMessage.systemMessageType, .messageTimerUpdate)

            //Third event with timer = nil
            self.sut?.processEvents([event], liveEvents: true, prefetchResult: nil)

            // THEN
            XCTAssertNil(self.groupConversation?.messageDestructionTimeout)
            guard let secondMessage = self.groupConversation?.lastMessage as? ZMSystemMessage else { return XCTFail() }
            XCTAssertEqual(firstMessage, secondMessage) //Check that no other messages are appended in the conversation
        }
    }

    // MARK: Member join

    func testThatItCreatesAndNotifiesSystemMessagesFromAMemberJoinEvent() {

        self.syncMOC.performAndWait {

            // GIVEN
            let payload = [
                "from": self.otherUser.remoteIdentifier!.transportString(),
                "conversation": self.groupConversation.remoteIdentifier!.transportString(),
                "time": NSDate().transportString(),
                "data": [
                    "user_ids": [self.thirdUser.remoteIdentifier!.transportString()]
                ],
                "type": "conversation.member-join"
                ] as [String: Any]
            let event = ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!

            // WHEN
            self.sut.processEvents([event], liveEvents: true, prefetchResult: nil)

            // THEN
            guard let message = self.groupConversation.lastMessage as? ZMSystemMessage else {
                XCTFail()
                return
            }
            XCTAssertEqual(message.systemMessageType, .participantsAdded)
        }
    }

    func testThatItAddsUsersWithRolesToAConversationAfterAMemberJoinEvent() {

        self.syncMOC.performAndWait {
            // GIVEN
            let user2 = ZMUser.insertNewObject(in: self.syncMOC)
            user2.remoteIdentifier = UUID.create()
            let payload = [
                "from": self.otherUser.remoteIdentifier!.transportString(),
                "conversation": self.groupConversation.remoteIdentifier!.transportString(),
                "time": NSDate().transportString(),
                "data": [
                    "user_ids": [user2.remoteIdentifier!.transportString()],
                    "users": [[
                        "id": user2.remoteIdentifier!.transportString(),
                        "conversation_role": "wire_admin"
                        ]]
                ],
                "type": "conversation.member-join"
                ] as [String: Any]
            let event = ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!

            // WHEN
            groupConversation.addParticipantsAndUpdateConversationState(users: [otherUser], role: nil)
            XCTAssertEqual(self.groupConversation.localParticipants.count, 2)
            self.sut.processEvents([event], liveEvents: true, prefetchResult: nil)

            // THEN
            XCTAssertEqual(groupConversation.localParticipants.count, 3)
            let admins = groupConversation.participantRoles.filter({ (participantRole) -> Bool in
                participantRole.role?.name == "wire_admin"
            })
            XCTAssertEqual(admins.count, 1)
        }
    }

    func testThatItIgnoresMemberJoinEvents_IfMemberIsAlreadyPartOfConversation() {

        self.syncMOC.performAndWait {

            // GIVEN
            self.groupConversation.addParticipantAndUpdateConversationState(user: otherUser, role: nil)

            let payload = [
                "from": self.otherUser.remoteIdentifier!.transportString(),
                "conversation": self.groupConversation.remoteIdentifier!.transportString(),
                "time": NSDate().transportString(),
                "data": [
                    "user_ids": [self.otherUser.remoteIdentifier!.transportString()]
                ],
                "type": "conversation.member-join"
                ] as [String: Any]
            let event = ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!
            let messageCountBeforeProcessing = self.groupConversation.allMessages.count

            // WHEN
            self.sut.processEvents([event], liveEvents: true, prefetchResult: nil)

            // THEN
            XCTAssertEqual(self.groupConversation.allMessages.count, messageCountBeforeProcessing)
        }
    }

    // MARK:  Member leave

    func testThatItCreatesAndNotifiesSystemMessagesFromAMemberLeaveEvent() {

        self.syncMOC.performAndWait {

            // GIVEN
            self.groupConversation.addParticipantAndUpdateConversationState(user: thirdUser, role: nil)

            let payload = [
                "from": self.otherUser.remoteIdentifier!.transportString(),
                "conversation": self.groupConversation.remoteIdentifier!.transportString(),
                "time": NSDate().transportString(),
                "data": [
                    "user_ids": [self.thirdUser.remoteIdentifier!.transportString()]
                ],
                "type": "conversation.member-leave"
                ] as [String: Any]
            let event = ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!

            // WHEN
            self.sut.processEvents([event], liveEvents: true, prefetchResult: nil)

            // THEN
            guard let message = self.groupConversation.lastMessage as? ZMSystemMessage else {
                XCTFail()
                return
            }
            print(message.systemMessageType.rawValue)
            XCTAssertEqual(message.systemMessageType, .participantsRemoved)
        }
    }

    func testThatItIgnoresMemberLeaveEvents_IfMemberIsNotPartOfConversation() {

        self.syncMOC.performAndWait {

            // GIVEN
            let payload = [
                "from": self.otherUser.remoteIdentifier!.transportString(),
                "conversation": self.groupConversation.remoteIdentifier!.transportString(),
                "time": NSDate().transportString(),
                "data": [
                    "user_ids": [self.thirdUser.remoteIdentifier!.transportString()]
                ],
                "type": "conversation.member-leave"
                ] as [String: Any]
            let event = ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!
            let messageCountBeforeProcessing = self.groupConversation.allMessages.count

            // WHEN
            self.sut.processEvents([event], liveEvents: true, prefetchResult: nil)

            // THEN
            XCTAssertEqual(self.groupConversation.allMessages.count, messageCountBeforeProcessing)
        }
    }

    // MARK: Member update

    func testThatItAddsAUserReceivedWithAMemberUpdate() {

        syncMOC.performAndWait {

            let userId = UUID.create()
            let selfUser = ZMUser.selfUser(in: self.syncMOC)
            selfUser.remoteIdentifier = UUID.create()

            // GIVEN
            let payload: [String: Any] = [
                "from": selfUser.remoteIdentifier!.transportString(),
                "conversation": self.groupConversation!.remoteIdentifier!.transportString(),
                "time": NSDate(timeIntervalSinceNow: 100).transportString(),
                "data": [
                    "target": userId.transportString(),
                    "conversation_role": "new"
                ],
                "type": "conversation.member-update"
            ]

            // WHEN
            let event = ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!
            self.sut?.processEvents([event], liveEvents: true, prefetchResult: nil)

            // THEN
            guard let participant = self.groupConversation.participantRoles
                .first(where: {$0.user.remoteIdentifier == userId}) else {
                    return XCTFail("No user in convo")
            }
            XCTAssertEqual(participant.role?.name, "new")
        }
    }

    func testThatItChangesRoleAfterMemberUpdate() {

        syncMOC.performAndWait {

            let userId = UUID.create()

            let user = ZMUser.insertNewObject(in: self.syncMOC)
            user.remoteIdentifier = userId

            let selfUser = ZMUser.selfUser(in: self.syncMOC)
            selfUser.remoteIdentifier = UUID.create()

            let oldRole = Role.insertNewObject(in: self.syncMOC)
            oldRole.name = "old"
            oldRole.conversation = self.groupConversation

            self.groupConversation.addParticipantAndUpdateConversationState(user: user, role: oldRole)

            let newRole = Role.insertNewObject(in: self.syncMOC)
            newRole.name = "new"
            newRole.conversation = self.groupConversation
            self.syncMOC.saveOrRollback()

            // GIVEN
            let payload: [String: Any] = [
                "from": selfUser.remoteIdentifier!.transportString(),
                "conversation": self.groupConversation!.remoteIdentifier!.transportString(),
                "time": NSDate(timeIntervalSinceNow: 100).transportString(),
                "data": [
                    "target": userId.transportString(),
                    "conversation_role": "new"
                ],
                "type": "conversation.member-update"
            ]

            // WHEN
            let event = ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!
            self.sut?.processEvents([event], liveEvents: true, prefetchResult: nil)

            // THEN
            guard let participant = self.groupConversation.participantRoles
                .first(where: {$0.user == user}) else {
                    return XCTFail("No user in convo")
            }
            XCTAssertEqual(participant.role, newRole)
        }
    }

    func testThatItChangesSelfRoleAfterMemberUpdate() {

        syncMOC.performAndWait {

            let selfUser = ZMUser.selfUser(in: self.syncMOC)
            selfUser.remoteIdentifier = UUID.create()

            let oldRole = Role.insertNewObject(in: self.syncMOC)
            oldRole.name = "old"
            oldRole.conversation = self.groupConversation

            self.groupConversation.addParticipantAndUpdateConversationState(user: selfUser, role: oldRole)

            let newRole = Role.insertNewObject(in: self.syncMOC)
            newRole.name = "new"
            newRole.conversation = self.groupConversation
            self.syncMOC.saveOrRollback()

            // GIVEN
            let payload: [String: Any] = [
                "from": selfUser.remoteIdentifier!.transportString(),
                "conversation": self.groupConversation!.remoteIdentifier!.transportString(),
                "time": NSDate(timeIntervalSinceNow: 100).transportString(),
                "data": [
                    "target": selfUser.remoteIdentifier.transportString(),
                    "conversation_role": "new"
                ],
                "type": "conversation.member-update"
            ]

            // WHEN
            let event = ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!
            self.sut?.processEvents([event], liveEvents: true, prefetchResult: nil)

            // THEN
            guard let participant = self.groupConversation.participantRoles
                .first(where: {$0.user == selfUser}) else {
                    return XCTFail("No user in convo")
            }
            XCTAssertEqual(participant.role, newRole)
        }
    }


    // MARK: - Helpers

    func qualifiedID(for conversation: ZMConversation) -> Payload.QualifiedUserID {
        var qualifiedID: Payload.QualifiedUserID!
        syncMOC.performGroupedBlockAndWait {
            qualifiedID = Payload.QualifiedUserID(uuid: conversation.remoteIdentifier!,
                                                  domain: conversation.domain!)
        }
        return qualifiedID
    }

    func startSlowSync() {
        syncMOC.performGroupedBlockAndWait {
            self.mockSyncProgress.currentSyncPhase = .fetchingConversations
        }
    }

    func fetchConversation(with response: ZMTransportResponse) {
        syncMOC.performGroupedBlockAndWait {
            // given
            self.groupConversation.needsToBeUpdatedFromBackend = true
            self.sut.objectsDidChange(Set([self.groupConversation]))

            // when
            let request = self.sut.nextRequest()!
            request.complete(with: response)
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }

    func fetchConversationListDuringSlowSync() {
        syncMOC.performGroupedBlockAndWait {
            let qualifiedConversationID = Payload.QualifiedUserID(uuid: self.groupConversation.remoteIdentifier!,
                                                                  domain: self.groupConversation.domain!)

            let listRequest = self.sut.nextRequest()!
            guard let listPayload = Payload.PaginationStatus(listRequest) else {
                return XCTFail()
            }

            listRequest.complete(with: self.successfulResponse(request: listPayload, conversations: [qualifiedConversationID]))
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    

    func fetchConversationListDuringSlowSyncWithEmptyResponse() {
        syncMOC.performGroupedBlockAndWait {
            let request = self.sut.nextRequest()!
            guard let listPayload = Payload.PaginationStatus(request) else {
                return XCTFail()
            }

            request.complete(with: self.successfulResponse(request: listPayload, conversations: []))
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }

    func fetchConversationListDuringSlowSyncWithPermanentError() {
        syncMOC.performGroupedBlockAndWait {
            let request = self.sut.nextRequest()!
            request.complete(with: self.responseFailure(code: 404, label: .noEndpoint))
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }

    func fetchConversationsDuringSlowSync(notFound: [Payload.QualifiedUserID] = [],
                                          failed: [Payload.QualifiedUserID] = []) {
        syncMOC.performGroupedBlockAndWait {

            // when
            let request = self.sut.nextRequest()!

            guard let payload = Payload.QualifiedUserIDList(request) else {
                return XCTFail()
            }

            request.complete(with: self.successfulResponse(request: payload, notFound: notFound, failed: failed))
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }

    func successfulResponse(request: Payload.PaginationStatus,
                            conversations: [Payload.QualifiedUserID]) -> ZMTransportResponse {
        let payload = Payload.PaginatedQualifiedConversationIDList(conversations: conversations,
                                                                   pagingState: "",
                                                                   hasMore: false)

        let payloadData = payload.payloadData()!
        let payloadString = String(bytes: payloadData, encoding: .utf8)!
        let response = ZMTransportResponse(payload: payloadString as ZMTransportData,
                                           httpStatus: 200,
                                           transportSessionError: nil)

        return response
    }

    func successfulResponse(request: Payload.QualifiedUserIDList,
                            notFound: [Payload.QualifiedUserID],
                            failed: [Payload.QualifiedUserID]) -> ZMTransportResponse {


        let found = request.qualifiedIDs.map({ conversation(uuid: $0.uuid, domain: $0.domain)})
        let payload = Payload.QualifiedConversationList(found: found, notFound: notFound, failed: failed)
        let payloadData = payload.payloadData()!
        let payloadString = String(bytes: payloadData, encoding: .utf8)!
        let response = ZMTransportResponse(payload: payloadString as ZMTransportData,
                                           httpStatus: 200,
                                           transportSessionError: nil)

        return response
    }

    func conversation(uuid: UUID, domain: String?, type: BackendConversationType = .group) -> Payload.Conversation {
        return Payload.Conversation(qualifiedID: nil,
                                    id: uuid,
                                    type: type.rawValue,
                                    creator: nil,
                                    access: nil,
                                    accessRole: nil,
                                    name: nil,
                                    members: nil,
                                    lastEvent: nil,
                                    lastEventTime: nil,
                                    teamID: nil,
                                    messageTimer: nil,
                                    readReceiptMode: nil)
    }

    func updateEvent<Event: EventData>(from data: Event,
                                     conversationID: Payload.QualifiedUserID? = nil,
                                     senderID: Payload.QualifiedUserID? = nil,
                                     timestamp: Date? = nil) -> ZMUpdateEvent {

        let event = Payload.ConversationEvent<Event>(id: conversationID?.uuid,
                                                     qualifiedID: conversationID,
                                                     from: senderID?.uuid,
                                                     qualifiedFrom: senderID,
                                                     timestamp: timestamp,
                                                     type: ZMUpdateEvent.eventTypeString(for: Event.eventType),
                                                     data: data)

        let payload = try! JSONSerialization.jsonObject(with: event.payloadData()!, options: []) as? [String: Any]
        return ZMUpdateEvent(fromEventStreamPayload: payload! as ZMTransportData, uuid: UUID())!
    }

}
