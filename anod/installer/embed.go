// Package installer holds the AnoShell install and uninstall scripts. They are
// the canonical implementation (plain bash, served by the docs site as
// `curl … | bash`); `ano setup` embeds them so its wizard runs the exact
// version it shipped with.
package installer

import (
	_ "embed"
)

//go:embed install.sh
var Install []byte

//go:embed uninstall.sh
var Uninstall []byte
