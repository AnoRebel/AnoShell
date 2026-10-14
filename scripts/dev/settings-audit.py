#!/usr/bin/env python3
"""settings-audit.py — cross-check ano's config schema, bundled config, Settings
UI writes and runtime reads.

usage: settings-audit.py [--json] [--verbose]

Sources:
  schema   modules/common/Config.qml (JsonObject tree inside the JsonAdapter)
  bundled  config.json
  written  Config.setNestedValue("…") / `prefix.${…}` / configKeys in the Settings UI
  read     Config.options?.a?.b chains in runtime code (everything outside modules/settings/)

A read of an object path (chain ending at a JsonObject) counts as reading every key
under it, because the code may then access the keys through a local alias.

Exit status is 1 when any blocking category is non-empty:
  written-not-read, read-not-declared, written-not-declared, bundled-not-declared.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # ano/
SETTINGS_DIRS = ("modules/settings/",)
SETTINGS_FILES = ("settings.qml",)

PROP_RE = re.compile(r"\bproperty\s+([\w<>]+)\s+(\w+)\s*:")
STR_RE = re.compile(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|`(?:\\.|[^`\\])*`')
READ_RE = re.compile(r"\bConfig\??\.options((?:\??\.[A-Za-z_]\w*)+)")
WRITE_LIT_RE = re.compile(r'setNestedValue\(\s*"([A-Za-z0-9_.]+)"')
WRITE_TPL_RE = re.compile(r"setNestedValue\(\s*`([A-Za-z0-9_.]*)\$\{")
CONFIGKEYS_RE = re.compile(r"configKeys\s*:\s*\[([^\]]*)\]")


def strip_comments(src: str) -> str:
    """Drop // and /* */ comments, keeping strings intact (good enough for QML)."""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c in "\"'`":
            m = STR_RE.match(src, i)
            if m:
                out.append(m.group(0)); i = m.end(); continue
        if src.startswith("//", i):
            j = src.find("\n", i); i = n if j < 0 else j; continue
        if src.startswith("/*", i):
            j = src.find("*/", i + 2); i = n if j < 0 else j + 2; continue
        out.append(c); i += 1
    return "".join(out)


def parse_schema(path: Path):
    """Return (leaves, objects): dotted leaf keys and dotted JsonObject paths."""
    src = strip_comments(path.read_text())
    start = re.search(r"\bJsonAdapter\s*\{", src).end() - 1
    body = STR_RE.sub('""', src[start + 1:])
    leaves, objects = set(), set()
    stack = []          # names of open JsonObjects
    open_at = []        # brace depth at which each JsonObject opened
    depth = 0
    pending_obj = None  # JsonObject name waiting for its "{"
    i = 0
    for m in re.finditer(r"\bproperty\s+[\w<>]+\s+\w+\s*:|[{}]", body):
        tok = m.group(0)
        if tok == "{":
            depth += 1
            if pending_obj is not None:
                stack.append(pending_obj); open_at.append(depth); pending_obj = None
        elif tok == "}":
            if open_at and open_at[-1] == depth:
                stack.pop(); open_at.pop()
            depth -= 1
            if depth < 0:
                break  # end of JsonAdapter
        else:
            ptype, pname = PROP_RE.match(tok).groups()
            # Only properties declared directly inside the adapter / a JsonObject.
            expected = open_at[-1] if open_at else 0
            if depth != expected:
                continue
            key = ".".join(stack + [pname])
            if ptype == "JsonObject":
                objects.add(key); pending_obj = pname
            else:
                leaves.add(key)
        i = m.end()
    return leaves, objects


def flatten_json(obj, prefix=""):
    keys = set()
    if isinstance(obj, dict):
        for k, v in obj.items():
            p = f"{prefix}.{k}" if prefix else k
            if isinstance(v, dict) and v:
                keys |= flatten_json(v, p)
            else:
                keys.add(p)
    return keys


def qml_files():
    for p in ROOT.rglob("*.qml"):
        rel = p.relative_to(ROOT).as_posix()
        if rel.startswith(("external/", ".backups/")):
            continue
        yield rel, p


def is_settings(rel: str) -> bool:
    return rel.startswith(SETTINGS_DIRS) or rel in SETTINGS_FILES


