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

class UserProfilePayloadTests: MessagingTestBase {

    override func setUp() {
        super.setUp()

        syncMOC.performGroupedBlockAndWait {
            self.otherUser.remoteIdentifier = nil
            self.otherUser.domain = nil
        }
    }

    func testUpdateUserProfile_ID() throws {
        syncMOC.performGroupedBlockAndWait {
            // given
            let userProfile = Payload.UserProfile(id: UUID())

            // when
            userProfile.updateUserProfile(for: self.otherUser, authoritative: true)

            // then
            XCTAssertEqual(self.otherUser.remoteIdentifier, userProfile.id)
        }
    }

    func testUpdateUserProfile_QualifiedUserID() throws {
        syncMOC.performGroupedBlockAndWait {
            // given
            let qualifiedID = Payload.QualifiedUserID(uuid: UUID(), domain: "example.com")
            let userProfile = Payload.UserProfile(qualifiedID: qualifiedID)

            // when
            userProfile.updateUserProfile(for: self.otherUser, authoritative: true)

            // then
            XCTAssertEqual(self.otherUser.remoteIdentifier, qualifiedID.uuid)
            XCTAssertEqual(self.otherUser.domain, qualifiedID.domain)
        }
    }

    func testUpdateUserProfile_TeamID() throws {
        syncMOC.performGroupedBlockAndWait {
            // given
            let qualifiedID = Payload.QualifiedUserID(uuid: UUID(), domain: "example.com")
            let userProfile = Payload.UserProfile(qualifiedID: qualifiedID, teamID: UUID())

            // when
            userProfile.updateUserProfile(for: self.otherUser, authoritative: true)

            // then
            XCTAssertEqual(self.otherUser.teamIdentifier, userProfile.teamID)
        }
    }

    func testUpdateUserProfile_ServiceID() throws {
        syncMOC.performGroupedBlockAndWait {
            // given
            let qualifiedID = Payload.QualifiedUserID(uuid: UUID(), domain: "example.com")
            let serviceID = Payload.ServiceID(id: UUID(), provider: UUID())
            let userProfile = Payload.UserProfile(qualifiedID: qualifiedID, serviceID: serviceID)

            // when
            userProfile.updateUserProfile(for: self.otherUser, authoritative: true)

            // then
            XCTAssertEqual(self.otherUser.serviceIdentifier, serviceID.id.transportString())
            XCTAssertEqual(self.otherUser.providerIdentifier, serviceID.provider.transportString())
        }
    }

    func testUpdateUserProfile_SSOID() throws {
        syncMOC.performGroupedBlockAndWait {
            // given
            let qualifiedID = Payload.QualifiedUserID(uuid: UUID(), domain: "example.com")
            let SSOID = Payload.SSOID(tenant: "a", subject: "b", scimExternalID: "c")
            let userProfile = Payload.UserProfile(qualifiedID: qualifiedID, SSOID: SSOID)

            // when
            userProfile.updateUserProfile(for: self.otherUser, authoritative: true)

            // then
            XCTAssertTrue(self.otherUser.usesCompanyLogin)
        }
    }

    func testUpdateUserProfile_Name() throws {
        syncMOC.performGroupedBlockAndWait {
            // given
            let qualifiedID = Payload.QualifiedUserID(uuid: UUID(), domain: "example.com")
            let name = "John Doe"
            let userProfile = Payload.UserProfile(qualifiedID: qualifiedID, name: name)

            // when
            userProfile.updateUserProfile(for: self.otherUser, authoritative: true)

            // then
            XCTAssertEqual(self.otherUser.name, name)
        }
    }

    func testUpdateUserProfile_Handle() throws {
        syncMOC.performGroupedBlockAndWait {
            // given
            let qualifiedID = Payload.QualifiedUserID(uuid: UUID(), domain: "example.com")
            let handle = "johndoe"
            let userProfile = Payload.UserProfile(qualifiedID: qualifiedID, handle: handle)

            // when
            userProfile.updateUserProfile(for: self.otherUser, authoritative: true)

            // then
            XCTAssertEqual(self.otherUser.handle, handle)
        }
    }

