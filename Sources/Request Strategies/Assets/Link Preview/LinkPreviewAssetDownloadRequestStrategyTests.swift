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
import WireDataModel
import XCTest
import WireRequestStrategy


@testable import WireRequestStrategy

class LinkPreviewAssetDownloadRequestStrategyTests: MessagingTestBase {

    var sut: LinkPreviewAssetDownloadRequestStrategy!
    var mockApplicationStatus : MockApplicationStatus!
    var oneToOneconversationOnSync : ZMConversation!
    
    override func setUp() {
        super.setUp()
        self.syncMOC.performGroupedAndWait { syncMOC in
            self.mockApplicationStatus = MockApplicationStatus()
            self.mockApplicationStatus.mockSynchronizationState = .eventProcessing
            self.oneToOneconversationOnSync = syncMOC.object(with: self.oneToOneConversation.objectID) as? ZMConversation

            self.sut = LinkPreviewAssetDownloadRequestStrategy(withManagedObjectContext: syncMOC, applicationStatus: self.mockApplicationStatus)
        }
    }
    
    override func tearDown() {
        self.syncMOC.performGroupedAndWait { syncMOC in
            self.sut = nil
            self.mockApplicationStatus = nil
            self.oneToOneconversationOnSync = nil
            syncMOC.zm_fileAssetCache.wipeCaches()
        }
        uiMOC.zm_fileAssetCache.wipeCaches()
        super.tearDown()
    }
    
    // MARK: - Helper
    
    fileprivate func createLinkPreview(_ assetID: String, article: Bool = true, otrKey: Data? = nil, sha256: Data? = nil) -> LinkPreview {
        let URL = "http://www.example.com"
        
        if article {
            let (otr, sha) = (otrKey ?? Data.randomEncryptionKey(), sha256 ?? Data.zmRandomSHA256Key())
            let remoteData = WireProtos.Asset.RemoteData.with {
                $0.assetID = assetID
                $0.otrKey = otr
                $0.sha256 = sha
            }
            let asset = WireProtos.Asset.with {
                $0.uploaded = remoteData
            }
            let preview = LinkPreview.with {
                $0.url = URL
                $0.permanentURL = URL
                $0.urlOffset = 42
                $0.title = "Title"
                $0.summary = "Summary"
                $0.image = asset
            }
            return preview
        } else {
            let preview = LinkPreview.with {
                $0.url = URL
                $0.permanentURL = URL
                $0.urlOffset = 42
                $0.title = "Title"
                $0.summary = "Summary"
                $0.tweet = Tweet.with {
                    $0.author = "Author"
                    $0.username = "UserName"
                }
            }
            return preview
        }
    }
    
    fileprivate func fireSyncCompletedNotification() {
        // ManagedObjectContextObserver does not process all changes until the sync is done
        NotificationCenter.default.post(name: Notification.Name(rawValue: "ZMApplicationDidEnterEventProcessingStateNotification"), object: nil, userInfo: nil)
    }
}

extension LinkPreviewAssetDownloadRequestStrategyTests {
    
    // MARK: - Request Generation

    func testThatItGeneratesARequestForAWhitelistedMessageWithNoImageInCache() {
        // GIVEN
        let assetID = UUID.create().transportString()
        let linkPreview = self.createLinkPreview(assetID)
        let nonce = UUID.create()
        var text = Text(content: self.name, mentions: [], linkPreviews: [], replyingTo: nil)
        text.linkPreview.append(linkPreview)
        let genericMessage = GenericMessage(content: text, nonce: nonce)

        self.syncMOC.performGroupedAndWait { syncMOC in
            let message = self.oneToOneconversationOnSync.appendClientMessage(with: genericMessage)!
            _ = try? syncMOC.obtainPermanentIDs(for: [message])

            // WHEN
            message.textMessageData?.requestLinkPreviewImageDownload()
        }
        self.syncMOC.performGroupedAndWait { syncMOC in
            // THEN
            guard let request = self.sut.nextRequest() else { XCTFail("No request generated"); return }
            XCTAssertEqual(request.path, "/assets/v3/\(assetID)")
            XCTAssertEqual(request.method, ZMTransportRequestMethod.methodGET)
            XCTAssertNil(self.sut.nextRequest())
        }
    }
    
