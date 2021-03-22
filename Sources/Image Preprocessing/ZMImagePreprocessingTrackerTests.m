// 
// Wire
// Copyright (C) 2016 Wire Swiss GmbH
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


@import WireImages;
@import WireDataModel;
@import WireTesting;

#import <WireRequestStrategy/ZMImagePreprocessingTracker+Testing.h>
#import "WireRequestStrategyTests-Swift.h"


@interface ZMImagePreprocessingTrackerTests : ZMTBaseTest

@property (nonatomic) id preprocessor;
@property (nonatomic) CoreDataStack *coreDataStack;
@property (nonatomic) NSOperationQueue *imagePreprocessingQueue;
@property (nonatomic) ZMImagePreprocessingTracker *sut;
@property (nonatomic) NSPredicate *fetchPredicate;
@property (nonatomic) NSPredicate *needsProcessingPredicate;

@property (nonatomic)  ZMClientMessage *linkPreviewMessage1;
@property (nonatomic)  ZMClientMessage *linkPreviewMessage2;
@property (nonatomic)  ZMClientMessage *linkPreviewMessage3;
@property (nonatomic)  ZMClientMessage *linkPreviewMessageExcludedByPredicate;

@end



@implementation ZMImagePreprocessingTrackerTests

- (void)setUp {
    [super setUp];

    self.coreDataStack = [self createCoreDataStack];
    [self setupCachesIn:self.coreDataStack];
    
    self.linkPreviewMessage1 = [[ZMClientMessage alloc] initWithNonce:NSUUID.createUUID managedObjectContext:self.coreDataStack.viewContext];
    self.linkPreviewMessage2 = [[ZMClientMessage alloc] initWithNonce:NSUUID.createUUID managedObjectContext:self.coreDataStack.viewContext];
    self.linkPreviewMessage3 = [[ZMClientMessage alloc] initWithNonce:NSUUID.createUUID managedObjectContext:self.coreDataStack.viewContext];
    self.linkPreviewMessageExcludedByPredicate = [[ZMClientMessage alloc] initWithNonce:NSUUID.createUUID managedObjectContext:self.coreDataStack.viewContext];
    self.linkPreviewMessageExcludedByPredicate.nonce = nil;
    
    self.fetchPredicate = [NSPredicate predicateWithValue:NO];
    self.needsProcessingPredicate = [NSPredicate predicateWithFormat:@"nonce_data != nil"];
    self.preprocessor = [OCMockObject niceMockForClass:[ZMAssetsPreprocessor class]];
    self.imagePreprocessingQueue = [[NSOperationQueue alloc] init];
    self.sut = [[ZMImagePreprocessingTracker alloc] initWithManagedObjectContext:self.coreDataStack.viewContext
                                                            imageProcessingQueue:self.imagePreprocessingQueue
                                                                  fetchPredicate:self.fetchPredicate
                                                        needsProcessingPredicate:self.needsProcessingPredicate
                                                                     entityClass:[ZMClientMessage class] preprocessor:self.preprocessor];
    
    [[[self.preprocessor stub] andReturn:@[[[NSOperation alloc] init]]] operationsForPreprocessingImageOwner:self.linkPreviewMessage1];
    [[[self.preprocessor stub] andReturn:@[[[NSOperation alloc] init]]] operationsForPreprocessingImageOwner:self.linkPreviewMessage2];
    [[[self.preprocessor stub] andReturn:@[[[NSOperation alloc] init]]] operationsForPreprocessingImageOwner:self.linkPreviewMessage3];
}

- (void)tearDown
{
    self.imagePreprocessingQueue.suspended = NO;
    WaitForAllGroupsToBeEmpty(0.5);
    self.linkPreviewMessage1 = nil;
    self.linkPreviewMessage2 = nil;
    self.linkPreviewMessage3 = nil;
    self.preprocessor = nil;
    self.imagePreprocessingQueue = nil;
    [self.sut tearDown];
    self.sut = nil;
    self.coreDataStack = nil;
    [super tearDown];
}

- (void)testThatItReturnsTheCorrectFetchRequest
{
    // when
    NSFetchRequest *request = [self.sut fetchRequestForTrackedObjects];
    
    // then
    NSFetchRequest *expectedRequest = [ZMClientMessage sortedFetchRequestWithPredicate:self.fetchPredicate];
    XCTAssertEqualObjects(request, expectedRequest);
}


- (void)testThatItAddsTrackedObjects
{
    // given
    NSSet *objects = [NSSet setWithArray:@[self.linkPreviewMessage1, self.linkPreviewMessage2]];
    
    // when
    self.imagePreprocessingQueue.suspended = YES;
    [self.sut addTrackedObjects:objects];
    
    // then
    XCTAssertTrue([self.sut.imageOwnersBeingPreprocessed containsObject:self.linkPreviewMessage1]);
    XCTAssertTrue([self.sut.imageOwnersBeingPreprocessed containsObject:self.linkPreviewMessage2]);
    self.imagePreprocessingQueue.suspended = NO;
}

- (void)testThatItDoesNotAddTrackedObjectsThatDoNotMatchPredicateForNeedToPreprocess
{
    // given
    NSSet *objects = [NSSet setWithObject:self.linkPreviewMessageExcludedByPredicate];
    
    // when
    self.imagePreprocessingQueue.suspended = YES;
    [self.sut addTrackedObjects:objects];
    
    // then
    XCTAssertFalse(self.sut.hasOutstandingItems);
    XCTAssertEqual(self.sut.imageOwnersThatNeedPreprocessing.count, 0u);
}