def collect():
    reads, writes, write_prefixes, unresolved = {}, {}, {}, []
    for rel, p in qml_files():
        src = strip_comments(p.read_text(errors="replace"))
        if not is_settings(rel):
            for m in READ_RE.finditer(src):
                key = re.sub(r"\?", "", m.group(1)).lstrip(".")
                reads.setdefault(key, set()).add(rel)
        if rel == "modules/common/PanelGate.qml":  # feature keys read via _keyValue(path)
            for m in re.finditer(r'\bkey:\s*"([A-Za-z0-9_.]+)"', src):
                reads.setdefault(m.group(1), set()).add(rel)
        for m in WRITE_LIT_RE.finditer(src):
            writes.setdefault(m.group(1), set()).add(rel)
        for m in WRITE_TPL_RE.finditer(src):
            write_prefixes.setdefault(m.group(1).rstrip("."), set()).add(rel)
        for m in re.finditer(r"setNestedValue\(\s*([A-Za-z_][\w.]*)\s*,", src):
            unresolved.append(f"{rel}: setNestedValue({m.group(1)}, …)")
        if is_settings(rel):
            for m in CONFIGKEYS_RE.finditer(src):
                for k in re.findall(r'"([A-Za-z0-9_.]+)"', m.group(1)):
                    writes.setdefault(k, set()).add(rel + " (configKeys)")
    return reads, writes, write_prefixes, unresolved


def covered(key, keyset):
    """True if key or any ancestor of key is in keyset."""
    parts = key.split(".")
    return any(".".join(parts[:i]) in keyset for i in range(1, len(parts) + 1))


def has_descendant(key, keyset):
    return any(k.startswith(key + ".") for k in keyset)


def main(argv):
    as_json, verbose = "--json" in argv, "--verbose" in argv
    leaves, objects = parse_schema(ROOT / "modules/common/Config.qml")
    declared = leaves | objects
    bundled = flatten_json(json.loads((ROOT / "config.json").read_text()))
    reads, writes, wprefix, unresolved = collect()
    read_keys = set(reads)

    def is_read(k):
        return covered(k, read_keys) or has_descendant(k, read_keys)

    def is_declared(k):
        # Keys under a `var`/array leaf (e.g. bars.0.edge, maps) count as declared.
        return k in declared or covered(k, leaves) or has_descendant(k, declared)

    report = {
        "written-not-read": sorted(k for k in writes if not is_read(k)),
        "written-prefix-not-read": sorted(k for k in wprefix if not is_read(k)),
        "written-not-declared": sorted(k for k in writes if not is_declared(k)),
        "read-not-declared": sorted(k for k in read_keys if not is_declared(k)),
        "bundled-not-declared": sorted(k for k in bundled if not is_declared(k)),
        "declared-not-read": sorted(k for k in leaves
                                    if not is_read(k) and k not in writes
                                    and not covered(k, set(wprefix))),
    }
    # Name mismatches: an undeclared read whose sibling differs only by a suffix.
    mism = []
    for k in report["read-not-declared"]:
        parent, _, leaf = k.rpartition(".")
        for d in leaves:
            dp, _, dl = d.rpartition(".")
            if dp == parent and dl != leaf and (dl.startswith(leaf) or leaf.startswith(dl)):
                mism.append(f"{k}  (schema has {d})")
    report["name-mismatch"] = sorted(mism)
    report["unresolved-dynamic-writes"] = sorted(unresolved)

    # The palette's label index must match the Settings pages.
    import subprocess
    stale = subprocess.run([sys.executable, "-I", str(ROOT / "scripts/dev/settings-index.py"), "--check"],
                           capture_output=True, text=True).returncode != 0
    report["stale-settings-index"] = ["modules/settings/settings-index.json"] if stale else []

    blocking = ["written-not-read", "written-not-declared",
                "read-not-declared", "bundled-not-declared", "stale-settings-index"]
    if as_json:
        print(json.dumps(report, indent=2))
    else:
        for cat, items in report.items():
            tag = "BLOCK" if cat in blocking else "info"
            print(f"== {cat} [{tag}] ({len(items)})")
            for k in items:
                where = ""
                if verbose:
                    src = writes.get(k) or reads.get(k) or wprefix.get(k) or ()
                    where = f"   <- {', '.join(sorted(src)[:3])}" if src else ""
                print(f"   {k}{where}")
    return 1 if any(report[c] for c in blocking) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