    func testThatItGeneratesARequestForAWhitelistedEphemeralMessageWithNoImageInCache() {
        let assetID = UUID.create().transportString()

        self.syncMOC.performGroupedAndWait { syncMOC in
            // GIVEN
            let linkPreview = self.createLinkPreview(assetID)
            let nonce = UUID.create()
//            let text = Text.with {
//                $0.content = self.name
//                $0.mentions = []
//                $0.linkPreview = [linkPreview]
//            }
            var text = Text(content: self.name, mentions: [], linkPreviews: [], replyingTo: nil)
            text.linkPreview.append(linkPreview)
            let genericMessage = GenericMessage(content: text, nonce: nonce, expiresAfter: 20)
            let message = self.oneToOneconversationOnSync.appendClientMessage(with: genericMessage)!
            _ = try? syncMOC.obtainPermanentIDs(for: [message])

            // WHEN
            message.textMessageData?.requestLinkPreviewImageDownload()
        }
        self.syncMOC.performGroupedAndWait { syncMOC in
            // THEN
            guard let request = self.sut.nextRequest() else { XCTFail("No request generated"); return }
            XCTAssertEqual(request.path, "/assets/v3/\(assetID)")
            XCTAssertEqual(request.method, ZMTransportRequestMethod.methodGET)
            XCTAssertNil(self.sut.nextRequest())
        }
    }
    
