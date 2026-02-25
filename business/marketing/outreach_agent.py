#!/usr/bin/env python3
"""
BioMate Marketing Outreach Agent
=================================
CLI tool for managing and activating the BioMate beta user target list.

Usage:
    python outreach_agent.py --stats
    python outreach_agent.py --output csv --segment all
    python outreach_agent.py --output json --segment texas
    python outreach_agent.py --output emails --segment texas --priority A
    python outreach_agent.py --output emails --segment energy
    python outreach_agent.py --output emails --segment doe_labs
    python outreach_agent.py --output csv --segment energy --priority A,B
"""

import argparse
import csv
import json
import os
import sys
from pathlib import Path
from typing import Optional

TARGETS_DIR = Path(__file__).parent / "targets"

SEGMENT_FILES = {
    "texas":       "texas_targets.json",
    "doe_labs":    "doe_labs_targets.json",
    "gulf_coast":  "gulf_coast_targets.json",
    "ag_genomics": "agricultural_genomics_targets.json",
    "cro":         "clinical_cro_targets.json",
}

# Energy-linked targets cut across files — any target with energy_link=true
ENERGY_SEGMENT = "energy"

SEGMENT_ALIASES = {
    "energy":     None,   # special: filter by energy_link=true across all files
    "academic":   None,   # filter by segment="academic" across texas
    "medical":    None,   # filter by segment="medical" across texas
    "biotech":    None,   # filter by segment="biotech" across texas
    "all":        None,   # load everything
}


def _strip_comments(text: str) -> str:
    """Remove // comments from pseudo-JSON (our curated format).
    Uses negative lookbehind to preserve https:// URLs inside strings."""
    import re
    # Remove // comments but NOT https:// or http:// URLs
    text = re.sub(r'(?<!:)//[^\n]*', '', text)
    # Remove trailing commas before } or ]
    text = re.sub(r',\s*([}\]])', r'\1', text)
    return text


def load_segment(segment: str, priority_filter: Optional[list] = None) -> list:
    """Load and return targets for a given segment name."""
    targets = []

    if segment == "all":
        for file_key in SEGMENT_FILES:
            targets.extend(_load_file(file_key))
    elif segment == ENERGY_SEGMENT:
        # Cross-file filter: energy_link=true
        for file_key in SEGMENT_FILES:
            for t in _load_file(file_key):
                if t.get("energy_link"):
                    targets.append(t)
    elif segment in ("academic", "medical", "biotech"):
        # Texas sub-segments
        for t in _load_file("texas"):
            if t.get("segment") == segment:
                targets.append(t)
    elif segment in SEGMENT_FILES:
        targets = _load_file(segment)
    else:
        print(f"ERROR: Unknown segment '{segment}'. "
              f"Valid: {', '.join(list(SEGMENT_FILES.keys()) + list(SEGMENT_ALIASES.keys()))}")
        sys.exit(1)

    if priority_filter:
        targets = [t for t in targets if t.get("priority") in priority_filter]

    return targets


def _load_file(file_key: str) -> list:
    path = TARGETS_DIR / SEGMENT_FILES[file_key]
    if not path.exists():
        print(f"WARNING: Target file not found: {path}")
        return []
    raw = path.read_text(encoding="utf-8")
    cleaned = _strip_comments(raw)
    data = json.loads(cleaned)
    return data.get("targets", [])


def print_stats():
    """Print summary statistics across all segments."""
    print("\n" + "=" * 60)
    print("  BioMate Marketing Target Database — Statistics")
    print("=" * 60)

    grand_total = 0
    grand_priority = {"A": 0, "B": 0, "C": 0}
    grand_energy = 0

    for seg, fname in SEGMENT_FILES.items():
        targets = _load_file(seg)
        total = len(targets)
        p_counts = {"A": 0, "B": 0, "C": 0}
        energy_count = 0
        for t in targets:
            p = t.get("priority", "C")
            p_counts[p] = p_counts.get(p, 0) + 1
            if t.get("energy_link"):
                energy_count += 1

        grand_total += total
        for p in p_counts:
            grand_priority[p] = grand_priority.get(p, 0) + p_counts[p]
        grand_energy += energy_count

        print(f"\n  [{seg.upper():20s}]  {total:3d} targets")
        print(f"    Priority A: {p_counts['A']:3d}  |  B: {p_counts['B']:3d}  |  C: {p_counts['C']:3d}")
        if energy_count:
            print(f"    Energy-linked: {energy_count}")

    print("\n" + "-" * 60)
    print(f"  TOTAL  {grand_total:3d} targets across all segments")
    print(f"  Priority A: {grand_priority['A']}  |  B: {grand_priority['B']}  |  C: {grand_priority['C']}")
    print(f"  Energy-linked (total): {grand_energy}")
    print("=" * 60 + "\n")


