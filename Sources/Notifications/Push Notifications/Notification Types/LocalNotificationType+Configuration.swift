//
// Wire
// Copyright (C) 2018 Wire Swiss GmbH
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

extension LocalNotificationType {

    func category(hasTeam: Bool, encryptionAtRestEnabled: Bool) -> PushNotificationCategory {
        return PushNotificationCategory(notificationType: self)
            .addEncryptionAtRestIfNeeded(encryptionAtRestEnabled: encryptionAtRestEnabled)
            .addMuteIfNeeded(hasTeam: hasTeam)
    }

    var sound: NotificationSound {
        switch self {
/// TODO Katerina fix it
//        case .calling(let callState):
//            switch callState {
//            case .incoming:
//                return .call
//            default:
//                return .newMessage
//            }
        case .calling:
            return .newMessage
        case .event:
            return .newMessage
        case .message(let contentType):
            switch contentType {
            case .knock:
                return .ping
            default:
                return .newMessage
            }
        case .failedMessage, .availabilityBehaviourChangeAlert:
            return .newMessage
        }
    }

}

private extension PushNotificationCategory {

    init(notificationType: LocalNotificationType) {
        switch notificationType {
            /// TODO Katerina fix it
//        case .calling(let callState):
//            self.init(callState: callState)
        case .calling:
            self = .alert
        case .event(let eventType):
            self.init(eventType: eventType)
        case .message(let contentType):
            self.init(contentType: contentType)
        case .failedMessage:
            self = .conversation
        case .availabilityBehaviourChangeAlert:
            self = .alert
        }
    }

    /// TODO Katerina fix it
//    init(callState: CallState) {
//        switch (callState) {
//        case .incoming:
//            self = .incomingCall
//        case .terminating(reason: .timeout):
//            self = .missedCall
//        default :
//            self = .conversation
//        }
//    }

    init(eventType: LocalNotificationEventType) {
        switch eventType {
        case .connectionRequestPending, .conversationCreated:
            self = .connect
        default:
            self = .conversation
        }
    }

    init(contentType: LocalNotificationContentType) {
        switch contentType {
        case .audio, .video, .fileUpload, .image, .text, .location:
            self = .conversationWithLike
        case .hidden:
            self = .alert
        default:
            self = .conversation
        }
    }

    func addMuteIfNeeded(hasTeam: Bool) -> Self {
        guard !hasTeam else { return self }

        switch self {
        case .conversation:
            return .conversationWithMute
        case .conversationWithLike:
            return .conversationWithLikeAndMute
        case .conversationUnderEncryptionAtRest:
            return .conversationUnderEncryptionAtRestWithMute
        default:
            return self
        }
    }

    func addEncryptionAtRestIfNeeded(encryptionAtRestEnabled: Bool) -> Self {
        guard encryptionAtRestEnabled else { return self }

        switch self {
        case .conversation, .conversationWithLike:
            return .conversationUnderEncryptionAtRest
        case .conversationWithMute, .conversationWithLikeAndMute:
            return .conversationUnderEncryptionAtRestWithMute
        default:
            return self
        }
    }
}
