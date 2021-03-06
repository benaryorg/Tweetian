/*
    Copyright (C) 2012 Dickson Leong
    This file is part of Tweetian.

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program. If not, see <http://www.gnu.org/licenses/>.
*/

import QtQuick 2.1
import Sailfish.Silica 1.0
import "../Utils/Calculations.js" as Calculate
import "../Utils/Database.js" as Database
import "../Component"
import "../Delegate"
import "../Services/Twitter.js" as Twitter
import "../TweetPageJS.js" as JS

Item {
    id: root
    height: mainView.height; width: mainView.width

    property string type //"Timeline" or "Mentions"

    property ListModel model: tweetView.model // strictly read-only

    property bool busy: true
    property int unreadCount: 0

    property string reloadType: "all" //"older", "newer" or "all"
    property bool active: Qt.application.active && mainPage.status === PageStatus.Active &&
                          mainView.currentIndex === (type === "Timeline" ? 0 : 1)

    function initialize() {
        var msg = {
            type: "database",
            data: (type === "Timeline" ? Database.getTimeline() : Database.getMentions()),
            model: tweetView.model
        }
        tweetParser.sendMessage(msg)
        busy = true
        if (type === "Timeline") tweetView.lastUpdate = Database.getSetting("timelineLastUpdate")
        else tweetView.lastUpdate = Database.getSetting("mentionsLastUpdate")
    }

    function refresh(type) {
        if (tweetView.count <= 0)
            type = "all";
        var sinceId = "", maxId = "";
        switch (type) {
        case "newer": sinceId = tweetView.model.get(0).id; break;
        case "older": maxId = tweetView.model.get(tweetView.count - 1).id; break;
        case "all": tweetView.model.clear(); break;
        default: throw new Error("Invalid type");
        }
        reloadType = type
        if (root.type == "Timeline") Twitter.getHomeTimeline(sinceId, Calculate.minusOne(maxId), internal.successCallback, internal.failureCallback)
        else Twitter.getMentions(sinceId, Calculate.minusOne(maxId), internal.successCallback, internal.failureCallback)
        busy = true
    }

    function positionAtTop() {
        tweetView.positionViewAtBeginning();
        root.unreadCount = 0;
    }

    function prependNewTweets(tweetsJson) {
        var msg = {
            type: "newer",
            data: tweetsJson,
            model: tweetView.model,
            muteString: (type === "Timeline" ? settings.muteString : "")
        }
        tweetParser.sendMessage(msg)
        tweetView.lastUpdate = new Date().toString()
    }

    function favouriteTweet(id) {
        var msg = {
            type: "favourite",
            id: id,
            model: tweetView.model
        }
        tweetParser.sendMessage(msg)
    }

    function removeTweet(id) {
        var msg = {
            type: "remove",
            id: id,
            model: tweetView.model
        }
        tweetParser.sendMessage(msg)
    }

    function removeAllTweet() {
        var msg = {
            type: "all",
            data: [],
            model: tweetView.model
        }
        tweetParser.sendMessage(msg)
    }

    onUnreadCountChanged: {
        if (unreadCount === 0 && type === "Mentions") harmattanUtils.clearNotification("tweetian.mention")
    }

    SilicaListView {
        id: tweetView
        property string lastUpdate: ""
        property int lastCount: 0
        property Item contextMenu

        PullDownMenu {
            busy: root.busy
            MenuItem {
               visible: !pendingTweet
               onClicked: pageStack.push(Qt.resolvedUrl("../NewTweetPage.qml"), {type: "New"})
               text: qsTr("New Tweet")
            }
            MenuItem {
               enabled: !userStream.connected
               onClicked: if (!userStream.connected) refresh("newer")
               text: userStream.connected ? qsTr("Streaming...") : qsTr("Refresh")
            }
        }

        property bool stayAtCurrentPosition: (userStream.connected && !active) ||
                                             (!userStream.connected && reloadType === "newer")

        anchors.fill: parent
        model: ListModel {}
        section.property: "timeDiff" // for FastScroll
        delegate: TweetDelegate {}
        header: Item { height: Theme.paddingSmall; width: 1 }
        footer: LoadMoreButton {
            visible: tweetView.count > 0
            enabled: !busy
            onClicked: refresh("older")
        }
       // onPulledDown: if (userStream.status === 0) refresh("newer")
        onContentYChanged: refreshUnreadCountTimer.running = true
        onCountChanged: {
            if (lastCount && settings.keepPosition) {
                /* Move to one item before newer items */
                positionViewAtIndex(count - lastCount, ListView.Center);
            }

            lastCount = count;
        }

        Timer {
            id: refreshUnreadCountTimer
            interval: 250
            repeat: false
            onTriggered: root.unreadCount = Math.min(tweetView.indexAt(0, tweetView.contentY + 5), root.unreadCount)
        }

        IconButton {
            id: toTop
            visible: opacity != 0.0
            opacity: 0.0
            z: 1
            y: Theme.paddingLarge
//            y: Screen.height * 0.40 // middle of screen
            x: Screen.width - width - Theme.paddingLarge
            width: 120
            height: 120
            icon.source: "qrc:/icons/icon-ll-up.png";
            onClicked: {
                // for someuknown reason we don't get onFlickEnded when doing this so we  turn on
                // timer here to make sure button dissapears after 500ms
                // Since setting opacity 0.0 fails, we also prevent interactive scroll when call move to top
                timerVisibleFor.start()
                tweetView.interactive = false;
                // this seems work better than scrollToTop()
                tweetView.positionViewAtIndex(0, ListView.Top);
                tweetView.interactive = true;
            }

            Behavior on opacity {
                FadeAnimation {}
            }
        }

        IconButton {
            id: toBottom
            visible: opacity != 0.0
            opacity: 0.0
            z: 1
            y: Theme.paddingLarge
//            y: Screen.height * 0.40  // middle of screen
            x: Screen.width - width - Theme.paddingLarge
            width: 120
            height: 120
            icon.rotation: 180
            icon.source: "qrc:/icons/icon-ll-up.png";
            onClicked: {
                // for someuknown reason we don't get onFlickEnded when doing this so we  turn on
                // timer here to make sure button dissapears after 500ms
                // Since setting opcity 0.0 fails
                timerVisibleFor.start()
                tweetView.interactive = false;
                tweetView.positionViewAtEnd()
                tweetView.interactive = true;
            }

            Behavior on opacity {
                FadeAnimation {}
            }
        }

        Timer {
            id: timerVisibleFor
            repeat: false
            running: false
            interval: 500
            onTriggered: { toTop.opacity = 0.0; toBottom.opacity = 0.0; }
        }

        VerticalScrollDecorator {
            flickable: tweetView;
        }

        onFlickStarted: {
            if (!tweetView.hasOwnProperty("quickScroll") || !tweetView.quickScroll) {
	            if (verticalVelocity < 0)
	            {
	                toBottom.opacity = 0.0;
	                toTop.opacity = 1.0;
	            }
	            else
	            {
	                toTop.opacity = 0.0;
	                toBottom.opacity = 1.0;
	            }
	        }
        }
        onFlickEnded: {
        	if (toTop.visible || toBottom.visible)
        		timerVisibleFor.start()
        }
    }

    // Timer used for refresh the timestamp of every tweet every minute. triggeredOnStart is set to true
    // so that the timestamp is refreshed when the app is switch from background to foreground.
    Timer {
        interval: 60000 // 1 minute
        repeat: true
        running: window.applicationActive
        triggeredOnStart: true
        onTriggered: internal.refreshTimeDiff()
    }

    Timer {
        id: autoRefreshTimer
        interval: settings.autoRefreshInterval * 60000
        running: networkMonitor.online && !settings.enableStreaming
        repeat: true
        onTriggered: refresh("newer")
    }

    WorkerScript {
        id: tweetParser
        source: "../WorkerScript/TweetsParser.js"
        onMessage: internal.onParseComplete(messageObject)
    }

    QtObject {
        id: internal

        function refreshTimeDiff() {
            if (tweetView.count <= 0) return;
            var msg = { type: "time", model: tweetView.model }
            tweetParser.sendMessage(msg)
        }

        function successCallback(data) {
            var msg = {
                type: reloadType,
                data: data,
                model: tweetView.model,
                muteString: (type === "Timeline" ? settings.muteString : "")
            }
            tweetParser.sendMessage(msg);
            if (reloadType == "newer" || reloadType == "all") {
                tweetView.lastUpdate = new Date().toString()
                if (autoRefreshTimer.running) autoRefreshTimer.restart()
            }
        }

        function failureCallback(status, statusText) {
            infoBanner.showHttpError(status, statusText)
            busy = false
        }

        function onParseComplete(msg) {
            switch (msg.type) {
            case "newer":
                __createNotification(msg.newTweetCount);
                // fallthrough
            case "all": case "older":
                cache.storeScreenNames(msg.screenNames);
                busy = false;
                break;
            case "database":
                refresh("newer");
                break;
            }
            cache.storeHashtags(msg.hashtags)
        }

        function __createNotification(newTweetCount) {
            if (newTweetCount <= 0) return;

            if (tweetView.stayAtCurrentPosition || tweetView.indexAt(0, tweetView.contentY) > 0)
                unreadCount += newTweetCount;

            if (type !== "Mentions") return;

            var body = qsTr("%n new mention(s)", "", unreadCount)
            if (Qt.application.active) {
                if (mainPage.status !== PageStatus.Active)
                    infoBanner.showText(body);
            }
            else {
                if (settings.enableNotification) {
                    harmattanUtils.clearNotification("tweetian.mention")
                    harmattanUtils.publishNotification("tweetian.mention", "Tweetian", body, unreadCount)
                }
            }
        }
    }

    Component.onDestruction: {
        if (type === "Timeline") {
            Database.setSetting({"timelineLastUpdate": tweetView.lastUpdate})
            Database.storeTimeline(tweetView.model);
        }
        else {
            Database.setSetting({"mentionsLastUpdate": tweetView.lastUpdate})
            Database.storeMentions(tweetView.model);
        }
    }
}