    func testUpdateUserProfile_Phone() throws {
        syncMOC.performGroupedBlockAndWait {
            // given
            let qualifiedID = Payload.QualifiedUserID(uuid: UUID(), domain: "example.com")
            let phone = "+123456789"
            let userProfile = Payload.UserProfile(qualifiedID: qualifiedID, phone: phone)

            // when
            userProfile.updateUserProfile(for: self.otherUser, authoritative: true)

            // then
            XCTAssertEqual(self.otherUser.phoneNumber, phone)
        }
    }

    func testUpdateUserProfile_Email() throws {
        syncMOC.performGroupedBlockAndWait {
            // given
            let qualifiedID = Payload.QualifiedUserID(uuid: UUID(), domain: "example.com")
            let email = "john.doe@example.com"
            let userProfile = Payload.UserProfile(qualifiedID: qualifiedID, email: email)

            // when
            userProfile.updateUserProfile(for: self.otherUser, authoritative: true)

            // then
            XCTAssertEqual(self.otherUser.emailAddress, email)
        }
    }

    func testUpdateUserProfile_Assets() throws {
        syncMOC.performGroupedBlockAndWait {
            // given
            let qualifiedID = Payload.QualifiedUserID(uuid: UUID(), domain: "example.com")
            let previewAsset = Payload.Asset(key: "1", size: .preview, type: .image)
            let completeAsset = Payload.Asset(key: "2", size: .complete, type: .image)
            let assets = [previewAsset, completeAsset]
            let userProfile = Payload.UserProfile(qualifiedID: qualifiedID, assets: assets)


            // when
            userProfile.updateUserProfile(for: self.otherUser, authoritative: true)

            // then
            XCTAssertEqual(self.otherUser.previewProfileAssetIdentifier, previewAsset.key)
            XCTAssertEqual(self.otherUser.completeProfileAssetIdentifier, completeAsset.key)
        }
    }

    func testUpdateUserProfile_ManagedBy() throws {
        syncMOC.performGroupedBlockAndWait {
            // given
            let qualifiedID = Payload.QualifiedUserID(uuid: UUID(), domain: "example.com")
            let managedBy = "wire"
            let userProfile = Payload.UserProfile(qualifiedID: qualifiedID, managedBy: managedBy)

            // when
            userProfile.updateUserProfile(for: self.otherUser, authoritative: true)

            // then
            XCTAssertTrue(self.otherUser.managedByWire)
        }
    }

    func testUpdateUserProfile_AccentColor() throws {
        syncMOC.performGroupedBlockAndWait {
            // given
            let qualifiedID = Payload.QualifiedUserID(uuid: UUID(), domain: "example.com")
            let accentColor = ZMAccentColor(rawValue: 3)
            let userProfile = Payload.UserProfile(qualifiedID: qualifiedID, accentColor: Int(accentColor!.rawValue))

            // when
            userProfile.updateUserProfile(for: self.otherUser, authoritative: true)

            // then
            XCTAssertEqual(self.otherUser.accentColorValue, accentColor)
        }
    }

    func testUpdateUserProfile_IsDeleted() throws {
        syncMOC.performGroupedBlockAndWait {
            // given
            let qualifiedID = Payload.QualifiedUserID(uuid: UUID(), domain: "example.com")
            let userProfile = Payload.UserProfile(qualifiedID: qualifiedID, isDeleted: true)

            // when
            userProfile.updateUserProfile(for: self.otherUser, authoritative: true)

            // then
            XCTAssertTrue(self.otherUser.isAccountDeleted)
        }
    }

    func testUpdateUserProfile_ExpiresAt() throws {
        syncMOC.performGroupedBlockAndWait {
            // given
            let qualifiedID = Payload.QualifiedUserID(uuid: UUID(), domain: "example.com")
            let expiresAt = Date()
            let userProfile = Payload.UserProfile(qualifiedID: qualifiedID, expiresAt: expiresAt)

            // when
            userProfile.updateUserProfile(for: self.otherUser, authoritative: true)

            // then
            XCTAssertEqual(self.otherUser.expiresAt, expiresAt)
        }
    }

}
