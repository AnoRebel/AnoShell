#!/usr/bin/env python3
"""export-schema.py — Config.qml → anod/internal/config/schema.json.

usage: export-schema.py [--check]
  --check  exit 1 if the committed schema.json is stale (run in each wave's audit)

The schema maps every leaf key to its QML type and lists the JsonObject paths;
anod embeds it for `ano config validate` and `ano doctor`.
"""
import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "anod/internal/config/schema.json"

spec = importlib.util.spec_from_file_location("audit", Path(__file__).with_name("settings-audit.py"))
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)

types = {}
_, objects = audit.parse_schema(ROOT / "modules/common/Config.qml", types)
text = json.dumps({"leaves": dict(sorted(types.items())), "objects": sorted(objects)}, indent=1) + "\n"

if "--check" in sys.argv:
    if not OUT.exists() or OUT.read_text() != text:
        print("schema.json is stale: run scripts/dev/export-schema.py", file=sys.stderr)
        sys.exit(1)
    sys.exit(0)
OUT.write_text(text)
print(f"wrote {OUT.relative_to(ROOT)}: {len(types)} keys, {len(objects)} objects")
