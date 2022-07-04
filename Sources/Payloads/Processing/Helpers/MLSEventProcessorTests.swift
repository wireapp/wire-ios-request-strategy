// Wire
// Copyright (C) 2022 Wire Swiss GmbH
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
@testable import WireRequestStrategy

private class CoreCryptoMock: CoreCryptoProtocol {

    var hasWelcomeMessageBeenProcessed = false
    func wire_conversationExists(conversationId: [UInt8]) -> Bool {
        return hasWelcomeMessageBeenProcessed
    }

    func wire_setCallbacks(callbacks: CoreCryptoCallbacks) throws {
        // no op
    }

    func wire_clientPublicKey() throws -> [UInt8] {
        return []
    }

    func wire_clientKeypackages(amountRequested: UInt32) throws -> [[UInt8]] {
        return []
    }

    func wire_createConversation(conversationId: [UInt8], config: ConversationConfiguration) throws -> MemberAddedMessages? {
        return nil
    }

    func wire_processWelcomeMessage(welcomeMessage: [UInt8]) throws -> [UInt8] {
        return []
    }

    func wire_addClientsToConversation(conversationId: [UInt8], clients: [Invitee]) throws -> MemberAddedMessages? {
        return nil
    }

    func wire_removeClientsFromConversation(conversationId: [UInt8], clients: [[UInt8]]) throws -> [UInt8]? {
        return nil
    }

    func wire_leaveConversation(conversationId: [UInt8], otherClients: [[UInt8]]) throws -> ConversationLeaveMessages {
        return ConversationLeaveMessages(selfRemovalProposal: [], otherClientsRemovalCommit: [])
    }

    func wire_decryptMessage(conversationId: [UInt8], payload: [UInt8]) throws -> [UInt8]? {
        return nil
    }

    func wire_encryptMessage(conversationId: [UInt8], message: [UInt8]) throws -> [UInt8] {
        return []
    }

    func wire_newAddProposal(conversationId: [UInt8], keyPackage: [UInt8]) throws -> [UInt8] {
        return []
    }

    func wire_newUpdateProposal(conversationId: [UInt8]) throws -> [UInt8] {
        return []
    }

    func wire_newRemoveProposal(conversationId: [UInt8], clientId: [UInt8]) throws -> [UInt8] {
        return []
    }

}

class MLSEventProcessorTests: MessagingTestBase {

    private var coreCryptoMock: CoreCryptoMock!
    var conversation: ZMConversation!

    override func setUp() {
        super.setUp()
        coreCryptoMock = CoreCryptoMock()
        syncMOC.performGroupedBlockAndWait {
            self.syncMOC.coreCrypto = self.coreCryptoMock
            self.conversation = ZMConversation.insertNewObject(in: self.syncMOC)
            self.conversation.remoteIdentifier = UUID()
        }
    }

    override func tearDown() {
        coreCryptoMock = nil
        conversation = nil
        super.tearDown()
    }

    func test_itUpdatesConversation_WhenProtocolIsMLS_AndWelcomeMessageWasProcessed() {
        assert_isPendingWelcomeMessage(
            originalValue: true,
            expectedValue: false,
            hasWelcomeMessageBeenProcessed: true,
            protocol: "mls"
        )
    }

    func test_itUpdatesConversation_WhenProtocolIsMLS_AndWelcomeMessageWasNotProcessed() {
        assert_isPendingWelcomeMessage(
            originalValue: false,
            expectedValue: true,
            hasWelcomeMessageBeenProcessed: false,
            protocol: "mls"
        )
    }

    func test_itDoesntUpdateConversation_WhenProtocolIsNotMLS() {
        assert_isPendingWelcomeMessage(
            originalValue: true,
            expectedValue: true,
            hasWelcomeMessageBeenProcessed: true,
            protocol: "proteus"
        )
    }

    func assert_isPendingWelcomeMessage(
        originalValue: Bool,
        expectedValue: Bool,
        hasWelcomeMessageBeenProcessed: Bool,
        protocol: String
    ) {
        syncMOC.performGroupedBlockAndWait {
            // Given
            self.conversation.isPendingWelcomeMessage = originalValue
            self.coreCryptoMock.hasWelcomeMessageBeenProcessed = hasWelcomeMessageBeenProcessed

            // When
            MLSEventProcessor.shared.updateConversationIfNeeded(
                self.conversation,
                protocol: `protocol`,
                context: self.syncMOC
            )

            // Then
            XCTAssertEqual(self.conversation.isPendingWelcomeMessage, expectedValue)
        }
    }
}
