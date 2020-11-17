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
import WireRequestStrategy

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
    
    func testThatItSavesAllFeatures() {
        // Given
        let json: [String : Any] = ["applock": [
            "status": "disabled",
            "config": [
            "enforce_app_lock": true,
            "inactivity_timeout_secs": 30
            ]
            ]
            ]
        
        let data = try? JSONSerialization.data(withJSONObject: json, options: JSONSerialization.WritingOptions.prettyPrinted)
        
        // When
        sut.saveAllFeatures(data!)
       
        // Then
        let featureStatus = sut.status(for: FeatureModel.AppLock.self)
        XCTAssertEqual(featureStatus, false)
    }
    
    func testThatItSavesSingleFeature() {
        // Given
        let json: [String : Any] = [
            "status": "enabled",
            "config": [
                "enforce_app_lock": true,
                "inactivity_timeout_secs": 30
            ]
        ]
        
        let data = try? JSONSerialization.data(withJSONObject: json, options: JSONSerialization.WritingOptions.prettyPrinted)
        
        // When
        sut.save(FeatureModel.AppLock.self, data: data!)
        
        // Then
        let featureStatus = sut.status(for: FeatureModel.AppLock.self)
        XCTAssertEqual(featureStatus, true)
        
    }
}
