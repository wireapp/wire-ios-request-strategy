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

    // TODO jacob this method is duplicated. Move to a better place
    func responseFailure(code: Int, label: Payload.ResponseFailure.Label, message: String = "") -> ZMTransportResponse {
        let responseFailure = Payload.ResponseFailure(code: code, label: label, message: message)
        let payloadData = responseFailure.payloadData()!
        let payloadString = String(bytes: payloadData, encoding: .utf8)!
        let response = ZMTransportResponse(payload: payloadString as ZMTransportData,
                                           httpStatus: code,
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

}
