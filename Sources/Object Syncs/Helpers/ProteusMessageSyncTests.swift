//
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

class ProteusMessageSyncTests: MessagingTestBase {

    var sut: ProteusMessageSync<MockOTREntity>!
    var mockApplicationStatus: MockApplicationStatus!
    let domain =  "example.com"
    var qualifiedEndpoint: String!
    var legacyEndpoint: String!

    override func setUp() {
        super.setUp()

        mockApplicationStatus = MockApplicationStatus()
        sut = ProteusMessageSync<MockOTREntity>(context: syncMOC, applicationStatus: mockApplicationStatus)

        syncMOC.performGroupedBlockAndWait { [self] in
            otherUser.domain = domain
            qualifiedEndpoint = "/conversations/\(domain)/\(groupConversation.remoteIdentifier!.transportString())/proteus/messages"
            legacyEndpoint = "/conversations/\(groupConversation.remoteIdentifier!.transportString())/otr/messages"
        }
    }

    func testThatItCallsSyncCompletionHandler_WhenResponseIsSuccessfull() throws {
        syncMOC.performGroupedBlockAndWait { [self] in
            // given
            let message = MockOTREntity(conversation: self.groupConversation, context: self.syncMOC)

            // expect
            let expectation = self.expectation(description: "completion is called")
            sut.sync(message) { (result, _) in
                if case .success(()) = result {
                    expectation.fulfill()
                }
            }

            // when
            let payload = Payload.MessageSendingStatus(time: Date(),
                                                       missing: [:],
                                                       redundant: [:],
                                                       deleted: [:],
                                                       failedToSend: [:])
            let payloadAsString = String(bytes: payload.payloadData()!, encoding: .utf8)!
            sut.nextRequest()?.complete(with: ZMTransportResponse(payload: payloadAsString as ZMTransportData, httpStatus: 201, transportSessionError: nil))
        }

        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
    }

    func testThatItCallsSyncCompletionHandler_WhenResponseIsNonRecoverableFailure() throws {
        syncMOC.performGroupedBlockAndWait { [self] in
            // given
            let message = MockOTREntity(conversation: self.groupConversation, context: self.syncMOC)

            // expect
            let expectation = self.expectation(description: "completion is called")
            sut.sync(message) { (result, _) in
                if case .failure(let error) = result, error == .gaveUpRetrying {
                    expectation.fulfill()
                }
            }

            // when
            sut.nextRequest()?.complete(with: ZMTransportResponse(payload: nil, httpStatus: 500, transportSessionError: nil))
        }

        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
    }

    func testThatItRetriesTheRequest_WhenQualifiedEndpointIsNotAvailble() throws {
        syncMOC.performGroupedBlockAndWait { [self] in
            // given
            let message = MockOTREntity(conversation: self.groupConversation, context: self.syncMOC)
            sut.sync(message) { (result, _) in }

            // when
            let payload = Payload.ResponseFailure(code: 404, label: .noEndpoint, message: "")
            let payloadAsString = String(bytes: payload.payloadData()!, encoding: .utf8)!
            sut.nextRequest()?.complete(with: ZMTransportResponse(payload: payloadAsString as ZMTransportData, httpStatus: payload.code, transportSessionError: nil))
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        syncMOC.performGroupedBlockAndWait { [self] in
            // then
            XCTAssertEqual(sut.nextRequest()?.path, legacyEndpoint)
        }
    }

    func testThatItRetriesTheRequest_WhenResponseSaysClientAreMissing() throws {
        syncMOC.performGroupedBlockAndWait { [self] in
            // given
            let message = MockOTREntity(conversation: self.groupConversation, context: self.syncMOC)
            sut.sync(message) { (result, _) in }

            // when
            let clientID = UUID().transportString()
            let missing: Payload.ClientListByQualifiedUserID =
                [self.domain:
                    [self.otherUser.remoteIdentifier.transportString(): [clientID]]
                ]
            let payload = Payload.MessageSendingStatus(time: Date(),
                                                       missing: missing,
                                                       redundant: [:],
                                                       deleted: [:],
                                                       failedToSend: [:])
            let payloadAsString = String(bytes: payload.payloadData()!, encoding: .utf8)!
            sut.nextRequest()?.complete(with: ZMTransportResponse(payload: payloadAsString as ZMTransportData, httpStatus: 412, transportSessionError: nil))
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        syncMOC.performGroupedBlockAndWait { [self] in
            // then
            XCTAssertEqual(sut.nextRequest()?.path, qualifiedEndpoint)
        }
    }

    func testThatItDetectsThatSelfClientIsDeleted_WhenResponseSaysClientIsUnknown() throws {
            syncMOC.performGroupedBlockAndWait { [self] in
                // given
                let message = MockOTREntity(conversation: self.groupConversation, context: self.syncMOC)
                sut.sync(message) { (result, _) in }

                // when
                let payload = Payload.ResponseFailure(code: 403, label: .unknownClient, message: "")
                let payloadAsString = String(bytes: payload.payloadData()!, encoding: .utf8)!
                sut.nextRequest()?.complete(with: ZMTransportResponse(payload: payloadAsString as ZMTransportData, httpStatus: payload.code, transportSessionError: nil))
            }
            XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

            syncMOC.performGroupedBlockAndWait { [self] in
                // then
                XCTAssertTrue(mockApplicationStatus.mockClientRegistrationStatus.deletionCalls > 0)
            }
    }

    func testThatItAssignsRequestExpirationDate_WhenAvailableOnMessage() throws {
        syncMOC.performGroupedBlockAndWait { [self] in
            // given
            let expirationDate = Date(timeIntervalSinceNow: 100)
            let message = MockOTREntity(conversation: self.groupConversation, context: self.syncMOC)
            message.expirationDate = expirationDate
            sut.sync(message) { (result, _) in }

            // when
            let request = sut.nextRequest()

            // then
            XCTAssertEqual(request?.expirationDate, expirationDate)
        }
    }

}
