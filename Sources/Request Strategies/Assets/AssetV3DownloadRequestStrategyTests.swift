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


import Foundation
@testable import WireRequestStrategy
import XCTest
import WireDataModel


private let testDataURL = Bundle(for: AssetV3DownloadRequestStrategyTests.self).url(forResource: "Lorem Ipsum", withExtension: "txt")!


public class MockTaskCancellationProvider: NSObject, ZMRequestCancellation {

    var cancelledIdentifiers = [ZMTaskIdentifier]()

    public func cancelTask(with identifier: ZMTaskIdentifier) {
        cancelledIdentifiers.append(identifier)
    }

    deinit {
        cancelledIdentifiers.removeAll()
    }
}


class AssetV3DownloadRequestStrategyTests: MessagingTestBase {

    var mockApplicationStatus: MockApplicationStatus!
    var sut: AssetV3DownloadRequestStrategy!
    var conversation: ZMConversation!
    var user: ZMUser!

    override func setUp() {
        super.setUp()
        
        mockApplicationStatus = MockApplicationStatus()
        mockApplicationStatus.mockSynchronizationState = .eventProcessing
        sut = AssetV3DownloadRequestStrategy(withManagedObjectContext: syncMOC, applicationStatus: mockApplicationStatus)
        
        self.syncMOC.performGroupedBlockAndWait {
            self.user = self.createUser(alsoCreateClient: true)
            self.conversation = self.createGroupConversation(with: self.user)
        }
    }
    
    override func tearDown() {
        mockApplicationStatus = nil
        sut = nil
        user = nil
        conversation = nil
        super.tearDown()
    }
    
    fileprivate func createFileMessageWithAssetId(
        in aConversation: ZMConversation,
        otrKey: Data = Data.randomEncryptionKey(),
        sha: Data  = Data.randomEncryptionKey()
        ) -> (message: ZMAssetClientMessage, assetId: String, assetToken: String)? {

        let message = aConversation.append(file: ZMFileMetadata(fileURL: testDataURL)) as! ZMAssetClientMessage
        let (assetId, token) = (UUID.create().transportString(), UUID.create().transportString())

        // TODO: We should replace this manual update with inserting a v3 asset as soon as we have sending support
        let uploaded = ZMGenericMessage.message(content: ZMAsset.asset(withUploadedOTRKey: otrKey, sha256: sha), nonce: message.nonce!, expiresAfter: aConversation.messageDestructionTimeoutValue)

        guard let uploadedWithId = uploaded.updatedUploaded(withAssetId: assetId, token: token) else {
            XCTFail("Failed to update asset")
            return nil
        }
        
        message.add(uploadedWithId)
        configureForDownloading(message: message)
        XCTAssertEqual(message.version, 3)
        return (message, assetId, token)
    }

    fileprivate func configureForDownloading(message: ZMAssetClientMessage) {
        contextDirectory.uiContext.zm_fileAssetCache.deleteAssetData(message)
        contextDirectory.syncContext.zm_fileAssetCache.deleteAssetData(message)

        message.requestFileDownload()
        syncMOC.saveOrRollback()

        sut.contextChangeTrackers.forEach { tracker in
            tracker.objectsDidChange([message])
        }
    }

    func testThatItGeneratesARequestToTheV3EndpointIfTheProtobufContainsAnAssetID_V3() {
        // Given
        syncMOC.performGroupedBlockAndWait {
            
            guard let (message, assetId, token) = self.createFileMessageWithAssetId(in: self.conversation) else { return XCTFail("No message") }
            
            guard let assetData = message.genericAssetMessage?.assetData else { return XCTFail("No assetData found") }
            XCTAssert(assetData.hasUploaded())
            XCTAssertEqual(assetData.uploaded.assetId, assetId)
            XCTAssertEqual(assetData.uploaded.assetToken, token)
            
            // When
            guard let request = self.sut.nextRequest() else { return XCTFail("No request generated") }
            
            // Then
            XCTAssertEqual(request.method, .methodGET)
            XCTAssertEqual(request.path, "/assets/v3/\(assetId)")
            XCTAssert(request.needsAuthentication)
        }
    }

