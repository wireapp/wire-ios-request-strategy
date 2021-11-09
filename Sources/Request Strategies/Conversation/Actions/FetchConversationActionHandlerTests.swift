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

final class FetchConversationActionHandlerTests: MessagingTestBase {
    
    private var key: String!
    private var code: String!
    
    private var sut: FetchConversationActionHandler!

    override func setUp() {
        super.setUp()
        
        key = UUID().uuidString
        code = UUID().uuidString
        
        sut = FetchConversationActionHandler(context: syncMOC)
    }
    
    override func tearDown() {
        sut = nil
        
        super.tearDown()
    }
    
    func testThatItCreatesAnExpectedRequestForFetchingConversationInformation() throws {
        try syncMOC.performGroupedAndWait { [self] syncMOC in
            // given
            let action = FetchConversationAction(key: key, code: code)
            
            // when
            let request = try XCTUnwrap(sut.request(for: action))
            
            // then
            XCTAssertEqual(request.path, "/conversations/join?key=\(key!)&code=\(code!)")
        }
    }
    
    func testThatItReturnsConversationIDAndNameWhenTheRequestSucceeded() {
        syncMOC.performGroupedAndWait { [self] syncMOC in
            // given
            let expectation = self.expectation(description: "Result Handler was called")
            
            let expectedConversationID = UUID()
            let expectedConversationName = UUID().uuidString
            
            var resultConversationID: UUID?
            var resultConversationName: String?
            var action = FetchConversationAction(key: key, code: code)
            action.onResult { result in
                if case .success((let id, let name)) = result {
                    resultConversationID = id
                    resultConversationName = name
                    expectation.fulfill()
                }
            }
            
            let payload = ["id": expectedConversationID.uuidString,
                           "name": expectedConversationName]
            let response = ZMTransportResponse(payload: payload as ZMTransportData, httpStatus: 200, transportSessionError: nil)
            
            // when
            self.sut.handleResponse(response, action: action)
            
            // then
            XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
            XCTAssertEqual(resultConversationID!, expectedConversationID)
            XCTAssertEqual(resultConversationName, expectedConversationName)
        }
    }
    
    func testThatItFailsWhenTheRequestIsFailed() {
        syncMOC.performGroupedAndWait { [self] syncMOC in
            // given
            let expectation = self.expectation(description: "Result Handler was called")
            
            var action = FetchConversationAction(key: key, code: code)
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
        let errorResponses: [(ConversationFetchError, ZMTransportResponse)] = [
            (.noTeamMember, ZMTransportResponse(payload: ["label": "no-team-member"] as ZMTransportData, httpStatus: 403, transportSessionError: nil)),
            (.accessDenied, ZMTransportResponse(payload: ["label": "access-denied"] as ZMTransportData, httpStatus: 403, transportSessionError: nil)),
            (.invalidCode, ZMTransportResponse(payload: ["label": "no-conversation-code"] as ZMTransportData, httpStatus: 404, transportSessionError: nil)),
            (.noConversation, ZMTransportResponse(payload: ["label": "no-conversation"] as ZMTransportData, httpStatus: 404, transportSessionError: nil))
        ]

        for (expectedError, response) in errorResponses {
            if case ConversationFetchError(response: response) = expectedError {
                // success
            } else {
                XCTFail()
            }
        }
    }

}
