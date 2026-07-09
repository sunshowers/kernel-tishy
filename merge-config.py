#!/usr/bin/env python3
"""Merge Kconfig set/unset fragments into a base config.

A faithful reimplementation of OpenGamingCollective/kernel-configurator so that
the same merge runs both locally (build.sh) and in CI without a network action.

Set files contain ``CONFIG_FOO=value`` lines; unset files contain bare
``CONFIG_FOO`` names. Sets are applied first, then unsets (so a key listed in
both ends up unset), matching the upstream action.
"""

import argparse
import sys


def parse_set(path):
    entries = []
    with open(path, encoding="utf-8") as f:
        for raw in f.read().split("\n"):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            idx = line.find("=")
            if idx == -1:
                continue
            entries.append((line[:idx], line[idx + 1:]))
    return entries


def parse_unset(path):
    entries = []
    with open(path, encoding="utf-8") as f:
        for raw in f.read().split("\n"):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            entries.append(line)
    return entries


def apply_set(lines, entries):
    for key, value in entries:
        set_prefix = f"{key}="
        unset_marker = f"# {key} is not set"
        found = False
        for i, line in enumerate(lines):
            if line.startswith(set_prefix):
                lines[i] = f"{key}={value}"
                found = True
                break
            if line == unset_marker:
                lines[i] = f"{key}={value}"
                found = True
                break
        if not found:
            lines.append(f"{key}={value}")


def apply_unset(lines, keys):
    for key in keys:
        set_prefix = f"{key}="
        unset_marker = f"# {key} is not set"
        for i, line in enumerate(lines):
            if line.startswith(set_prefix) or line == unset_marker:
                lines[i] = f"# {key} is not set"
                break
        else:
            print(f"{key} not found in config, skipping unset")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True)
    ap.add_argument("--set", dest="set_files", action="append", default=[])
    ap.add_argument("--unset", dest="unset_files", action="append", default=[])
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    with open(args.config, encoding="utf-8") as f:
        lines = f.read().split("\n")

    set_entries = []
    for p in args.set_files:
        set_entries.extend(parse_set(p))
    apply_set(lines, set_entries)

    unset_entries = []
    for p in args.unset_files:
        unset_entries.extend(parse_unset(p))
    apply_unset(lines, unset_entries)

    with open(args.output, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"Merged config written to {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
