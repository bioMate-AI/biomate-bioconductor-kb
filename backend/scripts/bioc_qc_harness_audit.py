#!/usr/bin/env python3
"""
Static audit of every BIOC_QC_HARNESS-adopted .nf file.

For each Bioconductor workflow that declares non-empty qc_steps AND has
been adopted (contains `gates_by_label`), check the inject block between
`.qc_metrics_path <-` and `cat(jsonlite::toJSON(.qc_payload` for:

  1. qc_metrics.json output declaration present in process output: block
  2. Bare `$` (not escaped as `\\\$`) inside the inject block — would
     crash Nextflow's Groovy parser since the heredoc interpolates `$`
     regardless of R comment syntax. Same trap as 572637e48 / a56262912.
  3. Balanced `{` and `}` inside the inject block.
  4. writeLines anchor still present after the inject (sanity check
     that the patcher inserted before — not after — versions.yml).
  5. Every declared qc_steps label has a `.gates_by_label[["<label>"]]`
     entry (catches drift between LABEL_BLOCKS and the DB declarations).

Exit codes:
  0 — all clean
  1 — issues found (printed per-workflow with counts)

Run pre-sync; required if anyone re-runs `bioc_qc_harness_inject_multi.py`.
"""

import json
import re
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DB = ROOT / "backend/database/galaxy_ai_tools.db"


def main() -> int:
    con = sqlite3.connect(DB)
    rows = con.execute(
        "SELECT name, filename, qc_steps FROM workflows "
        "WHERE source='bioconductor' AND qc_steps NOT IN ('[]','') AND qc_steps IS NOT NULL"
    ).fetchall()

    issues: dict[str, list] = {
        "no_qc_metrics_output_decl": [],
        "no_inject_block_found": [],
        "bare_dollar_in_block": [],
        "brace_mismatch": [],
        "no_writeLines_after_block": [],
        "missing_label_entry": [],
    }
    adopted = 0

    for name, filename, qc_json in rows:
        p = ROOT / "backend/biomni_workflows" / filename
        if not p.exists():
            continue
        src = p.read_text(errors="ignore")
        if "gates_by_label" not in src:
            continue
        adopted += 1

        if 'path("qc_metrics.json")' not in src:
            issues["no_qc_metrics_output_decl"].append(name)

        m = re.search(
            r'(\.qc_metrics_path\s*<-\s*"qc_metrics\.json".*?cat\(jsonlite::toJSON\(\.qc_payload)',
            src, re.DOTALL,
        )
        if not m:
            issues["no_inject_block_found"].append(name)
            continue
        block = m.group(1)

        bare = re.findall(r"(?<!\\)\$", block)
        if bare:
            issues["bare_dollar_in_block"].append((name, len(bare)))

        if block.count("{") != block.count("}"):
            issues["brace_mismatch"].append((name, block.count("{"), block.count("}")))

        if "writeLines(c(" not in src[m.end():]:
            issues["no_writeLines_after_block"].append(name)

        try:
            declared = json.loads(qc_json)
        except json.JSONDecodeError:
            declared = []
        missing = [l for l in declared if f'.gates_by_label[["{l}"]]' not in block]
        if missing:
            issues["missing_label_entry"].append((name, missing))

    print(f"Adopted Bioc workflows audited: {adopted}")
    any_issue = False
    for k, v in issues.items():
        if v:
            any_issue = True
            print(f"  ✗ {k}: {len(v)}")
            for x in v[:5]:
                print(f"      {x}")
        else:
            print(f"  ✓ {k}: 0")
    return 1 if any_issue else 0


if __name__ == "__main__":
    sys.exit(main())
