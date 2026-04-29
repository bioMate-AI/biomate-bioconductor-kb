"""
Regulatory Skills Ingestion Runner

Downloads and ingests all authoritative regulatory documents into the
skills DB for BioMate. Sources are validated against regulatory_knowledge.yaml
before ingestion — only current, EMA-accepted, GPL-licensed OSP reports.

Usage:
    python evaluation/runners/ingest_regulatory_skills.py [--force]
    python evaluation/runners/ingest_regulatory_skills.py --summary
    python evaluation/runners/ingest_regulatory_skills.py --compare --afe 0.95 --aafe 1.3 --within2fold 0.73

Options:
    --force          Re-download and re-ingest even if already present
    --summary        Print DB summary and exit
    --compare        Run compare_metrics with provided values
    --afe FLOAT      AFE for compare mode
    --aafe FLOAT     AAFE for compare mode
    --within2fold FLOAT  Fraction within 2-fold (0–1) for compare mode
    --region STR     FDA|EMA|NMPA|PMDA (default: EMA)
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Allow running from repo root
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "backend" / "lib"))

from galaxy.ai.drug_discovery.regulatory_skills_db import RegulatorySkillsDB, AUTHORITATIVE_SOURCES


def cmd_ingest(args: argparse.Namespace) -> None:
    db = RegulatorySkillsDB()
    print(f"DB path: {db.db_path}")
    print(f"Sources to ingest: {len(AUTHORITATIVE_SOURCES)}")
    for sid, meta in AUTHORITATIVE_SOURCES.items():
        print(f"  {sid}: {meta['description'][:60]}…")
    print()

    results = db.ingest_all(force_refresh=args.force)

    ok = err = skip = 0
    for sid, r in results.items():
        status = r.get("status", "?")
        if status == "ingested":
            ok += 1
            print(f"  ✓ {sid}: {r.get('skills_added', 0)} skills, {r.get('chars', 0):,} chars"
                  + (f", version={r['version']}" if r.get('version') else ""))
        elif status == "already_ingested":
            skip += 1
            print(f"  - {sid}: already ingested (use --force to refresh)")
        else:
            err += 1
            print(f"  ✗ {sid}: {status}")

    print(f"\nDone: {ok} ingested, {skip} skipped, {err} errors")
    print()
    cmd_summary(args, db)


def cmd_summary(args: argparse.Namespace, db: RegulatorySkillsDB = None) -> None:
    if db is None:
        db = RegulatorySkillsDB()
    s = db.summary()
    print("=== Regulatory Skills DB Summary ===")
    print(f"Documents (current):   {s['documents']}")
    print(f"Skills:                {s['skills']}")
    print(f"PBPK benchmarks:       {s['pbpk_benchmarks']}")
    print(f"Narrative patterns:    {s['narrative_patterns']}")
    print()
    if s["sources"]:
        print("Ingested sources:")
        for src in s["sources"]:
            print(f"  {src['id']:30s}  v{src.get('version','?'):<12}  {src.get('fetched','?')[:10]}  {src.get('chars',0):>8,} chars")
    else:
        print("No sources ingested yet. Run: python ingest_regulatory_skills.py")

    # Show a sample of extracted criterion statements
    patterns = db.get_narrative_patterns(pattern_type="criterion_statement")
    if patterns:
        print(f"\nSample criterion statements ({len(patterns)} total):")
        for p in patterns[:3]:
            print(f"  [{p['source_id']}] {p['text'][:120]}…")

    benchmarks = db.get_pbpk_benchmarks()
    if benchmarks:
        print(f"\nPBPK benchmarks ({len(benchmarks)} entries):")
        for b in benchmarks[:5]:
            w2f = b.get("within_2fold_pct")
            verdict = b.get("regulatory_verdict", "?")
            print(f"  {b['drug_pair']:<40s}  within-2-fold={w2f}%  [{verdict}]")


def cmd_compare(args: argparse.Namespace) -> None:
    db = RegulatorySkillsDB()
    result = db.compare_metrics(
        afe=args.afe,
        aafe=args.aafe,
        within_2fold=args.within2fold,
        region=args.region,
    )
    print(json.dumps(result, indent=2))
    verdict = result.get("verdict", "?")
    icon = "✓" if verdict == "PASS" else "✗"
    print(f"\n{icon} Verdict: {verdict}")
    print(result.get("note", ""))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--force", action="store_true",
                        help="Re-ingest even if already present")
    parser.add_argument("--summary", action="store_true",
                        help="Print summary and exit")
    parser.add_argument("--compare", action="store_true",
                        help="Run metric comparison")
    parser.add_argument("--afe", type=float, default=1.0)
    parser.add_argument("--aafe", type=float, default=1.0)
    parser.add_argument("--within2fold", type=float, default=0.73)
    parser.add_argument("--region", default="EMA",
                        choices=["FDA", "EMA", "NMPA", "PMDA", "ALL"])

    args = parser.parse_args()

    if args.summary:
        cmd_summary(args)
    elif args.compare:
        cmd_compare(args)
    else:
        cmd_ingest(args)


if __name__ == "__main__":
    main()
