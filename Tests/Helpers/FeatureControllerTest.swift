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
    
    let json = """
    {
     "status": "enabled",
         "config": {
            "enforceAppLock": true,
            "inactivityTimeoutSecs": 30
         }
    }
    """
    
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
        let json = """
        {
          "applock": {
              "status": "disabled",
               "config": {
                "enforceAppLock": true,
                "inactivityTimeoutSecs": 30
               }
            }
        }
        """
        let data = json.data(using: .utf8)!
        let allConfigs = try! JSONDecoder().decode(AllFeatureConfigsResponse.self, from: data)
        
        // When
        sut.saveAllFeatures(allConfigs)
       
        // Then
        let fechedFeature = Feature.fetch("applock", context: self.uiMOC)
        XCTAssertNotNil(fechedFeature)
        XCTAssertEqual(fechedFeature?.name, "applock")
        XCTAssertEqual(fechedFeature?.status, .disabled)
    }
    
    func testThatItSavesSingleFeature() {
        // Given
        let data = json.data(using: .utf8)!
        let configuration = try! JSONDecoder().decode(FeatureConfigResponse<Feature.AppLock>.self, from: data)
        
        // When
        sut.save(Feature.AppLock.self, configuration: configuration)
        
        // Then
        let fechedFeature = Feature.fetch("applock", context: self.uiMOC)
        XCTAssertNotNil(fechedFeature)
        XCTAssertEqual(fechedFeature?.name, "applock")
        XCTAssertEqual(fechedFeature?.status, .enabled)
    }
    
    func testThatItFetchesAFeatureStatus() {
        // Given
        let data = json.data(using: .utf8)!
        let configuration = try! JSONDecoder().decode(FeatureConfigResponse<Feature.AppLock>.self, from: data)
        sut.save(Feature.AppLock.self, configuration: configuration)
        
        // When
        let featureStatus = FeatureController.status(for: Feature.AppLock.self, managedObjectContext: self.uiMOC)
        
        // Then
        XCTAssertEqual(featureStatus, .enabled)
    }
    
    func testThatItFetchesAFeatureConfig() {
        // Given
        let data = json.data(using: .utf8)!
        let configuration = try! JSONDecoder().decode(FeatureConfigResponse<Feature.AppLock>.self, from: data)
        sut.save(Feature.AppLock.self, configuration: configuration)
        
        // When
        let featureConfig = FeatureController.configuration(for: Feature.AppLock.self, managedObjectContext: self.uiMOC)
        
        // Then
        XCTAssertEqual(featureConfig?.enforceAppLock, true)
        XCTAssertEqual(featureConfig?.inactivityTimeoutSecs, 30)
    }
}
