# Contributing

## Checks

Run these before sending a change; each exits non-zero on a problem.

| Command | Checks |
|---|---|
| `python3 scripts/dev/settings-audit.py` | every setting written is declared and read; the Settings search index is current (`scripts/dev/settings-index.py` regenerates it) |
| `bash scripts/dev/lint-compositor.sh` | nothing outside `services/compositor/` talks to a compositor directly (see its `BackendContract.md`) |
| `bash scripts/dev/lint-motion.sh` | animations use the motion tokens, not literal durations or Qt easings |
| `bash scripts/dev/look-coverage.sh` | colours come from the theme |

Tests (no shell needed):

```sh
node scripts/dev/test-frame-geometry.js   # connected frame slot packing
node scripts/dev/test-bar-layout.js       # bar forms and groups
node scripts/dev/test-wallpaper-deck.js
node scripts/dev/test-generic-model.js    # compositor backends' parsing
node scripts/dev/test-sway-model.js
node scripts/dev/test-mango-model.js
node scripts/dev/test-umbriel-model.js
node scripts/dev/test-pieces-logic.js     # world clock zones, palette layout
cd anod && go vet ./... && go test ./...
```

## Running a test shell

Run a second shell against its own config so your real one is never touched:

```sh
T=$(mktemp -d)                 # absolute: a relative XDG path is ignored
mkdir -p $T/config $T/state $T/data
ln -s ~/.config/quickshell $T/config/quickshell
XDG_CONFIG_HOME=$T/config XDG_STATE_HOME=$T/state XDG_DATA_HOME=$T/data \
  GSETTINGS_BACKEND=keyfile qs -c ano
```

Every XDG path must be absolute: Qt and GLib ignore a relative one and fall
back to `~/.config`. A first start also adopts the AnoShell icon theme and
cursor through `gsettings`; put a no-op `gsettings` first on `PATH` (or set
`icons.adopted` and `cursor.adopted` in the test config) to keep it off your
desktop. Stop a test shell by its PID, not `pkill -f "qs -c ano"` (which
matches more than you mean).

`scripts/dev/budget.sh` measures a running shell's idle CPU and memory, and
`scripts/dev/idle-profile.sh` shows which QML keeps it busy.

## Conventions

- **Motion:** pick a `MotionSpring` token from the Behavior's `targetValue`,
  not from the state that drives the value (the Behavior starts first, so a
  state binding runs each move on the previous direction's curve):
  `Behavior on shown { id: m; MotionSpring { token: m.targetValue > 0.5 ? "liquid" : "settle" } }`.
- **Connected mode:** a surface that fuses into the frame publishes its body
  through a `ConnectedSurfaceLease` and draws no border, shadow or elevation
  of its own; it animates out of the edge it belongs to.
- **Compositors:** go through `CompositorService`; a new capability goes into
  the backend contract with a `false`/`null` answer on backends without it.
- **Dependencies:** a feature that needs a binary gets a row in the README's
  dependency map and a check in `ano doctor`, and must not spawn the binary
  unless it is installed and the feature is on.
- **Hidden surfaces:** a surface revealed by hovering an edge keeps an input
  strip on that edge while hidden (its own content has slid out of the window).

Commit messages say what changed and why, in plain sentences.
