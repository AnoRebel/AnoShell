# Compositor backend contract

`services/CompositorService.qml` is the only compositor API the UI uses. It loads one
backend from this directory and forwards to it. Nothing outside `services/compositor/`
(and `services/NiriService.qml`, the niri IPC client the niri backend wraps) may import
`Quickshell.Hyprland`, run `hyprctl`, `niri msg` or `umbriel msg`. `scripts/dev/lint-compositor.sh`
enforces this.

## Selection

`CompositorService` picks the backend from `compositor.backend` in config if it is set,
otherwise from the environment:

| Variable | Backend |
|---|---|
| `HYPRLAND_INSTANCE_SIGNATURE` | `hyprland` |
| `NIRI_SOCKET` | `niri` |
| `SWAYSOCK` | `sway` |
| `MANGO_INSTANCE_SIGNATURE` | `mango` |
| `LABWC_PID` | `labwc` |
| `UMBRIEL_SOCKET` | `umbriel` (with `XDG_CURRENT_DESKTOP=umbriel` it is checked first, before Hyprland) |
| anything else | `generic` |

`SwayBackend`, `MangoBackend`, `LabwcBackend` and `UmbrielBackend` extend
`GenericBackend` (ext-workspace, foreign-toplevel) and override what their
compositor's IPC does better; per-backend notes in `docs/compositors.md`.
Their reply parsing lives in `SwayModel.js` / `MangoModel.js` /
`UmbrielModel.js`, tested with node (`scripts/dev/test-sway-model.js`,
`scripts/dev/test-mango-model.js`, `scripts/dev/test-umbriel-model.js`).

## Properties every backend provides

| Property | Type | Meaning |
|---|---|---|
| `name` | string | `hyprland`, `niri`, `generic`, … |
| `experimental` | bool | shown as a badge in Settings and `ano doctor`; only `generic` |
| `supports` | object | capability flags, listed below |
| `focusedOutput` | string | name of the focused output |
| `activeWorkspaceNumber` | int | 1-based number of the focused workspace on the focused output |
| `activeWorkspaceName` | string | its name (may be empty) |
| `workspaces` | array | `{ id, number, name, output, focused, active, occupied, urgent }` |
| `fullscreenOutputs` | object | `{ outputName: true }` for outputs showing a fullscreen window |
| `revision` | int | bumped whenever workspaces or fullscreen state change |
| `keyboardLayout` | string | current layout name |
| `keyboardLayouts` | array | the configured layouts (xkb codes on Hyprland, full names on niri); use for counting/cycling, not display |

`supports` flags: `workspaces`, `perOutputWorkspaces` (numbers restart per output, as on niri), `windowCapture`, `blurProtocol`, `layerBlurRules`,
`outerGaps`, `cursorZoom`, `screenShader`, `dpms`, `outputConfig`, `exit`, `keyboardLayouts`,
`windowGeometry` (windows' x/y are layout coordinates and `reservedOf` is known, so they can be placed on an output's
usable area; Hyprland, sway), `cursorPos` (`cursorPos(cb)`; Hyprland), `windowBlur` (blur behind translucent windows
through window rules in anod's managed file; Hyprland, niri 26.04+), `scrollingLayout` (scrolling.* has an effect:
Hyprland, niri, mango), `infiniteDesktop` (the canvas functions below: Hyprland, niri, sway, mango).

## Functions

| Function | Notes |
|---|---|
| `focusWorkspace(number, outputName?)` | absolute, 1-based; on `outputName` when given (per-output numbering), else the focused output |
| `focusWorkspaceRelative(delta)` | `+1` / `-1` |
| `exit()` | end the session |
| `powerOffMonitors()` / `powerOnMonitors()` | DPMS |
| `setOuterGaps(px)` | runtime only |
| `setLayerBlur(namespaceRegex, enabled, ignoreAlpha)` | layer-rule fallback where `ext-background-effect-v1` is missing |
| `setCursorZoom(factor)` | |
| `setScreenShader(path)` | full-screen GLSL shader; `""` clears |
| `applyOutputs(configs)` | `[{ name, width, height, rate, scale, x, y }]`, x/y `null` = auto; reads `outputs` (backend-native monitor objects) |
| `switchKeyboardLayout(delta)` | |
| `focusedWindowGeometry(cb)` | optional: `cb({x, y, width, height} \| null)` in layout coordinates; Hyprland, sway, mango, umbriel |
| `cursorPos(cb)` | optional: `cb({x, y} \| null)`, the pointer in layout coordinates; Hyprland |
| `reservedOf(outputName)` | optional: `[left, top, right, bottom]` other clients reserve; Hyprland, sway |
| `signal screencast(open, owner, name)` | optional: capture opened/closed (owner `monitor`, `window`, region); Hyprland |
| `canvasState(cb)` | infinite desktop (`supports.infiniteDesktop`): `cb({ workspace, output, view, others, windows: [{ id, x, y, width, height, floating, focused, appId }] } \| null)` for the focused output's workspace; `view` its usable area, `others` the other outputs; layout coordinates. Hyprland, niri, sway, mango |
| `floatWindows(rects)` / `placeWindows(list)` / `tileWindows(ids)` | float at `{id, x, y, width, height}`, move to `{id, x, y}` (absolute), tile again. Hyprland: one `eval` each, moves coalesced (newest wins while one is in flight); niri: floating positions relative to the working area, learnt from where a window lands; mango: moves go relative (`movewin` reads a leading `-` as relative) |
| `signal windowOpened(id, workspace)` | a new window (workspace may be `""`); Hyprland, niri, sway, mango |

Unsupported operations return `false` and log once; they never throw.

## Blur

Surfaces request blur with Quickshell's `BackgroundEffect.blurRegion` when
`supports.blurProtocol` is true (ext-background-effect-v1). The blur then follows
the region's shape, rounded corners included. Verified on Hyprland 0.56.2 with a
probe layer that no blur layer rule matched. niri 26.04 also implements the
protocol. `CompositorService.requestBlur(ns, enabled, ignoreAlpha)` is the
fallback: a no-op where the protocol exists, a layer rule (`setLayerBlur`) where
it doesn't.

## Windows

Windows are Quickshell `Toplevel` objects (`ToplevelManager.toplevels`). Focus and close
go through `Toplevel.activate()` / `Toplevel.close()` (foreign-toplevel protocol), which
work on every supported compositor, so backends do not reimplement them.
`CompositorService.sortedToplevels` (leased via `setSortingConsumer`) orders them by
output, then workspace, then position.
