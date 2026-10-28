# AnoShell architecture

How the shell is put together, and the Quickshell 0.3 and compositor
constraints that shaped it. For the daemon and the `ano` CLI, see
[anod.md](anod.md).

## Layout of the tree

| Path | What lives there |
|---|---|
| `shell.qml` | Entry point. Instantiates every module behind `PanelGate.enabled(id)`. |
| `modules/common/PanelGate.qml` | Decides which modules exist: the active panel family (ano, hefty, clean, minimal), the user's Modules page choices, each module's feature key, `anoSpot.pillOnly`, and compositor support. |
| `modules/common/Config.qml` | Bundled `config.json` plus the user's sparse delta (`~/.config/anoshell/config.json`). |
| `services/` | Singletons: compositor backends, `PanelRegistry`, notifications, audio, … |
| `modules/<feature>/` | One directory per surface (bar, anoScreen, sidebars, dock, anoSpot, …). |
| `shaders/frag/*.frag` → `shaders/qsb/*.qsb` | Fragment shaders, compiled with `qsb` (see below). |
| `anod/` | Go daemon and CLI. |
| `scripts/dev/` | Checks: `test-frame-geometry.js`, `test-bar-layout.js`, `settings-audit.py`, `settings-index.py`, `budget.sh`, `idle-profile.sh`. |

## The connected frame

In Connected mode (`appearance.connectedCorners.enable`) the screen gets a
painted band with rounded inner corners, and every surface that touches an
edge (bar, pill, sidebars, dock, popouts, notifications, OSD, tray menus) is
drawn as part of one continuous shape with concave fillets where it meets the
band.

### Pieces

- **AnoScreen** (`modules/anoScreen/AnoScreen.qml`): one full-screen,
  click-through window per screen on the Top layer. It hosts only the frame
  shader and never any panel content (see the constraints below).
- **ConnectedFrame** (`ConnectedFrame.qml` + `shaders/frag/connected_arc.frag`):
  one `ShaderEffect` that draws the ring and up to **8 slots** as a signed
  distance field. Slots join the ring and each other with a smooth minimum
  (`smin`), whose `k` is the fillet radius.
  With jelly on, each slot also carries a give in pixels: an underdamped
  spring (ported from Ryoku's `BlobRect`) driven by the speed of the slot's
  free edge, which the shader applies as a stretch along the slot's depth,
  anchored at the band. The give is capped at a third of the body's depth, so
  a closing surface takes it along instead of popping. The spring runs on a
  `FrameAnimation` only while something moves.
- **PanelRegistry** (`services/PanelRegistry.qml`): the per-screen list of
  surfaces the frame should draw.
- **ConnectedSurfaceLease** (`modules/common/ConnectedSurfaceLease.qml`): how a
  surface publishes itself.
- **FrameExclusions** (inside AnoScreen): one empty, click-through window per
  edge that reserves the band's thickness on edges no bar reserves, so windows
  don't slide under the band, and there's no double gap under a bar.

### Lease API

A surface declares a lease bound to its *current, animated* geometry in screen
coordinates:

```qml
ConnectedSurfaceLease {
    key: "sidebarLeft:" + screen.name   // unique per surface and screen
    kind: "sidebar"; edge: "left"; priority: 5
    screenName: screen.name
    active: open                        // published only while true
    x: …; y: …; w: …; h: …              // the body right now
    progress: 0..1                      // how far it has grown out of its edge
    detached: false                     // an island: keeps its own near edge, joins by a neck
    neckK: undefined                    // neck smoothing radius for detached surfaces
    surfaceRadius: undefined            // corner radius of the body's far corners
    omitStartConnector: false           // this end is flush with a band/bar:
    omitEndConnector: false             //   fillet into it instead of rounding
    reserve: 0                          // exclusive zone held on that edge
}
```

- Writes coalesce to one per event-loop turn through a Timer owned by the
  lease. Not `Qt.callLater`: a call queued just before the lease is destroyed
  would run on a dead object.
- Each lease **claims** its key and gets an owner token. Only the owner may
  write, each write carries an increasing revision, and stale or foreign
  writes are rejected and counted (`frame selftest` over IPC checks this).
- Entries for screens that disappear are pruned on hotplug.
- **Priority** decides who gets the 8 slots when more surfaces are visible:
  bars 20, bar islands 19, pill 15, popouts and tray menus 10, OSD 9, dock 8,
  notifications 7, sidebars 5.

### Screen coordinates

Layer-shell windows don't know their own screen position, and items map only
to their window. `PanelRegistry` provides:

- `windowOrigin(w)`: where the layer shell places a window, modelled from its
  anchors, margins and the other edges' reserved space (a window centred on an
  edge is centred in the space left by side bars).
- `windowEdge(w)`: the edge a window hugs, from its anchors. It works on the
  C++ `WlrLayershell` that `popup.anchor.window` returns, which lacks QML
  properties such as a bar's `edge`.
- `inset(screen, edge)`: the reserved space on an edge (bars), or the band's
  thickness.

### Slot packing

`modules/anoScreen/ConnectedSurfaceGeometry.js` (checked by
`node scripts/dev/test-frame-geometry.js`) turns each descriptor into a slot:
`rect`, per-corner radii and per-corner `k`.

- An attached surface's near edge is clamped to the band's inner edge.
- Its near corners become concave junctions; its far corners are rounded.
- While a surface grows (`progress < 1`), the junction `k` swells (a
  meniscus).
- Detached surfaces keep their rect and take `neckK` on every corner.
- `fillets()` computes the concave fillet shapes outside the slot rects. The
  blur region includes them, so the whole silhouette is one material.

