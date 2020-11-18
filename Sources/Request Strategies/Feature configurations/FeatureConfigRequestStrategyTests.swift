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
    let teamId = UUID()
    
    override func setUp() {
        super.setUp()
        mockApplicationStatus = MockApplicationStatus()
        mockApplicationStatus.mockSynchronizationState = .online
        
        sut = FeatureConfigRequestStrategy(withManagedObjectContext: syncMOC,
                                           applicationStatus: mockApplicationStatus)
        syncMOC.performGroupedBlockAndWait {
            let selfUser = ZMUser.selfUser(in: self.syncMOC)
            selfUser.teamIdentifier = self.teamId
        }
    }
    
    override func tearDown() {
        mockApplicationStatus = nil
        sut = nil
        super.tearDown()
    }
    
    // MARK: Request generation
    
    func testThatItGeneratesARequestToFetchAllFeatureConfigurations() throws {
//        self.syncMOC.performGroupedAndWait { moc in
            // given
//            let teamId = UUID()
//            let selfUser = ZMUser.selfUser(in: moc)
//            selfUser.teamIdentifier = teamId
            
//            // when
//            guard let request = self.sut.nextRequest() else { XCTFail(); return }
//
//            // then
//            XCTAssertEqual(request.path, "/teams/\(self.teamId)/features")
//            XCTAssertEqual(request.method, .methodGET)
            let request = try XCTUnwrap(self.sut.nextRequest())
            XCTAssertEqual(request.path, "/teams/\(self.teamId)/features")
//        }
    }
    
    func testThatItGeneratesARequestToFetchASingleFeatureConfiguration() {
        
    }
}
