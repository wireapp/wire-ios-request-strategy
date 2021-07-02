//
//  InsertedObjectSyncTests.swift
//  WireRequestStrategyTests
//
//  Created by Jacob Persson on 29.06.21.
//  Copyright © 2021 Wire GmbH. All rights reserved.
//

import XCTest
import WireTesting
@testable import WireRequestStrategy

class MockInsertedObjectSyncTranscoder: InsertedObjectSyncTranscoder {

    typealias Object = MockEntity

    var objectsAskedToBeInserted: [MockEntity] = []
    var pendingInsertions: [() -> Void] = []

    func completePendingInsertions() {
        pendingInsertions.forEach({ $0() })
        pendingInsertions.removeAll()
    }

    func insert(object: MockEntity, completion: @escaping () -> Void) {
        objectsAskedToBeInserted.append(object)
        pendingInsertions.append(completion)
    }

}

class InsertedObjectSyncTests: ZMTBaseTest {

    var moc: NSManagedObjectContext!
    var transcoder: MockInsertedObjectSyncTranscoder!
    var sut: InsertedObjectSync<MockInsertedObjectSyncTranscoder>!

    // MARK: - Life Cycle

    override func setUp() {
        super.setUp()

        moc = MockModelObjectContextFactory.testContext()
        transcoder = MockInsertedObjectSyncTranscoder()
        sut = InsertedObjectSync(entity: MockEntity.entity())
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
        XCTAssertEqual(fetchRequest?.predicate, MockEntity.predicateForObjectsThatNeedToBeInsertedUpstream())
    }

    func testThatItAsksToInsertObject_WhenAddingTrackedObjects() {
        // given
        let mockEntity = MockEntity.insertNewObject(in: moc)

        // when
        mockEntity.remoteIdentifier = nil
        sut.addTrackedObjects(Set(arrayLiteral: mockEntity))

        // then
        XCTAssertTrue(transcoder.objectsAskedToBeInserted.contains(mockEntity))
    }

    func testThatItAsksToInsertObject_WhenInsertPredicateEvalutesToTrue() {
        // given
        let mockEntity = MockEntity.insertNewObject(in: moc)

        // when
        mockEntity.remoteIdentifier = nil
        sut.objectsDidChange(Set(arrayLiteral: mockEntity))

        // then
        XCTAssertTrue(transcoder.objectsAskedToBeInserted.contains(mockEntity))
    }

    func testThatItAsksToInsertObject_WhenInsertPredicateEvaluatesToTrueAfterBeingFalse() {
        // given
        let mockEntity = MockEntity.insertNewObject(in: moc)
        mockEntity.remoteIdentifier = nil
        sut.objectsDidChange(Set(arrayLiteral: mockEntity))
        mockEntity.remoteIdentifier = UUID()
        sut.objectsDidChange(Set(arrayLiteral: mockEntity))

        // when
        mockEntity.remoteIdentifier = nil
        sut.objectsDidChange(Set(arrayLiteral: mockEntity))

        // then
        XCTAssertEqual(transcoder.objectsAskedToBeInserted, [mockEntity, mockEntity])
    }

    func testItDoesNotAskToInsertObject_WhenInsertPredicateEvaluatesToFalse() {
        // given
        let mockEntity = MockEntity.insertNewObject(in: moc)

        // when
        mockEntity.remoteIdentifier = UUID()
        sut.objectsDidChange(Set(arrayLiteral: mockEntity))

        // then
        XCTAssertTrue(transcoder.objectsAskedToBeInserted.isEmpty)
    }

    func testItDoesNotAskToInsertObject_WhenInsertionIsPending() {
        // given
        let mockEntity = MockEntity.insertNewObject(in: moc)
        mockEntity.remoteIdentifier = nil
        sut.objectsDidChange(Set(arrayLiteral: mockEntity))
        transcoder.objectsAskedToBeInserted.removeAll()

        // when
        sut.objectsDidChange(Set(arrayLiteral: mockEntity))

        // then
        XCTAssertTrue(transcoder.objectsAskedToBeInserted.isEmpty)
    }

}