The ShaderEffect has no array uniforms, so each slot is a `mat4`. Its columns
are rect, radii, k and (active, 0, 0, 0). The matrix is built with
`Qt.matrix4x4`, which takes rows, so packing transposes.

Rebuild the shader after editing it:

```sh
/usr/lib/qt6/bin/qsb --glsl 100es,120,150 --hlsl 50 --msl 12 \
    -o shaders/qsb/connected_arc.frag.qsb shaders/frag/connected_arc.frag
```

### Blur

Where the compositor supports `ext-background-effect-v1`, AnoScreen sets a
`BackgroundEffect.blurRegion` shaped like the silhouette: the ring, each slot
with its own corner radii, and each fillet (a k×k square minus a circle).
Hyprland applies a layer's `ignore_alpha` to protocol blur too, so the frame
sets its layer rule to `ignore_alpha = 0`. Otherwise a translucent frame
(opacity 0.33) falls below the threshold and isn't blurred. The bundled
`hyprland.lua` sets the same rule, because `hyprctl reload` drops rules the
shell added at runtime.

### Gaps and fullscreen

- Connected mode sets the compositor's `gaps_out` to 0 (`manageGaps`). This is
  applied again on every start, since a killed shell never runs its cleanup.
- While a window is fullscreen on a screen, the frame retracts on a spring and
  unmaps, and the bar and pill slide into their edges. The pill comes back
  while you hover a thin strip at its edge.

## Bar forms and groups

- **BarLayout.js** (pure; `node scripts/dev/test-bar-layout.js`):
  - `place()` puts groups along the bar for the form (full, fit, islands,
    notch).
  - `bodies()` cuts the bar body into segments around detached groups
    (islands), using each group's live `sep` (0 attached … 1 island).
  - `neckK()` thins the neck to nothing as an island finishes separating.
- **BarContent:**
  - Renders `bars[i].groups`, or the legacy `modules.{left,center,right}`
    migrated into start/center/end groups.
  - Each group's position and `sep` are springs, and a coalesced relayout
    publishes `bodyRects`.
- **BarWindow:**
  - Connected mode: one lease per body, using 8 fixed lease objects switched
    on and off. An Instantiator would recreate them all when the body count
    changes, and the frame would lose the bar for a frame.
  - Floating mode, anything but a plain strip: the same ConnectedFrame shader
    with no ring (BarSurface).
  - The input mask is the union of the bodies, so gaps click through.
- **BarEdit.js:** shared by Settings and the bar's right-click group menu.
- **BarManager:** keys bars by index, so editing a bar updates its window in
  place and the change animates.

## Motion

`MotionSpring { token: "liquid" | "settle" | "snappy" }` is a SpringAnimation
bound to `Appearance.springs.<token>`:
- **liquid:** growth.
- **settle:** firm retraction.
- **snappy:** small elements.

Springs retarget from their current velocity, so reversing mid-flight never
jumps. Surfaces grow from their own edge, pinned to it, never by sliding in
from off-screen or by fading alone.

## Config writes

`Config.setNestedValue(path, value)` updates memory and the delta file.

- **Arrays:** a path into a top-level array (`bars.0.groups`) is copy-on-write.
  The whole array is cloned, changed and assigned back, live and in the delta.
  Reading an array from the JsonAdapter gives a copy, so changing it in place
  is lost, and saving only the leaf turned the array into `{"0": …}`.
  Older deltas in that shape are merged per index.
- **Arrays may be V4Sequence:** arrays read from a JsonAdapter list property
  are `V4Sequence` wrappers that fail `Array.isArray`; use
  `Config._isArrayLike`.
- **Bindings over config objects:** a new array (from copy-on-write) notifies,
  so bars update live. Memoise anything derived from it that feeds a Repeater
  (see BarContent's `groups`): returning a fresh array on every change makes
  the Repeater rebuild all its delegates. `deltaRevision` bumps only after the
  debounced write.

## Quickshell 0.3 / Qt 6.11 constraints

These have each caused a crash or a silent failure here:

- **Don't attach deep content while a layer surface is being created.** Doing
  so triggers a recursive `refWindow()` segfault (intermittent, worst at cold
  start). Load content in an `asynchronous` Loader that activates one turn
  after the window is ready, as BarWindow and AnoScreen do.
- **The frame window hosts no panel content.** Surfaces keep their own windows
  and publish leases instead.
- **No `Layout.*` together with `anchors`** on the same item.
- **A `Repeater` inside a `Scope` creates nothing.** Use `Variants`.
- **Click-through masks:** `Region { item: null }`. An empty `Region {}`
  covers the whole window.
- **Regions are static children:** declare a fixed set of child Regions bound
  to data (frame slots, fillets, bar bodies) rather than creating them
  dynamically.
- **Don't edit `.qml` files with `sed -i`:** it truncated files here. Use the
  editor or Python.
- **Kill test shells by PID:** never `pkill -f "qs -c ano"`, which matches the
  calling shell too.

## Hyprland 0.56 notes

- **Runtime rules:** set with `hyprctl eval 'hl.layer_rule({…})'` or
  `hl.config({…})`. `keyword` is rejected by the Lua config, and `eval`
  applies to the live session, so never use it to "test" a config file. Use
  `Hyprland --verify-config -c FILE` and `hyprctl getoption`.
- **Layer rules:** the fields are `blur`, `blur_popups`, `ignore_alpha`,
  `xray` (bool), `no_anim`, `animation`, `order` and `dim_around`.
- **Renamed or removed keys:** `ignorealpha` is now `ignore_alpha`, and
  `input_methods:ignorealpha` is now `input_methods_ignorealpha`.
  `dwindle.pseudotile` and `shadow.ignore_window` are gone, and `vfr` is now
  `debug:vfr`.
- **`catchall`:** only valid inside a submap.
