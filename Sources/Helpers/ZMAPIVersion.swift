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

// MARK: - Current

extension ZMAPIVersion {

    private static let key = "currentAPIVersion"

    /// The API version against which all new backend requests should be made.
    ///
    /// The current version should be the highest value in common between the set
    /// of supported versions of the client (represented by `APIVersion` cases)
    /// and the set of supported versions of the backend (obtainable via `GET /api-version`).
    ///
    /// A `nil` value indicates that no version is selected yet and therefore one
    /// should be (re-)negotiated with the backend.

    public static var current: Self? {
        get {
            let storedValue = UserDefaults.standard.integer(forKey: key)
            return ZMAPIVersion(rawValue: storedValue)
        }

        set {
            UserDefaults.standard.set(newValue?.rawValue, forKey: key)
        }
    }

}

// MARK: - Comparable

extension ZMAPIVersion: Comparable {

    public static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

}
