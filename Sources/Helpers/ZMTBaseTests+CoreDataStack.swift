//
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

import Foundation
import WireTesting

extension ZMTBaseTest {

    @objc
    func createCoreDataStack() -> CoreDataStack {
        let account = Account(userName: "", userIdentifier: UUID())
        let storageDirectory = FileManager.default.urls(for: .documentDirectory,
                                                        in: .userDomainMask).first!
        let stack = CoreDataStack(account: account,
                                  applicationContainer: storageDirectory,
                                  inMemoryStore: true,
                                  dispatchGroup: dispatchGroup)

        stack.loadStore { (error) in
            XCTAssertNil(error)
        }

        return stack
    }

    @objc
    func setupCaches(in coreDataStack: CoreDataStack) {
        let userImageCache = UserImageLocalCache()
        let fileAssetCache = FileAssetCache()

        coreDataStack.viewContext.zm_userImageCache = userImageCache
        coreDataStack.viewContext.zm_fileAssetCache = fileAssetCache

        coreDataStack.syncContext.performGroupedBlockAndWait {
            coreDataStack.syncContext.zm_userImageCache = userImageCache
            coreDataStack.syncContext.zm_fileAssetCache = fileAssetCache
        }
    }

}
