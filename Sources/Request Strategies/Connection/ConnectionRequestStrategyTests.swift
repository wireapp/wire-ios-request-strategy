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

class ConnectionRequestStrategyTests: MessagingTestBase {

    var sut: ConnectionRequestStrategy!
    var mockApplicationStatus: MockApplicationStatus!
    var mockSyncProgress: MockSyncProgress!

    override func setUp() {
        super.setUp()

        mockApplicationStatus = MockApplicationStatus()
        mockApplicationStatus.mockSynchronizationState = .online
        mockSyncProgress = MockSyncProgress()

        sut = ConnectionRequestStrategy(withManagedObjectContext: syncMOC,
                                        applicationStatus: mockApplicationStatus,
                                        syncProgress: mockSyncProgress)
        sut.useFederationEndpoint = true
    }

    override func tearDown() {
        sut = nil
        mockSyncProgress = nil
        mockApplicationStatus = nil

        super.tearDown()
    }

    // MARK: Request generation

    func testThatRequestToFetchConversationIsGenerated_WhenNeedsToBeUpdatedFromBackendIsTrue_Federated() {
        syncMOC.performGroupedBlockAndWait {
            // given
            self.sut.useFederationEndpoint = true
            let connection = ZMConnection.insertNewObject(in: self.syncMOC)
            connection.to = self.otherUser
            connection.needsToBeUpdatedFromBackend = true
            self.sut.contextChangeTrackers.forEach { $0.objectsDidChange(Set([connection])) }

            // when
            let request = self.sut.nextRequest()!

            // then
            XCTAssertEqual(request.path, "/connections/\(self.otherUser.domain!)/\(self.otherUser.remoteIdentifier!)")
            XCTAssertEqual(request.method, .methodGET)
        }
    }

    func testThatRequestToFetchConversationIsGenerated_WhenNeedsToBeUpdatedFromBackendIsTrue_NonFederated() {
        syncMOC.performGroupedBlockAndWait {
            // given
            let connection = ZMConnection.insertNewObject(in: self.syncMOC)
            connection.to = self.otherUser
            connection.needsToBeUpdatedFromBackend = true
            self.sut.contextChangeTrackers.forEach { $0.objectsDidChange(Set([connection])) }

            // when
            let request = self.sut.nextRequest()!

            // then
            XCTAssertEqual(request.path, "/connections/\(self.otherUser.remoteIdentifier!)")
            XCTAssertEqual(request.method, .methodGET)
        }
    }

    // MARK: Slow sync

    func testThatRequestToFetchAllConnectionsIsGenerated_DuringFetchingConnectionsSyncPhase_Federated() {
        syncMOC.performGroupedBlockAndWait {
            // given
            self.sut.useFederationEndpoint = true
            self.mockSyncProgress.currentSyncPhase = .fetchingConnections

            // when
            let request = self.sut.nextRequest()!

            // then
            XCTAssertEqual(request.path, "/list-connections")
            XCTAssertEqual(request.method, .methodPOST)
        }
    }

    func testThatRequestToFetchAllConnectionsIsGenerated_DuringFetchingConnectionsSyncPhase_NonFederated() {
        syncMOC.performGroupedBlockAndWait {
            // given
            self.sut.useFederationEndpoint = false
            self.mockSyncProgress.currentSyncPhase = .fetchingConnections

            // when
            let request = self.sut.nextRequest()!

            // then
            XCTAssertEqual(request.path, "/connections?size=200")
            XCTAssertEqual(request.method, .methodGET)
        }
    }

    func testThatRequestToFetchAllConnectionsIsNotGenerated_WhenFetchIsAlreadyInProgress() {
        syncMOC.performGroupedBlockAndWait {
            // given
            self.mockSyncProgress.currentSyncPhase = .fetchingConnections
            XCTAssertNotNil(self.sut.nextRequest())

            // then
            XCTAssertNil(self.sut.nextRequest())
        }
    }

    func testThatFetchingConnectionsSyncPhaseIsFinished_WhenFetchIsCompleted() {
        // given
        startSlowSync()

        // when
        fetchConnectionsDuringSlowSync(connections: [createConnection()])

        // then
        XCTAssertEqual(mockSyncProgress.didFinishCurrentSyncPhase, .fetchingConnections)
    }

    func testThatFetchingConnectionsSyncPhaseIsFinished_WhenThereIsNoConnectionsToFetch() {
        // given
        startSlowSync()

        // when
        fetchConnectionsDuringSlowSync(connections: [])

        // then
        XCTAssertEqual(mockSyncProgress.didFinishCurrentSyncPhase, .fetchingConnections)
    }

    func testThatFetchingConnectionsSyncPhaseIsFailed_WhenReceivingAPermanentError() {
        // given
        startSlowSync()

        // when
        fetchConnectionsDuringSlowSyncWithPermanentError()

        // then
        XCTAssertEqual(mockSyncProgress.didFailCurrentSyncPhase, .fetchingConnections)
    }

    // MARK: Response processing

    // MARK: Event processing

    // MARK: Helpers

    func createConnection() -> Payload.Connection {
        let fromID = UUID()
        let toID = UUID()
        let toDomain = owningDomain
        let qualifiedTo = QualifiedID(uuid: toID, domain: toDomain)
        let conversationID = UUID()
        let conversationDomain = owningDomain
        let qualifiedConversation = QualifiedID(uuid: conversationID, domain: conversationDomain)

        return Payload.Connection(from: fromID,
                                  to: toID,
                                  qualifiedTo: qualifiedTo,
                                  conversationID: conversationID,
                                  qualifiedConversationID: qualifiedConversation,
                                  lastUpdate: Date(),
                                  status: .accepted)
    }

    func startSlowSync() {
        syncMOC.performGroupedBlockAndWait {
            self.mockSyncProgress.currentSyncPhase = .fetchingConnections
        }
    }

    func fetchConnectionsDuringSlowSync(connections: [Payload.Connection]) {
        syncMOC.performGroupedBlockAndWait {
            let request = self.sut.nextRequest()!
            guard let payload = Payload.PaginationStatus(request) else {
                return XCTFail()
            }

            request.complete(with: self.successfulResponse(request: payload, connections: connections))
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }

    func fetchConnectionsDuringSlowSyncWithPermanentError() {
        syncMOC.performGroupedBlockAndWait {
            let request = self.sut.nextRequest()!
            request.complete(with: self.responseFailure(code: 404, label: .noEndpoint))
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }

    func successfulResponse(request: Payload.PaginationStatus,
                            connections: [Payload.Connection]) -> ZMTransportResponse {

        let payload = Payload.PaginatedConnectionList(connections: connections,
                                        pagingState: "",
                                        hasMore: false)

        let payloadData = payload.payloadData()!
        let payloadString = String(bytes: payloadData, encoding: .utf8)!
        let response = ZMTransportResponse(payload: payloadString as ZMTransportData,
                                           httpStatus: 200,
                                           transportSessionError: nil)

        return response
    }

}
