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


import Foundation
import XCTest
import WireDataModel
import WireRequestStrategy

// MARK: - Confirmation message
extension ClientMessageTranscoderTests {
    
    func testThatItSendsAConfirmationMessage() {
        self.syncMOC.performGroupedBlockAndWait {
            
            // GIVEN
            let confirmationMessage = self.oneToOneConversation.appendClientMessage(with: ZMGenericMessage.message(content: ZMConfirmation.confirm(messageId: UUID(), type: .DELIVERED)))!
            self.syncMOC.saveOrRollback()
            self.sut.contextChangeTrackers.forEach { $0.objectsDidChange(Set([confirmationMessage])) }
            
            // WHEN
            guard let request = self.sut.nextRequest() else { return XCTFail() }
            
            // THEN
            guard let message = self.outgoingEncryptedMessage(from: request, for: self.otherClient) else { return XCTFail() }
            XCTAssertTrue(message.hasConfirmation())
        }
    }

    func testThatItDoesNotSendAnyConfirmationWhenItIsStillFetchingNotificationsInTheBackground() {
        syncMOC.performGroupedBlockAndWait {

            // Given
            let confirmationMessage = self.oneToOneConversation.appendClientMessage(with: ZMGenericMessage.message(content: ZMConfirmation.confirm(messageId: UUID(), type: .DELIVERED)))!
            self.syncMOC.saveOrRollback()
            self.sut.contextChangeTrackers.forEach { $0.objectsDidChange(Set([confirmationMessage])) }

            // When
            self.mockApplicationStatus.notificationFetchStatus = .inProgress

            // Then
            XCTAssertNil(self.sut.nextRequest())

            // When
            self.mockApplicationStatus.notificationFetchStatus = .done
            // Then
            guard let request = self.sut.nextRequest() else { return XCTFail() }

            // THEN
            guard let message = self.outgoingEncryptedMessage(from: request, for: self.otherClient) else { return XCTFail() }
            XCTAssertTrue(message.hasConfirmation())
        }
    }

    func testThatItDeletesTheConfirmationMessageWhenSentSuccessfully() {

        // GIVEN
        var confirmationMessage: ZMMessage!
        self.syncMOC.performGroupedBlockAndWait {

            confirmationMessage = self.oneToOneConversation.appendClientMessage(with: ZMGenericMessage.message(content: ZMConfirmation.confirm(messageId: UUID(), type: .DELIVERED)))
            self.syncMOC.saveOrRollback()
            self.sut.contextChangeTrackers.forEach { $0.objectsDidChange(Set([confirmationMessage])) }

            // WHEN
            guard let request = self.sut.nextRequest() else { return XCTFail() }
            request.complete(with: ZMTransportResponse(payload: NSDictionary(), httpStatus: 200, transportSessionError: nil))
        }
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        self.syncMOC.performGroupedBlockAndWait {
            XCTAssertTrue(confirmationMessage.isZombieObject)
        }
    }
    
}
