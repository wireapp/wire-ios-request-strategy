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

import XCTest
import WireTesting
@testable import WireRequestStrategy

class MockModifiedKeyObjectSyncTranscoder: ModifiedKeyObjectSyncTranscoder {

    typealias Object = MockEntity

    var objectsAskedToBeSynchronized: [MockEntity] = []
    var pendingModifications: [() -> Void] = []

    func completePendingModifiations() {
        pendingModifications.forEach({ $0() })
        pendingModifications.removeAll()
    }

    func synchronize(key: String, for object: MockEntity, completion: @escaping () -> Void) {
        objectsAskedToBeSynchronized.append(object)
        pendingModifications.append(completion)
    }

}

class ModifiedKeyObjectSyncTests: ZMTBaseTest {

    var moc: NSManagedObjectContext!
    var transcoder: MockModifiedKeyObjectSyncTranscoder!
    var sut: ModifiedKeyObjectSync<MockModifiedKeyObjectSyncTranscoder>!

    // MARK: - Life Cycle

    override func setUp() {
        super.setUp()

        moc = MockModelObjectContextFactory.testContext()
        transcoder = MockModifiedKeyObjectSyncTranscoder()
        sut = ModifiedKeyObjectSync(entity: MockEntity.entity(),
                                    trackedKey: "field",
                                    modifiedPredicate: NSPredicate(format: "field2 != \"not allowed\""))
        sut.transcoder = transcoder
    }

    override func tearDown() {
        transcoder = nil
        sut = nil

        super.tearDown()
    }

    // MARK: - Tests

    func testThatItReturnsExpectedFetchRequest() {
        // when
        let fetchRequest = sut.fetchRequestForTrackedObjects()

        // then
        XCTAssertEqual(fetchRequest, MockEntity.sortedFetchRequest())
    }

    func testThatItAsksToSynchronizeObject_WhenTrackedFieldHasBeenModified() {
        // given
        let mockEntity = MockEntity.insertNewObject(in: moc)
        mockEntity.field = 1
        moc.saveOrRollback()

        // when
        sut.objectsDidChange(Set(arrayLiteral: mockEntity))

        // then
        XCTAssertTrue(transcoder.objectsAskedToBeSynchronized.contains(mockEntity))
    }

    func testThatItDoesNotAskToSynchronizeObject_WhenTrackedFieldHasNotBeenModified() {
        // given
        let mockEntity = MockEntity.insertNewObject(in: moc)
        mockEntity.field2 = "Hello world"
        moc.saveOrRollback()

        // when
        sut.objectsDidChange(Set(arrayLiteral: mockEntity))

        // then
        XCTAssertTrue(transcoder.objectsAskedToBeSynchronized.isEmpty)
    }

    func testThatItDoesNotAskToSynchronizeObject_WhenSynchronizationIsInProgress() {
        // given
        let mockEntity = MockEntity.insertNewObject(in: moc)
        mockEntity.field = 1
        moc.saveOrRollback()
        sut.objectsDidChange(Set(arrayLiteral: mockEntity))
        transcoder.objectsAskedToBeSynchronized.removeAll()

        // when
        sut.objectsDidChange(Set(arrayLiteral: mockEntity))

        // then
        XCTAssertTrue(transcoder.objectsAskedToBeSynchronized.isEmpty)
    }

    func testItDoesNotAskToSynchronizeObject_WhenModifiedPredicateEvaluatesToFalse() {
        // given
        let mockEntity = MockEntity.insertNewObject(in: moc)
        mockEntity.field = 1
        mockEntity.field2 = "not allowed"
        moc.saveOrRollback()

        // when
        sut.objectsDidChange(Set(arrayLiteral: mockEntity))

        // then
        XCTAssertTrue(transcoder.objectsAskedToBeSynchronized.isEmpty)
    }

    func testThatAsksToSynchronizeObject_WhenTrackedFieldHasBeenModifiedAgain() {
        // given
        let mockEntity = MockEntity.insertNewObject(in: moc)
        mockEntity.field = 1
        moc.saveOrRollback()
        sut.objectsDidChange(Set(arrayLiteral: mockEntity))
        transcoder.completePendingModifiations()
        transcoder.objectsAskedToBeSynchronized.removeAll()

        // when
        mockEntity.field = 2
        moc.saveOrRollback()
        sut.objectsDidChange(Set(arrayLiteral: mockEntity))

        // then
        XCTAssertTrue(transcoder.objectsAskedToBeSynchronized.contains(mockEntity))
    }

}
