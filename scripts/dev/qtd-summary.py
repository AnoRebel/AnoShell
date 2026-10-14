#!/usr/bin/env python3
"""qtd-summary.py TRACE.qtd [SKIP_SECONDS] — QML events by source, after SKIP seconds."""
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict

path, skip_ns = sys.argv[1], float(sys.argv[2] if len(sys.argv) > 2 else 0) * 1e9
events, count, total = {}, defaultdict(int), defaultdict(int)
t0 = None
for _, el in ET.iterparse(path, events=("end",)):
    if el.tag == "event":
        f = (el.findtext("filename") or "").split("/ano/")[-1].split("/qs/")[-1]
        events[el.get("index")] = (el.findtext("type") or "", f"{f}:{el.findtext('line') or ''}", (el.findtext("details") or "")[:50])
        el.clear()
    elif el.tag == "range":
        start = int(el.get("startTime") or 0)
        t0 = start if t0 is None else min(t0, start)
        if start - t0 >= skip_ns and el.get("duration"):
            count[el.get("eventIndex")] += 1
            total[el.get("eventIndex")] += int(el.get("duration"))
        el.clear()
rows = sorted(count, key=lambda k: -count[k])[:25]
for k in rows:
    typ, loc, det = events.get(k, ("?", k, ""))
    if typ in ("HandlingSignal", "Javascript", "Binding", "Creating"):
        print(f"{count[k]:7}x {total[k]/1e6:8.1f} ms  {typ:<14} {loc}  {det}")
