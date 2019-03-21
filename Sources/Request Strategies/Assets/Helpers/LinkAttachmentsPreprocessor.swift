//
// Wire
// Copyright (C) 2019 Wire Swiss GmbH
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
import WireLinkPreview
import WireDataModel
import WireUtilities

private let zmLog = ZMSLog(tag: "link-attachments")

public final class LinkAttachmentDetectorHelper : NSObject {
    fileprivate static var _test_debug_linkAttachmentDetector : LinkAttachmentDetectorType? = nil

    public class func defaultDetector() -> LinkAttachmentDetectorType {
        return test_debug_linkAttachmentDetector() ?? LinkAttachmentDetector()
    }

    public class func test_debug_linkAttachmentDetector() -> LinkAttachmentDetectorType? {
        return _test_debug_linkAttachmentDetector
    }

    public class func setTest_debug_linkAttachmentDetector(_ detectorType: LinkAttachmentDetectorType?) {
        _test_debug_linkAttachmentDetector = detectorType
    }

    public class func tearDown() {
        _test_debug_linkAttachmentDetector = nil
    }

}

@objcMembers public final class LinkAttachmentsPreprocessor : NSObject, ZMContextChangeTracker {

    /// List of objects currently being processed
    fileprivate var objectsBeingProcessed = Set<ZMClientMessage>()
    fileprivate let linkAttachmentDetector: LinkAttachmentDetectorType

    let managedObjectContext : NSManagedObjectContext

    public init(linkAttachmentDetector: LinkAttachmentDetectorType, managedObjectContext: NSManagedObjectContext) {
        self.linkAttachmentDetector = linkAttachmentDetector
        self.managedObjectContext = managedObjectContext
        super.init()
    }

    public func objectsDidChange(_ objects: Set<NSManagedObject>) {
        processObjects(objects)
    }

    public func fetchRequestForTrackedObjects() -> NSFetchRequest<NSFetchRequestResult>? {
        let predicate = ZMMessage.predicateForMessagesThatNeedToUpdateLinkAttachments()
        return ZMClientMessage.sortedFetchRequest(with: predicate)
    }

    public func addTrackedObjects(_ objects: Set<NSManagedObject>) {
        processObjects(objects)
    }

    func processObjects(_ objects: Set<NSObject>) {
        objects.lazy
            .compactMap(linkAttachmentsToPreprocess)
            .filter(!objectsBeingProcessed.contains)
            .forEach(processMessage)
    }

    func linkAttachmentsToPreprocess(_ object: NSObject) -> ZMClientMessage? {
        guard let message = object as? ZMClientMessage else { return nil }
        return message.needsLinkAttachmentsUpdate ? message : nil
    }

    func processMessage(_ message: ZMClientMessage) {
        objectsBeingProcessed.insert(message)

        if let textMessageData = (message as ZMConversationMessage).textMessageData,
            let messageText = textMessageData.messageText {
            zmLog.debug("fetching previews for: \(message.nonce?.uuidString ?? "nil")")

            // We DONT want to generate link previews inside a mentions
            let mentionRanges = textMessageData.mentions.map(\.range)

            // We DONT want to generate link previews for markdown links such as
            // [click me!](www.example.com).
            let markdownRanges = markdownLinkRanges(in: messageText)

            linkAttachmentDetector.downloadLinkAttachments(inText: messageText, excluding: mentionRanges + markdownRanges) { [weak self] linkAttachments in
                self?.managedObjectContext.performGroupedBlock {
                    zmLog.debug("\(linkAttachments.count) attachments for: \(message.nonce?.uuidString ?? "nil")\n\(linkAttachments)")
                    self?.didProcessMessage(message, linkAttachments: linkAttachments)
                }
            }

        } else {
            didProcessMessage(message, linkAttachments: [])
        }
    }

    func didProcessMessage(_ message: ZMClientMessage, linkAttachments: [LinkAttachment]) {
        objectsBeingProcessed.remove(message)

        if let attachment = linkAttachments.first, !message.isObfuscated {
            message.linkAttachments = [attachment]

            if let imageData = attachment.thumbnails.first.flatMap({ (attachment.imageCache[$0]) }) {
                managedObjectContext.zm_fileAssetCache.storeAssetData(message, format: .original, encrypted: false, data: imageData)
            }
        }

        message.needsLinkAttachmentsUpdate = false

        // The change processor is called as a response to a context save,
        // which is why we need to enque a save maually here
        managedObjectContext.enqueueDelayedSave()
    }

    fileprivate func markdownLinkRanges(in text: String) -> [NSRange] {
        guard let regex = try? NSRegularExpression(pattern: "\\[.+\\]\\((.+)\\)", options: []) else { return [] }
        let wholeRange = NSRange(text.startIndex ..< text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: wholeRange).compactMap { $0.range(at: 0) }
    }
}
