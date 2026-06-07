#!/usr/bin/env python3
"""
Generate the public BioMate-KB skill bundle: top N Bioconductor packages
by official Bioconductor download score, one SKILL.md per package,
organized into domain folders.

Reads:
  - bioc_pkg_scores.tab   (official Bioconductor download scores)
  - galaxy_ai_tools.db    (production structured knowledge — read-only)
  - bioconductor_tools.db (23 hand-curated SKILL.md bodies — read-only)

Writes:
  - skills/<domain>/<pkg-kebab>/SKILL.md

Usage:
  ./generate_bundle.py --top 100
"""
from __future__ import annotations
import argparse, csv, json, re, sqlite3, sys
from collections import Counter, defaultdict
from pathlib import Path

# Add this dir to import extract_skill
sys.path.insert(0, str(Path(__file__).parent.resolve()))
from extract_skill import extract_skill, _kebab  # type: ignore

HERE = Path(__file__).parent.resolve()
REL_ROOT = HERE.parent
SCORES_TSV = REL_ROOT / "bioc_pkg_scores.tab"

DEFAULT_DB = Path(__file__).parent.parent / "galaxy_ai_tools.db"
DEFAULT_SKILL_DB = Path(__file__).parent.parent / "bioconductor_tools.db"


def load_scores(path: Path) -> list[tuple[str, int]]:
    rows: list[tuple[str, int]] = []
    with path.open() as f:
        reader = csv.reader(f, delimiter="\t")
        header = next(reader, None)
        for r in reader:
            if len(r) < 2: continue
            try: rows.append((r[0].strip(), int(r[1])))
            except ValueError: continue
    rows.sort(key=lambda x: -x[1])
    return rows


def db_has_package(name: str, db: Path) -> bool:
    conn = sqlite3.connect(str(db))
    r = conn.execute(
        "SELECT 1 FROM workflows WHERE lower(name)=? AND source='bioconductor' LIMIT 1",
        (name.lower(),),
    ).fetchone()
    conn.close()
    return r is not None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--top", type=int, default=100)
    ap.add_argument("--db", type=Path, default=DEFAULT_DB)
    ap.add_argument("--skill-db", type=Path, default=DEFAULT_SKILL_DB)
    ap.add_argument("--out", type=Path, default=REL_ROOT / "skills")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    skill_db = args.skill_db if args.skill_db.exists() else None
    if not skill_db: print(f"[warn] no hand-curated skill DB found", file=sys.stderr)

    scores = load_scores(SCORES_TSV)
    print(f"[bundle] loaded {len(scores)} packages from bioc score tab")
    print(f"[bundle] target top {args.top}; filter to those present in BioMate-KB ({args.db.name})")

    # Walk top scores; keep packages BioMate-KB has indexed; cap at args.top.
    selected: list[tuple[str, int]] = []
    seen = set()
    for name, score in scores:
        if name in seen: continue
        if db_has_package(name, args.db):
            selected.append((name, score))
            seen.add(name)
            if len(selected) >= args.top: break

    print(f"[bundle] selected {len(selected)} packages")
    if not selected: return 1

    # Generate
    args.out.mkdir(parents=True, exist_ok=True)
    by_domain: Counter = Counter()
    written: list[dict] = []
    skipped: list[str] = []
    for i, (name, score) in enumerate(selected, 1):
        try:
            r = extract_skill(name, args.db, skill_db)
        except Exception as exc:
            skipped.append(f"{name}: extract error {exc}")
            continue
        if not r:
            skipped.append(f"{name}: no usable content")
            continue
        domain, body = r
        out_dir = args.out / domain / _kebab(name)
        out_path = out_dir / "SKILL.md"
        if not args.dry_run:
            out_dir.mkdir(parents=True, exist_ok=True)
            out_path.write_text(body)
        by_domain[domain] += 1
        written.append({"name": name, "score": score, "domain": domain,
                         "chars": len(body), "path": str(out_path.relative_to(REL_ROOT))})
        if i % 50 == 0 or i <= 10:
            print(f"  [{i:3d}/{len(selected)}] {name:30s} → {domain}/{_kebab(name)}/SKILL.md ({len(body):6d} ch)")

    # Manifest
    manifest = {
        "version": "1.0.0",
        "generated_at": __import__("datetime").datetime.now(__import__("datetime").UTC).isoformat(),
        "total_packages": len(written),
        "skipped": len(skipped),
        "by_domain": dict(by_domain.most_common()),
        "ranking_source": "https://bioconductor.org/packages/stats/bioc/bioc_pkg_scores.tab",
        "packages": written,
    }
    (REL_ROOT / "MANIFEST.json").write_text(json.dumps(manifest, indent=2))
    print()
    print(f"[bundle] wrote {len(written)} SKILL.md files")
    print(f"[bundle] by domain: {dict(by_domain.most_common())}")
    print(f"[bundle] skipped: {len(skipped)}")
    if skipped[:5]:
        print(f"[bundle] first skips: {skipped[:5]}")
    print(f"[bundle] manifest → MANIFEST.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
