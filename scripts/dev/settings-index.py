#!/usr/bin/env python3
"""settings-index.py — build modules/settings/settings-index.json for the Ctrl+K palette.

usage: settings-index.py [--check]

Parses each Settings page and records, for every SettingsCard (title, subtitle,
configKeys) and every control inside it (label/sublabel + the keys it writes via
Config.setNestedValue), an entry {page, card, label, sublabel, keys}. The palette
adds these words to each key's search text, so controls are found by their label.
--check exits 1 if the committed index is stale (run from the settings audit).
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SETTINGS = ROOT / "modules/settings"
OUT = SETTINGS / "settings-index.json"
# Page order = SettingsRegistry.pages order.
PAGES = ["GeneralConfig", "ModulesConfig", "BarConfig", "DockConfig", "SidebarsConfig",
         "AnoSpotConfig", "AppearanceConfig", "OverviewConfig", "ServicesConfig", "DisplaysPage",
         "KeybindsPage", "AboutPage"]
# Cards kept in their own files, indexed with the page that shows them.
EXTRA = {"DisplaysPage": ["CursorCard"], "AboutPage": ["PresetsCard"]}
ADVANCED_RE = re.compile(r"^\s*advanced\s*:\s*true\b", re.M)

STR = r'"((?:\\.|[^"\\])*)"'
OBJ_RE = re.compile(r"\b([A-Z][A-Za-z0-9_]*)\s*\{")
PROP_STR_RE = re.compile(r"^\s*(label|sublabel|title|subtitle)\s*:\s*(.*)$", re.M)
WRITE_RE = re.compile(r'setNestedValue\(\s*"([A-Za-z0-9_.]+)"|setNestedValue\(\s*`([A-Za-z0-9_.]*)\$\{')
KEYS_RE = re.compile(r"configKeys\s*:\s*\[([^\]]*)\]")


def strip_comments(src):
    return re.sub(r"(?m)^\s*//.*$|(?<=[;{}\s])//[^\n\"]*$", "", src)


def blocks(src):
    """Yield (type, body) for every `Type { ... }` object, outermost first."""
    for m in OBJ_RE.finditer(src):
        i, depth = m.end(), 1
        while i < len(src) and depth:
            c = src[i]
            if c == '"':
                j = src.find('"', i + 1)
                while j > 0 and src[j - 1] == "\\":
                    j = src.find('"', j + 1)
                i = j if j > 0 else len(src)
            elif c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
            i += 1
        yield m.group(1), src[m.end():i - 1]


def own_props(body):
    """String props defined directly in this block (not in nested objects)."""
    flat, depth = [], 0
    for line in body.split("\n"):
        if depth == 0:
            flat.append(line)
        depth += line.count("{") - line.count("}")
    out = {}
    for name, rhs in PROP_STR_RE.findall("\n".join(flat)):
        lits = re.findall(STR, rhs)
        if lits:  # first literal: plain text or the main branch of a ternary
            out.setdefault(name, lits[-1] if "?" in rhs and len(lits) > 1 and "overrideNote" in rhs else lits[0])
    return out


def own_body(body):
    """The lines of a block outside its nested objects."""
    flat, depth = [], 0
    for line in body.split("\n"):
        if depth == 0:
            flat.append(line)
        depth += line.count("{") - line.count("}")
    return "\n".join(flat)


def keys_written(body):
    return sorted({a or b.rstrip(".") for a, b in WRITE_RE.findall(body)} - {""})


CARD_USE_RE = re.compile(r"\b([A-Z][A-Za-z0-9_]*Card)\s*\{")


def page_source(name):
    """A page's QML plus the card files it places (`IconsCard {}`), and theirs."""
    seen, out, todo = set(), [], [name] + EXTRA.get(name, [])
    while todo:
        n = todo.pop(0)
        f = SETTINGS / f"{n}.qml"
        if n in seen or not f.exists():
            continue
        seen.add(n)
        src = strip_comments(f.read_text())
        out.append(src)
        todo += [c for c in CARD_USE_RE.findall(src) if c != "SettingsCard"]
    return "\n".join(out)


def build():
    entries = []
    for idx, name in enumerate(PAGES):
        src = page_source(name)
        adv_keys = set()
        for typ, body in blocks(src):
            if typ == "SettingsCard" and ADVANCED_RE.search(own_body(body)):
                ck = KEYS_RE.search(body)
                adv_keys |= set(re.findall(STR, ck.group(1)) if ck else keys_written(body)) | set(keys_written(body))
        for typ, body in blocks(src):
            props = own_props(body)
            if typ == "SettingsCard":
                ck = KEYS_RE.search(body)
                keys = re.findall(STR, ck.group(1)) if ck else keys_written(body)
                if props.get("title"):
                    e = {"page": idx, "card": props["title"], "label": props["title"],
                         "sublabel": props.get("subtitle", ""), "keys": keys}
                    if ADVANCED_RE.search(own_body(body)):
                        e["advanced"] = True
                    entries.append(e)
            elif "label" in props:
                keys = keys_written(body)
                if keys:
                    e = {"page": idx, "card": "", "label": props["label"],
                         "sublabel": props.get("sublabel", ""), "keys": keys}
                    if set(keys) <= adv_keys:
                        e["advanced"] = True
                    entries.append(e)
    return entries


def main(argv):
    text = json.dumps(build(), indent=1, ensure_ascii=False) + "\n"
    if "--check" in argv:
        current = OUT.read_text() if OUT.exists() else ""
        if current != text:
            print("settings-index.json is stale: run scripts/dev/settings-index.py")
            return 1
        return 0
    OUT.write_text(text)
    print(f"wrote {OUT.relative_to(ROOT)} ({text.count('\"label\"')} entries)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
