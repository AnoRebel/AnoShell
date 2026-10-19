# Legacy reader backends (Python fallback)

The Python servers from novelmangareader (GPL-3.0, see `LICENSE.novelmangareader`),
kept as a per-source fallback for anod's Go reader until every Go provider has
passed live verification. Select one with
`reader.providers.<freewebnovel|weebcentral|allanime>.backend: "python"`.

anod starts a server only when its panel opens, on a free port it passes as
`--port N` and `ANO_READER_PORT`, and proxies `/<token>/<kind>/…` to it.
`ANO_READER_IMAGE_BASE` makes the servers' image URLs point back through anod.
They need `flask`, `requests` and (for Cloudflare) `curl_cffi`; set
`reader.python` to a venv's interpreter if those aren't installed system-wide.

Changes from upstream: the port and image base come from the environment.
