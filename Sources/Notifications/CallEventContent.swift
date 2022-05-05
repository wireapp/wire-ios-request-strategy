//
// Wire
// Copyright (C) 2022 Wire Swiss GmbH
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

public struct CallEventContent: Decodable {

    // MARK: - Properties

    /// Call event type.

    let type: String

    /// Properties containing info whether the incoming call has video or not.

    let props: Properties?

    /// Caller Id.

    let src_userid: String

    let resp: Bool

    // MARK: - Life cycle

    public init?(from data: Data, with decoder: JSONDecoder = .init()) {
        do {
            self = try decoder.decode(Self.self, from: data)
        } catch let error {
            print(error.localizedDescription)
            return nil
        }
    }

    // MARK: - Methods

    public var callerID: UUID? {
        return UUID(uuidString: src_userid)
    }

    public var callState: LocalNotificationType.CallState? {
        if isStartCall && !resp {
            return .incomingCall(video: props?.isVideo ?? false)
        } else if isEndCall {
            return .missedCall(cancelled: true)
        } else {
            return nil
        }
    }

    public var isStartCall: Bool {
        return type.isOne(of: ["SETUP", "GROUPSTART", "CONFSTART"])
    }

    public var isEndCall: Bool {
        return type == "CANCEL"
    }

    public var isRemoteMute: Bool {
        return type == "REMOTEMUTE"
    }

}

extension CallEventContent {

    struct Properties: Decodable {

        private let videosend: String

        var isVideo: Bool {
            return videosend == "true"
        }
    }

}
