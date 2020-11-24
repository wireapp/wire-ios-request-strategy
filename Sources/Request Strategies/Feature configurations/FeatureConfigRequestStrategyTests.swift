//
// Wire
// Copyright (C) 2020 Wire Swiss GmbH
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

class FeatureConfigRequestStrategyTests: MessagingTestBase {
    var mockApplicationStatus: MockApplicationStatus!
    var sut: FeatureConfigRequestStrategy!
    
    override func setUp() {
        super.setUp()
        mockApplicationStatus = MockApplicationStatus()
        mockApplicationStatus.mockSynchronizationState = .slowSyncing
        
        RequestAvailableNotification.notifyNewRequestsAvailable(self)
        sut = FeatureConfigRequestStrategy(withManagedObjectContext: syncMOC,
                                           applicationStatus: mockApplicationStatus)
    }
    
    override func tearDown() {
        mockApplicationStatus = nil
        sut = nil
        super.tearDown()
    }

    @discardableResult
    func createTeam(for user: ZMUser) -> Team {
        let context = user.managedObjectContext!

        let team = Team.insertNewObject(in: context)
        team.name = "Wire Amazing Team"
        team.remoteIdentifier = .create()

        let membership = Member.insertNewObject(in: context)
        membership.team = team
        membership.user = user

        return team
    }
    
    // MARK: Request generation
    func testThatItGeneratesARequestToFetchAllFeatureConfigurations() {
        self.syncMOC.performGroupedAndWait { (moc: NSManagedObjectContext) -> Void in
            // given
            let teamId = self.createTeam(for: .selfUser(in: moc)).remoteIdentifier!

            NotificationInContext(name: FeatureConfigRequestStrategy.needsToFetchFeatureConfigNotificationName,
                                  context: moc.notificationContext,
                                  object: nil).post()
            
            // when
            guard let request = self.sut.nextRequestIfAllowed() else { return XCTFail() }
            
            // then
            XCTAssertEqual(request.path, "/teams/\(teamId)/features")
        }
    }
    
    func testThatItGeneratesARequestToFetchASingleFeatureConfiguration() {
        self.syncMOC.performGroupedAndWait { (moc: NSManagedObjectContext) -> Void in
            // given
            let teamId = self.createTeam(for: .selfUser(in: moc)).remoteIdentifier!

            NotificationInContext(name: FeatureConfigRequestStrategy.needsToFetchFeatureConfigNotificationName,
                                  context: moc.notificationContext,
                                  object: "applock" as AnyObject).post()
            
            // when
            guard let request = self.sut.nextRequestIfAllowed() else { return XCTFail() }
            
            // then
            XCTAssertEqual(request.path, "/teams/\(teamId)/features/applock")
        }
    }
    
    func testThatItDoesNotGenerateARequestForNonTeamUser() {
        self.syncMOC.performGroupedAndWait { moc in
            // given
            XCTAssertNil(ZMUser.selfUser(in: moc).team)

            NotificationInContext(name: FeatureConfigRequestStrategy.needsToFetchFeatureConfigNotificationName,
                                  context: moc.notificationContext,
                                  object: nil).post()

            // when
            let request = self.sut.nextRequestIfAllowed()
            
            // then
            XCTAssertNil(request)
        }
    }
    
    func testThatItDoesNotGenerateARequestIfThereAreNoPendingItems() {
        self.syncMOC.performGroupedAndWait { moc in
            // given
            self.createTeam(for: .selfUser(in: moc))

            // when
            let request = self.sut.nextRequestIfAllowed()
            
            // then
            XCTAssertNil(request)
        }
    }
    
    func testThatItConsumesPendingItems() {
        self.syncMOC.performGroupedAndWait { moc in
            // given
            self.createTeam(for: .selfUser(in: moc))
            
            NotificationInContext(name: FeatureConfigRequestStrategy.needsToFetchFeatureConfigNotificationName,
                                  context: moc.notificationContext,
                                  object: nil).post()
            
            // when
            let firstRequest = self.sut.nextRequestIfAllowed()
            XCTAssertNotNil(firstRequest)
            let secondRequest = self.sut.nextRequestIfAllowed()
            
            // then
            XCTAssertNil(secondRequest)
        }
    }
}