@end



@implementation ZMImagePreprocessingTrackerTests (OutstandingItems)

- (void)testThatItHasNoOutstandingItems;
{
    XCTAssertFalse(self.sut.hasOutstandingItems, @"%u / %u",
                   (unsigned) self.sut.imageOwnersThatNeedPreprocessing, (unsigned) self.sut.imageOwnersBeingPreprocessed);
}

- (void)testThatItHasOutstandingItemsWhenItemsAreAdded
{
    // given
    [self.coreDataStack.viewContext.zm_fileAssetCache storeAssetData:self.linkPreviewMessage1 format:ZMImageFormatOriginal encrypted:NO data:[NSData dataWithBytes:"1" length:1]];
    [self.coreDataStack.viewContext.zm_fileAssetCache storeAssetData:self.linkPreviewMessage2 format:ZMImageFormatOriginal encrypted:NO data:[NSData dataWithBytes:"2" length:1]];
    NSSet *objects = [NSSet setWithArray:@[self.linkPreviewMessage1, self.linkPreviewMessage2]];
    
    // when
    self.imagePreprocessingQueue.suspended = YES;
    [self.sut objectsDidChange:objects];

    // then
    XCTAssertTrue(self.sut.hasOutstandingItems, @"%u / %u",
                  (unsigned) self.sut.imageOwnersThatNeedPreprocessing.count, (unsigned) self.sut.imageOwnersBeingPreprocessed.count);
    self.imagePreprocessingQueue.suspended = NO;
}

- (void)testThatItHasOutstandingItemsWhenItemsAreAddedAndOneIsRemoved
{
    // given
    [self.coreDataStack.viewContext.zm_fileAssetCache storeAssetData:self.linkPreviewMessage1 format:ZMImageFormatOriginal encrypted:NO data:[NSData dataWithBytes:"1" length:1]];
    [self.coreDataStack.viewContext.zm_fileAssetCache storeAssetData:self.linkPreviewMessage2 format:ZMImageFormatOriginal encrypted:NO data:[NSData dataWithBytes:"2" length:1]];
    NSSet *objects = [NSSet setWithArray:@[self.linkPreviewMessage1, self.linkPreviewMessage2]];
    
    // when
    self.imagePreprocessingQueue.suspended = YES;
    [self.sut objectsDidChange:objects];
    [self.coreDataStack.viewContext.zm_fileAssetCache deleteAssetData:self.linkPreviewMessage1 format:ZMImageFormatOriginal encrypted:NO];
    [self.sut objectsDidChange:objects];
    
    // then
    XCTAssertTrue(self.sut.hasOutstandingItems, @"%u / %u",
                  (unsigned) self.sut.imageOwnersThatNeedPreprocessing.count, (unsigned) self.sut.imageOwnersBeingPreprocessed.count);
    self.imagePreprocessingQueue.suspended = NO;
}

- (void)testThatItHasNoOutstandingItemsWhenItemsAreAddedAndThenRemoved;
{
    // given
    [self.coreDataStack.viewContext.zm_fileAssetCache storeAssetData:self.linkPreviewMessage1 format:ZMImageFormatOriginal encrypted:NO data:[NSData dataWithBytes:"1" length:1]];
    [self.coreDataStack.viewContext.zm_fileAssetCache storeAssetData:self.linkPreviewMessage2 format:ZMImageFormatOriginal encrypted:NO data:[NSData dataWithBytes:"2" length:1]];
    NSSet *objects = [NSSet setWithArray:@[self.linkPreviewMessage1, self.linkPreviewMessage2]];
    
    // when
    self.imagePreprocessingQueue.suspended = YES;
    [self.sut objectsDidChange:objects];
    self.imagePreprocessingQueue.suspended = NO;
    [self.imagePreprocessingQueue waitUntilAllOperationsAreFinished];
    [self.coreDataStack.viewContext.zm_fileAssetCache deleteAssetData:self.linkPreviewMessage1 format:ZMImageFormatOriginal encrypted:NO];
    [self.coreDataStack.viewContext.zm_fileAssetCache deleteAssetData:self.linkPreviewMessage2 format:ZMImageFormatOriginal encrypted:NO];
    [self.sut objectsDidChange:objects];
    XCTAssert([self waitForAllGroupsToBeEmptyWithTimeout:0.3]);
    
    // then
    XCTAssertFalse(self.sut.hasOutstandingItems, @"%u / %u",
                   (unsigned) self.sut.imageOwnersThatNeedPreprocessing, (unsigned) self.sut.imageOwnersBeingPreprocessed);
}

- (void)testThatItHasNoOutstandingItemsWhenItemsNotMatchingThePredicateChange
{
    // given
    NSSet *objects = [NSSet setWithObject:self.linkPreviewMessageExcludedByPredicate];
    
    // when
    self.imagePreprocessingQueue.suspended = YES;
    [self.sut objectsDidChange:objects];
    
    // then
    XCTAssertFalse(self.sut.hasOutstandingItems);
    XCTAssertEqual(self.sut.imageOwnersThatNeedPreprocessing.count, 0u);
}

@end
