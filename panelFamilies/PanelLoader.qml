import QtQuick
import Quickshell
import qs.modules.common

/**
 * PanelLoader — LazyLoader gated by Config.ready and an optional extra condition.
 * Used by panel family definitions to conditionally load modules.
 */
LazyLoader {
    property bool extraCondition: true
    active: Config.ready && extraCondition
}
