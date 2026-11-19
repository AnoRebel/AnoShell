#!/usr/bin/env python3
"""Print FocusTime's database as JSON for anod's one-time import.

Usage: python3 export.py PATH_TO_focustime.db
Output: {"log": [[date, app, seconds, name]], "hourly": [[date, hour, app, seconds]],
         "minutes": [[date, minute, app, seconds]]}; a missing table is [].
The database is opened read-only and never changed.
"""
import json
import os
import sqlite3
import sys
import urllib.parse


def rows(c, sql):
    try:
        return [list(r) for r in c.execute(sql).fetchall()]
    except sqlite3.OperationalError:
        return []  # an older FocusTime without that table


def main():
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    conn = sqlite3.connect("file:" + urllib.parse.quote(os.path.abspath(sys.argv[1])) + "?mode=ro", uri=True)
    c = conn.cursor()
    out = {
        "log": rows(c, "SELECT log_date, app_class, seconds, COALESCE(app_title, app_class) FROM focus_log"),
        "hourly": rows(c, "SELECT log_date, hour, app_class, seconds FROM focus_hourly"),
        "minutes": rows(c, "SELECT log_date, minute_idx, app_class, seconds FROM focus_minutes"),
    }
    json.dump(out, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
