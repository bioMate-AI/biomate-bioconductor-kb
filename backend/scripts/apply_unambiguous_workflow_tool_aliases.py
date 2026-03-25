#!/usr/bin/env python3
"""
Apply explicit, unambiguous alias mappings in workflows.tools_used.

This script only maps tokens that were manually verified to have a single
confident target tool_id.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sqlite3
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ALIAS_MAP = {
    "samtools/stats": "toolshed.g2.bx.psu.edu/repos/devteam/samtools_stats/samtools_stats/2.0.7",
    "samtools/flagstat": "toolshed.g2.bx.psu.edu/repos/devteam/samtools_flagstat/samtools_flagstat/2.0.7",
    "bwa/mem": "toolshed.g2.bx.psu.edu/repos/devteam/bwa/bwa_mem/0.7.19",
    "samtools/view": "toolshed.g2.bx.psu.edu/repos/iuc/samtools_view/samtools_view/1.21+galaxy0",
    "salmon/quant": "toolshed.g2.bx.psu.edu/repos/bgruening/salmon/salmon_quant/1.10.1+galaxy2",
    "ensemblvep/vep": "ensemblvep_vep",
    "bwamem2/mem": "bwamem2_mem",
    "samtools/faidx": "toolshed.g2.bx.psu.edu/repos/iuc/samtools_faidx/samtools_faidx/1.20+galaxy2",
    "gatk4/filtermutectcalls": "toolshed.g2.bx.psu.edu/repos/artbio/gatk4/gatk4_filtermutectcalls/4.1.7.0+galaxy3",
    "kallisto/quant": "toolshed.g2.bx.psu.edu/repos/iuc/kallisto_quant/kallisto_quant/0.48.0+galaxy1",
    "bismark/deduplicate": "toolshed.g2.bx.psu.edu/repos/bgruening/bismark/bismark_deduplicate/0.22.1",
    "strelka/somatic": "toolshed.g2.bx.psu.edu/repos/iuc/strelka_somatic/strelka_somatic/2.9.10+galaxy0",
    "angsd/docounts": "angsd_docounts",
    "angsd/contamination": "angsd_contamination",
    "somalier/relate": "somalier_relate",
    "samtools/depth": "toolshed.g2.bx.psu.edu/repos/iuc/samtools_depth/samtools_depth/1.21+galaxy0",
    "wisecondorx/predict": "toolshed.g2.bx.psu.edu/repos/artbio/wisecondorx/wisecondorx_predict/1.2.9+galaxy0",
    "seqtk/sample": "toolshed.g2.bx.psu.edu/repos/iuc/seqtk/seqtk_sample/1.5+galaxy0",
    "quantmsutils/dianncfg": "quantmsutils_dianncfg",
    "quantmsutils/mzmlstatistics": "quantmsutils_mzmlstatistics",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Apply unambiguous workflow tool alias mappings")
    parser.add_argument("--db", default="backend/database/galaxy_ai_tools.db", help="Path to DB")
    parser.add_argument("--apply", action="store_true", help="Persist changes")
    parser.add_argument(
        "--report-json",
        default="backend/database/tmp/workflow_tool_alias_apply_report.json",
        help="JSON report output path",
    )
    return parser.parse_args()


def parse_tools_used(raw: Any) -> list[str]:
    if raw is None:
        return []
    text = str(raw).strip()
    if not text:
        return []
    if text.startswith("["):
        try:
            arr = json.loads(text)
            if isinstance(arr, list):
                return [str(x).strip() for x in arr if str(x).strip()]
        except Exception:
            pass
    return [p.strip().strip("\"'") for p in re.split(r"[,;\n]+", text) if p.strip()]


def backup_db(db_path: Path) -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    backup_path = db_path.with_suffix(f".db.bak_{stamp}")
    shutil.copy2(db_path, backup_path)
    return backup_path


def main() -> int:
    args = parse_args()
    db_path = Path(args.db).resolve()
    report_path = Path(args.report_json).resolve()
    report_path.parent.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    try:
        cur = conn.cursor()
        cur.execute("SELECT id, name, filename, tools_used FROM workflows WHERE LOWER(format)='nextflow'")
        rows = cur.fetchall()

        updates = []
        token_counter = Counter()

        for row in rows:
            tokens = parse_tools_used(row["tools_used"])
            if not tokens:
                continue

            changed = False
            replaced = []
            new_tokens = []
            seen = set()
            for tok in tokens:
                mapped = ALIAS_MAP.get(tok, tok)
                if mapped != tok:
                    changed = True
                    replaced.append({"from": tok, "to": mapped})
                    token_counter[tok] += 1
                if mapped not in seen:
                    seen.add(mapped)
                    new_tokens.append(mapped)

            if changed:
                updates.append(
                    {
                        "id": row["id"],
                        "workflow": row["name"],
                        "filename": row["filename"],
                        "replacements": replaced,
                        "old_tokens": tokens,
                        "new_tokens": new_tokens,
                    }
                )

        backup_file = None
        if args.apply and updates:
            backup_file = backup_db(db_path)
            for u in updates:
                cur.execute("UPDATE workflows SET tools_used = ? WHERE id = ?", (json.dumps(u["new_tokens"]), u["id"]))
            conn.commit()

        report = {
            "timestamp_utc": datetime.now(timezone.utc).isoformat(),
            "db_path": str(db_path),
            "apply": args.apply,
            "workflows_scanned": len(rows),
            "workflows_updated": len(updates),
            "token_replacement_counts": dict(token_counter),
            "alias_map_size": len(ALIAS_MAP),
            "backup_file": str(backup_file) if backup_file else None,
            "sample_updates": updates[:200],
        }
        report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")

        print(f"db_path: {db_path}")
        print(f"mode: {'apply' if args.apply else 'dry-run'}")
        print(f"workflows_scanned: {len(rows)}")
        print(f"workflows_updated: {len(updates)}")
        print(f"token_replacement_counts: {dict(token_counter)}")
        if backup_file:
            print(f"backup_file: {backup_file}")
        print(f"report_json: {report_path}")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())