    func testThatItGeneratesARequestToTheV3EndpointITheProtobufContainsAnAssetID_EphemeralConversation_V3() {
        syncMOC.performGroupedBlockAndWait {
            
            // Given
            self.conversation.messageDestructionTimeout = .local(MessageDestructionTimeoutValue(rawValue: 5))
            guard let (message, assetId, token) = self.createFileMessageWithAssetId(in: self.conversation) else { return XCTFail("No message") }
            guard let assetData = message.genericAssetMessage?.assetData else { return XCTFail("No assetData found") }
            XCTAssert(assetData.hasUploaded())
            XCTAssertEqual(assetData.uploaded.assetId, assetId)
            XCTAssertEqual(assetData.uploaded.assetToken, token)
            XCTAssert(message.genericAssetMessage!.hasEphemeral())
            
            // When
            guard let request = self.sut.nextRequest() else { return XCTFail("No request generated") }
            
            // Then
            XCTAssertEqual(request.method, .methodGET)
            XCTAssertEqual(request.path, "/assets/v3/\(assetId)")
            XCTAssert(request.needsAuthentication)
        }
    }

    func testThatItGeneratesARequestOnlyOnceForAssetMessages_V3() {
        // Given
        syncMOC.performGroupedBlockAndWait {
            guard let _ = self.createFileMessageWithAssetId(in: self.conversation) else { return XCTFail("No message") }
            
            // When
            guard let _ = self.sut.nextRequest() else { return XCTFail("No request generated") }
            
            // Then
            XCTAssertNil(self.sut.nextRequest())
        }
    }

    func testThatItGeneratesNoRequestsIfNotAuthenticated_V3() {
        syncMOC.performGroupedBlockAndWait {
            // GIVEN
            self.mockApplicationStatus.mockSynchronizationState = .unauthenticated
            _ = self.createFileMessageWithAssetId(in: self.conversation)! // V3
            
            // THEN
            XCTAssertNil(self.sut.nextRequest())
        }
    }

    func testThatItGeneratesNoRequestsIfMessageIsUploading_V3() {
        self.syncMOC.performGroupedBlockAndWait {
            // GIVEN
            guard let (message , _, _) = self.createFileMessageWithAssetId(in: self.conversation) else { return XCTFail() } // V3
            message.fileMessageData?.transferState = .uploaded
            self.syncMOC.saveOrRollback()
            
            self.sut.contextChangeTrackers.forEach { tracker in
                tracker.objectsDidChange(Set(arrayLiteral: message))
            }
            
            // THEN
            XCTAssertNil(self.sut.nextRequest())
        }
    }

}

// tests on result of request
extension AssetV3DownloadRequestStrategyTests {

