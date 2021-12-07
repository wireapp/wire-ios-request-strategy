//
// Wire
// Copyright (C) 2018 Wire Swiss GmbH
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

import WireTesting
@testable import WireRequestStrategy

class AssetRequestFactoryTests: ZMTBaseTest {

    private var coreDataStack: CoreDataStack!
    private var sut: AssetRequestFactory!

    override func setUp() {
        super.setUp()
        coreDataStack = createCoreDataStack()
        sut = AssetRequestFactory()
    }

    override func tearDown() {
        XCTAssert(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        coreDataStack = nil
        sut = nil
        super.tearDown()
    }

    func testThatItReturnsExpiringForRegularConversation() {
        // given
        let conversation = ZMConversation.insertNewObject(in: coreDataStack.viewContext)

        // when & then
        XCTAssertEqual(AssetRequestFactory.Retention(conversation: conversation), .expiring)
    }

    func testThatItReturnsEternalInfrequentAccessForTeamUserConversation() {
        let moc = coreDataStack.syncContext
        moc.performGroupedBlock {
            // given
            let conversation = ZMConversation.insertNewObject(in: moc)
            let team = Team.insertNewObject(in: moc)
            team.remoteIdentifier = .init()

            // when
            let selfUser = ZMUser.selfUser(in: moc)
            let membership = Member.getOrCreateMember(for: selfUser, in: team, context: moc)
            XCTAssertNotNil(membership.team)
            XCTAssertTrue(selfUser.hasTeam)

            // then
            XCTAssertEqual(AssetRequestFactory.Retention(conversation: conversation), .eternalInfrequentAccess)
        }

        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.2))
    }

    func testThatItReturnsEternalInfrequentAccessForConversationWithTeam() {
        let moc = coreDataStack.syncContext
        moc.performGroupedBlock {
            // given
            let conversation = ZMConversation.insertNewObject(in: moc)

            // when
            conversation.team = .insertNewObject(in: moc)
            conversation.team?.remoteIdentifier = .init()

            // then
            XCTAssert(conversation.hasTeam)
            XCTAssertEqual(AssetRequestFactory.Retention(conversation: conversation), .eternalInfrequentAccess)
        }

        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.2))
    }

    func testThatItReturnsEternalInfrequentAccessForAConversationWithAParticipantsWithTeam() {

        // given
        let user = ZMUser.insertNewObject(in: coreDataStack.viewContext)
        user.remoteIdentifier = UUID()
        user.teamIdentifier = .init()

        // when
        guard let conversation = ZMConversation.insertGroupConversation(session: self.coreDataStack, participants: [user]) else { return XCTFail("no conversation") }

        // then
        XCTAssert(conversation.containsTeamUser)
        XCTAssertEqual(AssetRequestFactory.Retention(conversation: conversation), .eternalInfrequentAccess)
    }

    func testThatUpstreamRequestForAssetReturnsRequestWithExpectedV3Path_whenFederationIsNotEnabled() {
        // given
        let domain = UUID().uuidString
        let expectedPath = "/assets/v3"

        // when
        sut.useFederationEndpoint = false
        let request = sut.upstreamRequestForAsset(withData: Data(), retention: .eternal, domain: domain)

        // then
        XCTAssertEqual(request?.path, expectedPath)
    }

    func testThatUpstreamRequestForAssetReturnsNil_whenFederationIsEnabled_whenDomainIsMissing() {
        // when
        sut.useFederationEndpoint = true
        let request = sut.upstreamRequestForAsset(withData: Data(), retention: .eternal, domain: nil)

        // then
        XCTAssertNil(request)
    }
    
    func testThatUpstreamRequestForAssetReturnsRequesstWithExpectedV4Path_whenFederationIsEnabled_whenDomainIsAvailable() {
        // given
        let domain = UUID().uuidString
        let expectedPath = "/assets/v4/\(domain)"
        
        // when
        sut.useFederationEndpoint = true
        let request = sut.upstreamRequestForAsset(withData: Data(), retention: .eternal, domain: domain)
        
        // then
        XCTAssertEqual(request?.path, expectedPath)
    }
    
    func testThatBackgroundUpstreamRequestForAssetReturnsRequestWithExpectedV3Path_whenFederationIsNotEnabled() {
        let syncContext = coreDataStack.syncContext
        syncContext.performGroupedBlock {
            // given
            let domain = UUID().uuidString
            
            let conversation = ZMConversation.insertNewObject(in: syncContext)
            conversation.remoteIdentifier = UUID()
            conversation.domain = domain
            
            let user = ZMUser.insertNewObject(in: syncContext)
            user.remoteIdentifier = UUID()
            
            let message = ZMAssetClientMessage(nonce: UUID(), managedObjectContext: syncContext)
            message.visibleInConversation = conversation
            message.sender = user
            
            self.coreDataStack.syncContext.zm_fileAssetCache = FileAssetCache(location: nil)
            
            let expectedPath = "/assets/v3"
            
            // when
            self.sut.useFederationEndpoint = false
            let request = self.sut.backgroundUpstreamRequestForAsset(message: message, withData: Data(), retention: .eternal)
            
            // then
            XCTAssertEqual(request?.path, expectedPath)
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.2))
    }
    
    func testThatBackgroundUpstreamRequestForAssetReturnsNil_whenFederationIsEnabled_whenDomainIsMissing() {
        let syncContext = coreDataStack.syncContext
        syncContext.performGroupedBlock {
            // given
            let domain = UUID().uuidString
            
            let conversation = ZMConversation.insertNewObject(in: syncContext)
            conversation.remoteIdentifier = nil
            conversation.domain = domain
            
            let user = ZMUser.insertNewObject(in: syncContext)
            user.remoteIdentifier = UUID()
            
            let message = ZMAssetClientMessage(nonce: UUID(), managedObjectContext: syncContext)
            message.visibleInConversation = conversation
            message.sender = user
            
            self.coreDataStack.syncContext.zm_fileAssetCache = FileAssetCache(location: nil)
            
            // when
            self.sut.useFederationEndpoint = true
            let request = self.sut.backgroundUpstreamRequestForAsset(message: message, withData: Data(), retention: .eternal)
            
            // then
            XCTAssertNil(request)
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.2))
    }
    
    func testThatBackgroundUpstreamRequestForAssetReturnsRequesstWithExpectedV4Path_whenFederationIsEnabled_whenDomainIsAvailable() {
        let syncContext = coreDataStack.syncContext
        syncContext.performGroupedBlock {
            // given
            let domain = UUID().uuidString
            
            let conversation = ZMConversation.insertNewObject(in: syncContext)
            conversation.remoteIdentifier = UUID()

            ZMUser.selfUser(in: syncContext).domain = domain
            
            let user = ZMUser.insertNewObject(in: syncContext)
            user.remoteIdentifier = UUID()
            
            let message = ZMAssetClientMessage(nonce: UUID(), managedObjectContext: syncContext)
            message.visibleInConversation = conversation
            message.sender = user
            
            self.coreDataStack.syncContext.zm_fileAssetCache = FileAssetCache(location: nil)
            
            let expectedPath = "/assets/v4/\(ZMUser.selfUser(in: syncContext).domain!)"
            
            // when
            self.sut.useFederationEndpoint = true
            let request = self.sut.backgroundUpstreamRequestForAsset(message: message, withData: Data(), retention: .eternal)
            
            // then
            XCTAssertEqual(request?.path, expectedPath)
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.2))
    }
}
