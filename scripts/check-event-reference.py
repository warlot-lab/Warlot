#!/usr/bin/env python3
"""Compare a package's event reference with the events its code declares.

Called once per package by `check-events.sh` section 7, with the package
directory in `PKG`. Prints one line per discrepancy and exits non-zero.

Kept out of the shell script because the comparison is over JSON and over field
*order*, and both are things bash reads badly.
"""

import json
import os
import pathlib
import re
import sys


def declared_events(pkg):
    """Every event struct under sources/events/, with its fields in order."""
    events = {}
    for path in sorted((pkg / "sources/events").glob("*.move")):
        text = path.read_text()
        module = re.search(r"^module warlot::(\w+);", text, re.M).group(1)
        for match in re.finditer(
            r"public struct (\w+) has copy, drop, store \{(.*?)\n\}", text, re.S
        ):
            fields = [
                (
                    line.strip().rstrip(",").split(":")[0].strip(),
                    line.strip().rstrip(",").split(":", 1)[1].strip(),
                )
                for line in match.group(2).split("\n")
                if line.strip() and not line.strip().startswith("//")
            ]
            events[(module, match.group(1))] = fields
    return events


def check_schema(pkg, code):
    problems = []
    schema = json.loads((pkg / "docs/event-schema.json").read_text())["events"]
    want = {f"<PACKAGE>::{mod}::{name}": f for (mod, name), f in code.items()}

    for key in sorted(set(want) - set(schema)):
        problems.append(f"    event-schema.json is missing {key}")
    for key in sorted(set(schema) - set(want)):
        problems.append(f"    event-schema.json declares {key}, which the code does not")

    for key in sorted(set(want) & set(schema)):
        listed = [(f["name"], f["move_type"]) for f in schema[key]["fields"]]
        if listed != want[key]:
            problems.append(
                f"    event-schema.json fields differ for {key}\n"
                f"      code  : {[n for n, _ in want[key]]}\n"
                f"      schema: {[n for n, _ in listed]}"
            )
        absent = [n for n, _ in want[key] if n not in schema[key].get("parsedJson", {})]
        if absent:
            problems.append(
                f"    event-schema.json parsedJson for {key} omits {', '.join(absent)}"
            )
    return problems


def check_markdown(pkg, code):
    problems = []
    markdown = (pkg / "docs/events.md").read_text()
    for (_module, name), fields in sorted(code.items()):
        row = re.search(r"^\| `%s` \|([^|]*)\|([^|]*)\|" % name, markdown, re.M)
        if row is None:
            problems.append(f"    events.md has no row for {name}")
            continue
        listed = re.findall(r"`([a-z0-9_]+)`", row.group(2))
        if listed != [n for n, _ in fields]:
            problems.append(
                f"    events.md fields differ for {name}\n"
                f"      code    : {[n for n, _ in fields]}\n"
                f"      events.md: {listed}"
            )
    return problems


def main():
    pkg = pathlib.Path(os.environ["PKG"])
    code = declared_events(pkg)
    problems = check_schema(pkg, code) + check_markdown(pkg, code)

    for line in problems:
        print(line)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
