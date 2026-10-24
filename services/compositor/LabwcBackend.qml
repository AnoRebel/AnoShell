import QtQuick
import Quickshell

/**
 * labwc backend (experimental; written against labwc 0.20, see
 * BackendContract.md). labwc has no IPC: workspaces and windows come from
 * ext-workspace-v1 and foreign-toplevel like the generic backend, and the
 * session ends with `labwc --exit` (SIGTERM to $LABWC_PID, labwc(1)).
 *
 * A labwc config with a <privilegedInterfaces> block hides every privileged
 * protocol not listed there (labwc-config(5)); docs/compositors.md lists the
 * ones AnoShell needs.
 */
GenericBackend {
    id: root

    name: "labwc"
    supports: ({
        workspaces: true, perOutputWorkspaces: true, windowCapture: false, blurProtocol: false, layerBlurRules: false,
        outerGaps: false, cursorZoom: false, screenShader: false, dpms: false, outputConfig: false, exit: true,
        keyboardLayouts: false
    })

    function exit() { Quickshell.execDetached(["labwc", "--exit"]); return true }
    // labwc --reconfigure (SIGHUP): reloads rc.xml, e.g. after AnoShell edits it.
    function reconfigure() { Quickshell.execDetached(["labwc", "--reconfigure"]); return true }
}