    func testThatItDoesNotGenerateARequestForAMessageWithoutALinkPreview() {
        let message = syncMOC.performGroupedAndWait { moc -> ZMMessage in
            let genericMessage = GenericMessage(content: Text(content: self.name))
            return self.oneToOneconversationOnSync.appendClientMessage(with: genericMessage)!
        }
        
        syncMOC.performGroupedBlockAndWait {
            _ = try? self.syncMOC.obtainPermanentIDs(for: [message])
        }
        
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // WHEN
        syncMOC.performGroupedBlockAndWait {
            message.textMessageData?.requestLinkPreviewImageDownload()
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // THEN
        self.syncMOC.performGroupedAndWait { syncMOC in
            // THEN
            XCTAssertNil(self.sut.nextRequest())
        }
    }
    
    func testThatItDoesNotGenerateARequestForAMessageWithImageInCache() {
        self.syncMOC.performGroupedAndWait { syncMOC in
            // GIVEN
            let assetID = UUID.create().transportString()
            let linkPreview = self.createLinkPreview(assetID)
            let nonce = UUID.create()
            let text = Text.with {
                $0.content = self.name
                $0.mentions = []
                $0.linkPreview = [linkPreview]
            }
            let genericMessage = GenericMessage(content: text, nonce: nonce)
            let message = self.oneToOneconversationOnSync.appendClientMessage(with: genericMessage)!
            _ = try? syncMOC.obtainPermanentIDs(for: [message])
            syncMOC.zm_fileAssetCache.storeAssetData(message, format: .medium, encrypted: false, data: .secureRandomData(length: 256))

            // WHEN
            message.textMessageData?.requestLinkPreviewImageDownload()
        }
        self.syncMOC.performGroupedAndWait { syncMOC in
            // THEN
            XCTAssertNil(self.sut.nextRequest())
        }
    }
    
    func testThatItDoesNotGenerateARequestForAMessageWithoutArticleLinkPreview() {
        let assetID = UUID.create().transportString()
        let linkPreview = self.createLinkPreview(assetID, article: false)
        let nonce = UUID.create()
        let text = Text.with {
            $0.content = self.name
            $0.mentions = []
            $0.linkPreview = [linkPreview]
        }
        let genericMessage = GenericMessage(content: text, nonce: nonce)
        var message: ZMMessage!

        self.syncMOC.performGroupedAndWait { syncMOC in
            // GIVEN
            message = self.oneToOneconversationOnSync.appendClientMessage(with: genericMessage)!
            _ = try? syncMOC.obtainPermanentIDs(for: [message])
            syncMOC.zm_fileAssetCache.storeAssetData(message, format: .medium, encrypted: false, data: .secureRandomData(length:256))

            // WHEN
            message.textMessageData?.requestLinkPreviewImageDownload()
        }
        self.syncMOC.performGroupedAndWait { syncMOC in
            // THEN
            XCTAssertNil(self.sut.nextRequest())
        }
    }
    
    // MARK: - Response Handling
    
    func testThatItDecryptsTheImageDataInTheRequestResponseAndDeletesTheEncryptedVersion() {

        let assetID = UUID.create().transportString()
        let data = Data.secureRandomData(length: 256)
        let otrKey = Data.randomEncryptionKey()
        let encrypted = data.zmEncryptPrefixingPlainTextIV(key: otrKey)
//        let (linkPreview, _, _) = createLinkPreviewAndKeys(assetID, otrKey: otrKey, sha256: encrypted.zmSHA256Digest())
        let linkPreview = createLinkPreview(assetID, otrKey: otrKey, sha256: encrypted.zmSHA256Digest())
        let nonce = UUID.create()
        let text = Text.with {
            $0.content = self.name
            $0.mentions = []
            $0.linkPreview = [linkPreview]
        }
        let genericMessage = GenericMessage(content: text, nonce: nonce)

        var message: ZMMessage!

        self.syncMOC.performGroupedAndWait { syncMOC in

            message = self.oneToOneconversationOnSync.appendClientMessage(with: genericMessage)!
            _ = try? syncMOC.obtainPermanentIDs(for: [message])

            // WHEN
            message.textMessageData?.requestLinkPreviewImageDownload()
        }
        self.syncMOC.performGroupedAndWait { syncMOC in
            // THEN
            guard let request = self.sut.nextRequest() else { XCTFail("No request generated"); return }
            let response = ZMTransportResponse(imageData: encrypted, httpStatus: 200, transportSessionError: nil, headers: nil)

            // WHEN
            request.complete(with: response)
        }
        self.syncMOC.performGroupedAndWait { syncMOC in
            // THEN
            let actual = syncMOC.zm_fileAssetCache.assetData(message, format: .medium, encrypted: false)
            XCTAssertNotNil(actual)
            XCTAssertEqual(actual, data)
            XCTAssertNil(syncMOC.zm_fileAssetCache.assetData(message, format: .medium, encrypted: true))
        }
    }
    
    func testThatItDoesNotDecyptTheImageDataInTheRequestResponseWhenTheResponseIsNotSuccessful() {
        let assetID = UUID.create().transportString()
//        let (linkPreview, _, _) = createLinkPreviewAndKeys(assetID)
        let linkPreview = createLinkPreview(assetID)
        let nonce = UUID.create()
        let text = Text.with {
            $0.content = self.name
            $0.mentions = []
            $0.linkPreview = [linkPreview]
        }
        let genericMessage = GenericMessage(content: text, nonce: nonce)
        var message: ZMMessage!
        self.syncMOC.performGroupedAndWait { syncMOC in

            message = self.oneToOneconversationOnSync.appendClientMessage(with: genericMessage)!
            _ = try? syncMOC.obtainPermanentIDs(for: [message])
        
            // WHEN
            message.textMessageData?.requestLinkPreviewImageDownload()
        }

        self.syncMOC.performGroupedAndWait { syncMOC in
            // THEN
            guard let request = self.sut.nextRequest() else { XCTFail("No request generated"); return }
            let response = ZMTransportResponse(imageData: .secureRandomData(length:256), httpStatus: 400, transportSessionError: nil, headers: nil)
            // WHEN
            request.complete(with: response)
        }
        self.syncMOC.performGroupedAndWait { syncMOC in
            // THEN
            XCTAssertNil(syncMOC.zm_fileAssetCache.assetData(message, format: .medium, encrypted: false))
            XCTAssertNil(syncMOC.zm_fileAssetCache.assetData(message, format: .medium, encrypted: true))
        }
    }
}