def output_csv(targets: list, output_path: Optional[str] = None):
    """Export targets as CSV."""
    if not targets:
        print("No targets found for that filter.")
        return

    fieldnames = [
        "id", "name", "city", "state", "segment", "sub_segment",
        "priority", "energy_link", "domains", "biomate_workflows",
        "reach_channel", "notes", "key_contacts", "website"
    ]

    out = open(output_path, "w", newline="", encoding="utf-8") if output_path else sys.stdout
    writer = csv.DictWriter(out, fieldnames=fieldnames, extrasaction="ignore")
    writer.writeheader()
    for t in sorted(targets, key=lambda x: (x.get("priority", "C"), x.get("name", ""))):
        row = dict(t)
        row["domains"] = "; ".join(t.get("domains", []))
        row["biomate_workflows"] = "; ".join(t.get("biomate_workflows", []))
        contacts = t.get("key_contacts", [])
        row["key_contacts"] = "; ".join(
            f"{c['name']} ({c['title']}) <{c.get('email_hint', '')}>" for c in contacts
        )
        writer.writerow(row)

    if output_path:
        out.close()
        print(f"Exported {len(targets)} targets → {output_path}")


def output_json(targets: list, output_path: Optional[str] = None):
    """Export targets as JSON."""
    data = sorted(targets, key=lambda x: (x.get("priority", "C"), x.get("name", "")))
    payload = json.dumps(data, indent=2, ensure_ascii=False)
    if output_path:
        Path(output_path).write_text(payload, encoding="utf-8")
        print(f"Exported {len(targets)} targets → {output_path}")
    else:
        print(payload)


def output_emails(targets: list):
    """Generate personalized outreach email drafts for each target."""
    from outreach_templates import generate_email

    targets_sorted = sorted(targets, key=lambda x: (x.get("priority", "C"), x.get("name", "")))
    for i, target in enumerate(targets_sorted, 1):
        print(f"\n{'=' * 70}")
        print(f"  TARGET {i}/{len(targets_sorted)} — Priority {target.get('priority', '?')}  [{target.get('id', '')}]")
        print(f"  {target['name']}  |  {target.get('city', '')}, {target.get('state', '')}")
        print("=" * 70)
        email = generate_email(target)
        print(email)


def main():
    parser = argparse.ArgumentParser(
        description="BioMate Marketing Outreach Agent",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Segments:
  texas        All Texas targets (~80)
  doe_labs     DOE National Laboratories (~16)
  gulf_coast   Gulf Coast corridor (~18)
  ag_genomics  Agricultural genomics belt (~22)
  cro          Clinical labs & CROs (~18)
  energy       Cross-file: all energy-linked targets
  academic     Texas academic labs only
  medical      Texas medical centers only
  biotech      Texas biotech companies only
  all          Everything (~155 total)

Examples:
  python outreach_agent.py --stats
  python outreach_agent.py --output csv --segment texas --priority A
  python outreach_agent.py --output emails --segment energy
  python outreach_agent.py --output csv --segment all > all_targets.csv
        """
    )
    parser.add_argument("--stats", action="store_true", help="Print database statistics")
    parser.add_argument("--output", choices=["csv", "json", "emails"], default="csv",
                        help="Output format (default: csv)")
    parser.add_argument("--segment", default="texas",
                        help="Segment to target (default: texas)")
    parser.add_argument("--priority", default=None,
                        help="Filter by priority: A, B, C, or comma-separated e.g. A,B")
    parser.add_argument("--save", default=None, metavar="FILE",
                        help="Save output to file instead of stdout (csv/json only)")
    args = parser.parse_args()

    if args.stats:
        print_stats()
        return

    priority_filter = None
    if args.priority:
        priority_filter = [p.strip().upper() for p in args.priority.split(",")]

    targets = load_segment(args.segment, priority_filter)

    if not targets:
        print(f"No targets found for segment='{args.segment}' with priority filter={priority_filter}")
        return

    if args.output == "csv":
        output_csv(targets, args.save)
    elif args.output == "json":
        output_json(targets, args.save)
    elif args.output == "emails":
        output_emails(targets)


if __name__ == "__main__":
    main()
