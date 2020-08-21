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

typedef NS_OPTIONS(NSUInteger, ZMStrategyConfigurationOption) {
    ZMStrategyConfigurationOptionDoesNotAllowRequests = 0,
    ZMStrategyConfigurationOptionAllowsRequestsWhileUnauthenticated = 1 << 0,
    ZMStrategyConfigurationOptionAllowsRequestsWhileInBackground = 1 << 1,
    ZMStrategyConfigurationOptionAllowsRequestsWhileOnline = 1 << 4,
    ZMStrategyConfigurationOptionAllowsRequestsDuringSlowSync = 1 << 2,
    ZMStrategyConfigurationOptionAllowsRequestsDuringQuickSync = 1 << 3,
    ZMStrategyConfigurationOptionAllowsRequestsDuringNotificationStreamFetch = 1 << 5
};
