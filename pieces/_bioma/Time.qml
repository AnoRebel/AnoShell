pragma Singleton

import QtQuick
import Quickshell
import qs.services as Ano

// Bioma's Time for the ported clock organism: its running timer is
// AnoShell's countdown (services/Pomodoro), shared with the timer piece.
Singleton {
    readonly property bool running: Ano.Pomodoro.cdRunning
    readonly property real fractionLeft: Ano.Pomodoro.cdLength > 0 ? Ano.Pomodoro.cdLeft / (Ano.Pomodoro.cdLength * 1000) : 0
}