    func testThatItMarksDownloadAsSuccessIfSuccessfulDownloadAndDecryption_V3() {
        var message: ZMMessage!
        self.syncMOC.performGroupedBlockAndWait {
            
            // GIVEN
            let plainTextData = Data.secureRandomData(length: 500)
            let key = Data.randomEncryptionKey()
            let encryptedData = plainTextData.zmEncryptPrefixingPlainTextIV(key: key)
            let sha = encryptedData.zmSHA256Digest()
            
            let (msg, _, _) = self.createFileMessageWithAssetId(in: self.conversation, otrKey: key, sha: sha)!
            message = msg
            
            let request = self.sut.nextRequest()
            let response = ZMTransportResponse(imageData: encryptedData, httpStatus: 200, transportSessionError: .none, headers: [:])
            
            // WHEN
            request?.complete(with: response)
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        self.syncMOC.performGroupedBlockAndWait {
            // THEN
            XCTAssertEqual(message.fileMessageData?.transferState.rawValue, ZMFileTransferState.downloaded.rawValue)
        }
    }

    func testThatItMarksDownloadAsFailedIfCannotDownload_PermanentError_V3() {
        let message: ZMAssetClientMessage = syncMOC.performGroupedAndWait { _ in
            // GIVEN
            let (msg, _, _) = self.createFileMessageWithAssetId(in: self.conversation)!
            let request = self.sut.nextRequest()
            let response = ZMTransportResponse(payload: [] as ZMTransportData, httpStatus: 404, transportSessionError: .none)
            
            // WHEN
            request?.complete(with: response)
            return msg
        }

        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        syncMOC.performGroupedBlockAndWait {
            // THEN
            XCTAssertEqual(message.fileMessageData?.transferState, .unavailable)
            self.configureForDownloading(message: message)
            XCTAssertNil(self.sut.nextRequest())
        }
    }

    func testThatItMarksDownloadAsFailedIfCannotDownload_TemporaryError_V3() {
        let message: ZMAssetClientMessage = syncMOC.performGroupedAndWait { _ in
            // GIVEN
            let (msg, _, _) = self.createFileMessageWithAssetId(in: self.conversation)!
            let request = self.sut.nextRequest()
            let response = ZMTransportResponse(payload: [] as ZMTransportData, httpStatus: 500, transportSessionError: nil)

            // WHEN
            request?.complete(with: response)
            return msg
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        syncMOC.performGroupedBlockAndWait {
            // THEN
            XCTAssertEqual(message.fileMessageData?.transferState.rawValue, ZMFileTransferState.failedDownload.rawValue)
            self.configureForDownloading(message: message)
            XCTAssertNotNil(self.sut.nextRequest())
        }
    }

    func testThatItMarksDownloadAsFailedIfCannotDownload_CannotDecrypt_V3() {
        var message : ZMMessage!
        var request: ZMTransportRequest?
        self.syncMOC.performGroupedBlockAndWait {
            
            // GIVEN
            let (msg, _, _) = self.createFileMessageWithAssetId(in: self.conversation)!
            message = msg
            
            request = self.sut.nextRequest()
        }
        
            
        // WHEN
        self.performIgnoringZMLogError {
            self.syncMOC.performGroupedBlockAndWait {
                let response = ZMTransportResponse(payload: [] as ZMTransportData, httpStatus: 200, transportSessionError: .none)
                request?.complete(with: response)
            }
            XCTAssert(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        }
        
            // THEN
        self.syncMOC.performGroupedBlockAndWait {
            XCTAssertEqual(message.fileMessageData?.transferState.rawValue, ZMFileTransferState.failedDownload.rawValue)
        }
    }

    func testThatItDoesNotMarkDownloadAsFailedWhenNotDownloading_V3() {
        var message : ZMMessage!

        self.syncMOC.performGroupedBlockAndWait {
            
            // GIVEN
            let (msg, _, _) = self.createFileMessageWithAssetId(in: self.conversation)!
            let request = self.sut.nextRequest()
            let response = ZMTransportResponse(payload: [] as ZMTransportData, httpStatus: 500, transportSessionError: .none)
            
            // WHEN
            msg.transferState = .uploaded
            message = msg

            request?.complete(with: response)
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        self.syncMOC.performGroupedBlockAndWait {
            // THEN
            XCTAssertEqual(message.fileMessageData?.transferState.rawValue, ZMFileTransferState.uploaded.rawValue)
        }
    }

    func testThatItUpdatesFileDownloadProgress_V3() {
        var message : ZMMessage!
        let expectedProgress: Float = 0.5

        self.syncMOC.performGroupedBlockAndWait {
            // GIVEN
            let (msg, _, _) = self.createFileMessageWithAssetId(in: self.conversation)!
            message = msg
            let request = self.sut.nextRequest()
            
            XCTAssertEqual(msg.fileMessageData?.progress, 0)
            
            // WHEN
            request?.updateProgress(expectedProgress)
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        self.syncMOC.performGroupedBlockAndWait {
            // THEN
            XCTAssertEqual(message.fileMessageData?.progress, expectedProgress)
        }
    }

    func testThatItSendsTheNotificationIfSuccessfulDownloadAndDecryption_V3() {
        
        var token: Any? = nil
        self.syncMOC.performGroupedBlockAndWait {
            
            // GIVEN
            let plainTextData = Data.secureRandomData(length: 500)
            let key = Data.randomEncryptionKey()
            let encryptedData = plainTextData.zmEncryptPrefixingPlainTextIV(key: key)
            let sha = encryptedData.zmSHA256Digest()
            
            let _ = self.createFileMessageWithAssetId(in: self.conversation, otrKey: key, sha: sha)!
            
            let expectation = self.expectation(description: "Notification fired")
            token = NotificationInContext.addObserver(name: AssetDownloadRequestStrategyNotification.downloadFinishedNotificationName,
                                                          context: self.uiMOC.notificationContext,
                                                          object: nil)
            { note in
                XCTAssertNotNil(note.userInfo[AssetDownloadRequestStrategyNotification.downloadStartTimestampKey] as? Date)
                expectation.fulfill()
            }
            
            guard let request = self.sut.nextRequest() else {
                return XCTFail("Did not create expected request")
            }
            request.markStartOfUploadTimestamp()
            let response = ZMTransportResponse(imageData: encryptedData, httpStatus: 200, transportSessionError: .none, headers: [:])
            
            // WHEN
            request.complete(with: response)
        }
        
        withExtendedLifetime(token) { () -> () in
            // THEN
            XCTAssertTrue(self.waitForCustomExpectations(withTimeout: 0.5))
        }
    }
    
    func testThatItRecategorizeMessageAfterDownloadingAssetContent() {
        var message : ZMAssetClientMessage!
        self.syncMOC.performGroupedBlockAndWait {
            
            // GIVEN
            let plainTextData = self.verySmallJPEGData()
            let key = Data.randomEncryptionKey()
            let encryptedData = plainTextData.zmEncryptPrefixingPlainTextIV(key: key)
            let sha = encryptedData.zmSHA256Digest()
            let messageId = UUID.create()
            
            let asset = ZMAssetBuilder()
                .setOriginal(ZMAssetOriginalBuilder()
                    .setMimeType("image/jpeg")
                    .setSize(UInt64(plainTextData.count))
                    .setImage(ZMAssetImageMetaDataBuilder()
                        .setWidth(100)
                        .setHeight(100)
                        .setTag("medium")))
                .setUploaded(ZMAssetRemoteDataBuilder()
                    .setOtrKey(key)
                    .setSha256(sha)
                    .setAssetId("someId")
                    .setAssetToken("someToken"))
                .build()
            
            let genericMessage = ZMGenericMessage.message(content: asset!, nonce: messageId)
            
            let dict = ["recipient": self.selfClient.remoteIdentifier!,
                        "sender": self.selfClient.remoteIdentifier!,
                        "text": genericMessage.data().base64String()] as NSDictionary
            let updateEvent = ZMUpdateEvent(fromEventStreamPayload: ([
                "type": "conversation.otr-message-add",
                "data":dict,
                "from" : self.selfClient.user!.remoteIdentifier!,
                "conversation":self.conversation.remoteIdentifier!.transportString(),
                "time":Date(timeIntervalSince1970: 555555).transportString()] as NSDictionary), uuid: nil)!
            
            message = ZMOTRMessage.messageUpdateResult(from: updateEvent, in: self.syncMOC, prefetchResult: nil)?.message as? ZMAssetClientMessage
            message.visibleInConversation = self.conversation
            message.transferState = .downloading
            
            XCTAssertEqual(message.category, [.image, .excludedFromCollection])
            
            self.sut.contextChangeTrackers.forEach { (tracker) in
                tracker.objectsDidChange([message])
            }
            
            let request = self.sut.nextRequest()
            request?.markStartOfUploadTimestamp()
            let response = ZMTransportResponse(imageData: encryptedData, httpStatus: 200, transportSessionError: .none, headers: [:])
            
            // WHEN
            request?.complete(with: response)
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout:0.5))
        
        self.syncMOC.performGroupedBlockAndWait {
            // THEN
            XCTAssertEqual(message.category, [.image])
        }
    }
    
    
    func testThatItRecategorizeMessageWithSvgAttachmentAfterDownloadingAssetContent() {
        var message : ZMAssetClientMessage!
        self.syncMOC.performGroupedBlockAndWait {
            
            // GIVEN
            guard let plainTextData = ("<svg width=\"100\" height=\"100\">"
                                        + "<rect width=\"100\" height=\"100\"/>"
                                        + "</svg>").data(using: .utf8) else {
                XCTFail("Unable to convert SVG to Data");
                return;
            }
            
            let key = Data.randomEncryptionKey()
            let encryptedData = plainTextData.zmEncryptPrefixingPlainTextIV(key: key)
            let sha = encryptedData.zmSHA256Digest()
            let messageId = UUID.create()
            
            let asset = ZMAssetBuilder()
                .setOriginal(ZMAssetOriginalBuilder()
                    .setMimeType("image/svg+xml")
                    .setSize(UInt64(plainTextData.count))
                    .setImage(ZMAssetImageMetaDataBuilder() // Even if we treat them as files, SVGs are sent as images.
                        .setWidth(100)
                        .setHeight(100)
                        .setTag("medium")))
                .setUploaded(ZMAssetRemoteDataBuilder()
                    .setOtrKey(key)
                    .setSha256(sha)
                    .setAssetId("someId")
                    .setAssetToken("someToken"))
                .build()
            
            let genericMessage = ZMGenericMessage.message(content: asset!, nonce: messageId)
            
            let dict = ["recipient": self.selfClient.remoteIdentifier!,
                        "sender": self.selfClient.remoteIdentifier!,
                        "text": genericMessage.data().base64String()] as NSDictionary
            let updateEvent = ZMUpdateEvent(fromEventStreamPayload: ([
                "type": "conversation.otr-message-add",
                "data":dict,
                "from" : self.selfClient.user!.remoteIdentifier!,
                "conversation":self.conversation.remoteIdentifier!.transportString(),
                "time":Date(timeIntervalSince1970: 555555).transportString()] as NSDictionary), uuid: nil)!
            
            message = ZMOTRMessage.messageUpdateResult(from: updateEvent, in: self.syncMOC, prefetchResult: nil)?.message as? ZMAssetClientMessage
            message.visibleInConversation = self.conversation
            message.transferState = .downloading
            
            XCTAssertEqual(message.category, [.file])
            XCTAssertNotEqual(message.category, [.image])
            
            self.sut.contextChangeTrackers.forEach { (tracker) in
                tracker.objectsDidChange([message])
            }
            
            let request = self.sut.nextRequest()
            request?.markStartOfUploadTimestamp()
            let response = ZMTransportResponse(imageData: encryptedData, httpStatus: 200, transportSessionError: .none, headers: [:])
            
            // WHEN
            request?.complete(with: response)
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout:0.5))
        
        self.syncMOC.performGroupedBlockAndWait {
            // THEN
            XCTAssertEqual(message.category, [.file])
            XCTAssertNotEqual(message.category, [.image])
        }
    }
    
    func testThatItSendsTheNotificationIfCannotDownload_V3() {
        var token: Any? = nil
        self.syncMOC.performGroupedBlockAndWait {
            
            // GIVEN
            let expectation = self.expectation(description: "Notification fired")
            token = NotificationInContext.addObserver(name: AssetDownloadRequestStrategyNotification.downloadFailedNotificationName,
                                                          context: self.uiMOC.notificationContext,
                                                          object: nil)
            { note in
                XCTAssertNotNil(note.userInfo[AssetDownloadRequestStrategyNotification.downloadStartTimestampKey] as? Date)
                expectation.fulfill()
            }
            
            let _ = self.createFileMessageWithAssetId(in: self.conversation)!
            guard let request = self.sut.nextRequest() else { return XCTFail("No message")}
            
            request.markStartOfUploadTimestamp()
            let response = ZMTransportResponse(payload: [] as ZMTransportData, httpStatus: 404, transportSessionError: .none)
            
            // WHEN
            request.complete(with: response)
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        self.syncMOC.performGroupedBlockAndWait {
            // THEN
            withExtendedLifetime(token) { () -> () in
                XCTAssertTrue(self.waitForCustomExpectations(withTimeout: 0.5))
            }
        }
    }
}

// MARK : - Download Cancellation

extension AssetV3DownloadRequestStrategyTests {

    func testThatItInformsTheTaskCancellationProviderToCancelARequestForAnAssetMessageWhenItReceivesTheNotification_V3() {
        var message : ZMAssetClientMessage!
        var identifier: ZMTaskIdentifier?
        self.syncMOC.performGroupedBlockAndWait {
            
            // GIVEN
            let (msg, _, _) = self.createFileMessageWithAssetId(in: self.conversation)!
            message = msg
            XCTAssertNotNil(message.objectID)
            
            // GIVEN the task has been created
            guard let request = self.sut.nextRequest() else { return XCTFail("No request created") }
            
            request.callTaskCreationHandlers(withIdentifier: 42)
            XCTAssertTrue(self.syncMOC.saveOrRollback())
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout:0.5))

        self.syncMOC.performGroupedBlockAndWait {
            identifier = message.associatedTaskIdentifier
        }
        XCTAssertNotNil(identifier)

        // WHEN the transfer is cancelled
        self.syncMOC.performGroupedBlock {
            message.fileMessageData?.cancelTransfer()
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout:0.5))
        
        
        self.syncMOC.performGroupedBlockAndWait {
            // THEN the cancellation provider should be informed to cancel the request
            XCTAssertEqual(self.mockApplicationStatus.cancelledIdentifiers.count, 1)
            let cancelledIdentifier = self.mockApplicationStatus.cancelledIdentifiers.first
            XCTAssertEqual(cancelledIdentifier, identifier)
            
            // It should nil-out the identifier as it has been cancelled
            XCTAssertNil(message.associatedTaskIdentifier)
        }
    }
    
}

