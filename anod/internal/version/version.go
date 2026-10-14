// Package version holds the anod release and wire-protocol versions.
package version

// Version is the anod/ano release, overridable at build time with
// -ldflags "-X ano/anod/internal/version.Version=...".
var Version = "0.1.0"

// API is the socket protocol version. Bump it on any incompatible change to
// request, response or event shapes; clients send it as "v" on every request.
const API = 1
