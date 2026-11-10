#!/usr/bin/env python3
"""Allowlisted diagnostic projections. Never echo raw payloads on failure."""
import argparse
import json
from pathlib import Path
import re
import sys


def inspect_summary(records):
    """Omit environment, command lines, labels, mounts and health output."""
    result = []
    for item in records:
        state = item.get("State", {})
        health = state.get("Health", {})
        status = state.get("Status")
        health_status = health.get("Status")
        result.append({
            "id": item.get("Id", "")[:12] if re.fullmatch(r"[0-9a-f]{64}", item.get("Id", "")) else "unknown",
            "state": status if status in {"created", "running", "paused", "restarting", "removing", "exited", "dead"} else "unknown",
            "health": health_status if health_status in {"starting", "healthy", "unhealthy"} else "unknown",
            "exit_code": state.get("ExitCode") if type(state.get("ExitCode")) is int else None,
            "restart_count": item.get("RestartCount") if type(item.get("RestartCount")) is int else None,
            "health_exit_codes": [r.get("ExitCode") for r in health.get("Log", []) if type(r.get("ExitCode")) is int],
        })
    return result


def env_summary(text):
    """Report valid key names/presence only, never comments or any values."""
    rows = []
    for line in text.splitlines():
        match = re.match(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$", line)
        if match:
            value = match[2].strip()
            rows.append(match[1] + "=" + ("set" if value not in {"", "''", '\"\"'} else "empty"))
    return "\n".join(rows)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["inspect", "env"])
    parser.add_argument("path", nargs="?")
    args = parser.parse_args()
    try:
        if args.mode == "env":
            if not args.path:
                raise ValueError("missing environment path")
            print(env_summary(Path(args.path).read_text()))
        else:
            data = json.load(sys.stdin)
            if not isinstance(data, list) or not all(isinstance(x, dict) for x in data):
                raise ValueError("invalid inspect structure")
            print(json.dumps(inspect_summary(data), indent=2))
    except Exception:
        print("Diagnostic projection failed; raw input was not exported.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
