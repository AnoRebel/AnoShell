pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Polkit
import qs.modules.common

/**
 * The shell's polkit authentication agent: asks for the password when an app
 * needs permission (pkexec, mounting, system settings). The prompt is
 * modules/polkit/PolkitPrompt.qml.
 *
 * polkit takes one agent per session, so when another (hyprpolkitagent,
 * polkit-gnome…) is already registered this one never asks; `registered`
 * says which won, and Settings shows it. Nothing here stops other agents.
 * `retry()` registers again once the other one is gone.
 */
Singleton {
    id: root

    readonly property bool wanted: Config.options?.polkit?.enable ?? true
    // Off for a turn while retry() drops a refused registration.
    property bool _resting: false

    LazyLoader {
        id: agentLoader
        active: root.wanted && !root._resting
        PolkitAgent {}
    }

    readonly property var agent: agentLoader.item
    readonly property bool registered: root.agent?.isRegistered ?? false
    readonly property var flow: root.agent?.flow ?? null
    readonly property bool asking: root.agent?.isActive ?? false
    // Wanted but not registered a few seconds on: another agent holds the session.
    property bool otherAgent: false
    Timer {
        running: root.wanted && !root.registered
        interval: 4000
        onTriggered: root.otherAgent = !root.registered
    }
    onRegisteredChanged: if (root.registered) root.otherAgent = false

    function submit(password) {
        if (root.flow?.isResponseRequired) root.flow.submit(password)
    }
    // Closing the prompt answers "no" instead of leaving the app to time out.
    function cancel() {
        if (root.flow && !root.flow.isCompleted) root.flow.cancelAuthenticationRequest()
    }
    // polkit notices another agent is gone a moment after its process: a few
    // tries, a second apart.
    function retry() {
        if (!root.wanted || root.registered) return
        retryTimer.tries = 5
        retryTimer.restart()
    }
    Timer {
        id: retryTimer
        property int tries: 0
        interval: 1000
        repeat: true
        onTriggered: {
            if (root.registered || tries <= 0) { stop(); return }
            tries--
            root._resting = true
            Qt.callLater(() => root._resting = false)
        }
    }
}
