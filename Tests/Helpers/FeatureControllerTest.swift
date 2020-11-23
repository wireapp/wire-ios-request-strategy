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

import Foundation
import XCTest
import WireTesting
@testable import WireRequestStrategy

class FeatureControllerTest: MessagingTestBase {

    var sut: FeatureController!

    override func setUp() {
        super.setUp()
        sut = FeatureController(managedObjectContext: self.uiMOC)
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    func testThatItSavesSingleFeature() {
        // Given
        let feature = Feature.AppLock(
            status: .enabled,
            config: .init(enforceAppLock: true, inactivityTimeoutSecs: 10)
        )

        // When
        sut.store(feature: feature)
        
        // Then
        let fechedFeature = Feature.fetch(name: .appLock, context: self.uiMOC)
        XCTAssertNotNil(fechedFeature)
        XCTAssertEqual(fechedFeature?.name, .appLock)
        XCTAssertEqual(fechedFeature?.status, .enabled)
    }

}
