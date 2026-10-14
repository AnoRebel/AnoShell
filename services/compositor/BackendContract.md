# Compositor backend contract

`services/CompositorService.qml` is the only compositor API the UI uses. It loads one
backend from this directory and forwards to it. Nothing outside `services/compositor/`
(and `services/NiriService.qml`, the niri IPC client the niri backend wraps) may import
`Quickshell.Hyprland`, run `hyprctl`, or run `niri msg`. `scripts/dev/lint-compositor.sh`
enforces this.

## Selection

`CompositorService` picks the backend from `compositor.backend` in config if it is set,
otherwise from the environment:

| Variable | Backend |
|---|---|
| `HYPRLAND_INSTANCE_SIGNATURE` | `hyprland` |
| `NIRI_SOCKET` | `niri` |
| anything else | `generic` |

## Properties every backend provides

| Property | Type | Meaning |
|---|---|---|
| `name` | string | `hyprland`, `niri`, `generic`, … |
| `experimental` | bool | shown as a badge in Settings and `ano doctor` |
| `supports` | object | capability flags, listed below |
| `focusedOutput` | string | name of the focused output |
| `activeWorkspaceNumber` | int | 1-based number of the focused workspace on the focused output |
| `activeWorkspaceName` | string | its name (may be empty) |
| `workspaces` | array | `{ id, number, name, output, focused, active, occupied, urgent }` |
| `fullscreenOutputs` | object | `{ outputName: true }` for outputs showing a fullscreen window |
| `revision` | int | bumped whenever workspaces or fullscreen state change |
| `keyboardLayout` | string | current layout name |
| `keyboardLayouts` | array | all layout names |

`supports` flags: `workspaces`, `windowCapture`, `blurProtocol`, `layerBlurRules`,
`outerGaps`, `cursorZoom`, `dpms`, `outputConfig`, `exit`, `keyboardLayouts`.

## Functions

| Function | Notes |
|---|---|
| `focusWorkspace(number)` | absolute, 1-based, on the focused output |
| `focusWorkspaceRelative(delta)` | `+1` / `-1` |
| `exit()` | end the session |
| `powerOffMonitors()` / `powerOnMonitors()` | DPMS |
| `setOuterGaps(px)` | runtime only |
| `setLayerBlur(namespaceRegex, enabled, ignoreAlpha)` | layer-rule fallback where `ext-background-effect-v1` is missing |
| `setCursorZoom(factor)` | |
| `switchKeyboardLayout(delta)` | |

Unsupported operations return `false` and log once; they never throw.

## Windows

Windows are Quickshell `Toplevel` objects (`ToplevelManager.toplevels`). Focus and close
go through `Toplevel.activate()` / `Toplevel.close()` (foreign-toplevel protocol), which
work on every supported compositor, so backends do not reimplement them.
`CompositorService.sortedToplevels` (leased via `setSortingConsumer`) orders them by
output, then workspace, then position.
