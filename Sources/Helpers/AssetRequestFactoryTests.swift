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

    func testThatUpstreamRequestForAssetReturnsRequestWithExpectedPathAndWithoutDomainInJSON_whenFederationIsNotEnabled() {
        // given
        let expectedPath = "/assets/v3"
        let domain = UUID().uuidString

        // when
        sut.useFederationEndpoint = false
        let request = sut.upstreamRequestForAsset(withData: Data(), retention: .eternal, domain: domain)

        // then
        guard let json = json(from: request?.multipartBodyItems()) else {
            XCTFail("No JSON found in request")
            return
        }

        XCTAssertEqual(request?.path, expectedPath)
        XCTAssertFalse(json.keys.contains("domain"))
    }

    func testThatUpstreamRequestForAssetReturnsRequestWithExpectedPathAndWithoutDomain_whenFederationIsEnabled_whenDomainIsMissing() {
        // given
        let expectedPath = "/assets/v3"

        // when
        sut.useFederationEndpoint = true
        let request = sut.upstreamRequestForAsset(withData: Data(), retention: .eternal, domain: nil)

        // then
        XCTAssertEqual(request?.path, expectedPath)
    }

    func testThatUpstreamRequestForAssetReturnsRequestWithDomainInJSONAndExpectedPath_whenFederationIsEnabled_whenDomainIsAvailable() {
        // given
        let expectedPath = "/assets/v3"
        let domain = UUID().uuidString

        // when
        sut.useFederationEndpoint = true
        let request = sut.upstreamRequestForAsset(withData: Data(), retention: .eternal, domain: domain)

        // then
        guard let json = json(from: request?.multipartBodyItems()) else {
            XCTFail("No JSON found in request")
            return
        }

        XCTAssertEqual(request?.path, expectedPath)
        XCTAssertEqual(json["domain"] as! String, domain)
    }

    func testThatBackgroundUpstreamRequestForAssetReturnsRequestWithExpectedPath() {
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
            let request = self.sut.backgroundUpstreamRequestForAsset(message: message, withData: Data(), retention: .eternal, domain: domain)

            // then
            XCTAssertEqual(request?.path, expectedPath)
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.2))
    }

    func testThatDataForMultipartAssetUploadRequestReturnsExpectedDataWithDomainInJSON_whenFederationIsEnabled_whenDomainIsAvailable() {
        // given
        let domain = UUID().uuidString

        // when
        sut.useFederationEndpoint = true
        let data = try! sut.dataForMultipartAssetUploadRequest(Data(), shareable: true, retention: .eternal, domain: domain)

        // then
        let multipart = (data as NSData).multipartDataItemsSeparated(withBoundary: "frontier")

        guard let json = json(from: multipart) else {
            XCTFail("No JSON data")
            return
        }

        XCTAssertEqual(json["domain"] as! String, domain)
    }

    func testThatDataForMultipartAssetUploadRequestReturnsExpectedDataWithoutDomainInJSON_whenFederationIsEnabled_whenDomainIsNotAvailable() {
        // when
        sut.useFederationEndpoint = true
        let data = try! sut.dataForMultipartAssetUploadRequest(Data(), shareable: true, retention: .eternal, domain: nil)

        // then
        let multipart = (data as NSData).multipartDataItemsSeparated(withBoundary: "frontier")

        guard let json = json(from: multipart) else {
            XCTFail("No JSON data")
            return
        }

        XCTAssertFalse(json.keys.contains("domain"))
    }

    func testThatDataForMultipartAssetUploadRequestReturnsExpectedDataWithoutDomainInJSON_whenFederationIsNotEnabled() {
        // when
        sut.useFederationEndpoint = false
        let data = try! sut.dataForMultipartAssetUploadRequest(Data(), shareable: true, retention: .eternal, domain: nil)

        // then
        let multipart = (data as NSData).multipartDataItemsSeparated(withBoundary: "frontier")

        guard let json = json(from: multipart) else {
            XCTFail("No JSON data")
            return
        }

        XCTAssertFalse(json.keys.contains("domain"))
    }

}

private extension AssetRequestFactoryTests {
    func json(from multipart: [Any]?) -> [String: Any]? {
        guard
            let jsonData = (multipart as? [ZMMultipartBodyItem])?.filter({ $0.contentType == "application/json"}).first?.data,
            let json = (try? JSONSerialization.jsonObject(with: jsonData, options: .fragmentsAllowed)) as? [String: Any]
        else {
            return nil
        }

        return json
    }
}
