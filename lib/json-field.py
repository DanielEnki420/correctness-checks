#!/usr/bin/env python3
"""Read JSON on stdin, print the value at a dotted path given as argv[1].

A separate file on purpose. The obvious one-liner

    value=$(python3 - "$field" <<<"$body" <<'PY' ... PY)

does NOT work: `python3 -` reads the PROGRAM from stdin, so the heredoc
replaces the piped data and the script sees an empty input. Same trap applies
to `python3 -c "..."` with double quotes, where the shell expands $ and
backticks inside your source before Python ever sees it.
"""
import json
import sys

feld = sys.argv[1]
d = json.load(sys.stdin)
for teil in feld.split("."):
    d = d[teil] if isinstance(d, dict) else d[int(teil)]
print(d)
