"""Code-grounded audit of workflow descriptions: remove description clauses that contradict the workflow's own code.

A workflow's `.nf` file is what runs; its `description` is what search (FTS + LLM ranking) and users read. When they
disagree, routing follows the text. Found 2026-11-05: `Detect And Annotate Somatic Mutations` runs GATK Mutect2 from
tumour/normal BAMs, but its description said it "starts from a pre-existing VCF — it does NOT perform calling".

Per workflow (local code only — nf-core rows are display stubs locally, the real pipelines run on dev), model A
lists VERBATIM description clauses contradicting the code about the inputs it takes or the steps it performs, each
with the code line that shows it; model B confirms against the code. Removal-only, token-bounded, guarded by the
original text, addressed by row id, refused on an inconsistent FTS index (shared helpers of annotation_claim_audit).

Usage:
  PYTHONPATH=lib python3 -m galaxy.ai.chain_composer.description_code_audit propose --output p.jsonl [--names a|b] [--limit N]
  PYTHONPATH=lib python3 -m galaxy.ai.chain_composer.description_code_audit verify --output p.jsonl --verified v.jsonl
  PYTHONPATH=lib python3 -m galaxy.ai.chain_composer.description_code_audit apply --verified v.jsonl --db <db>
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sqlite3
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Dict, List, Optional

from .annotation_claim_audit import _json, cleaned
from .domain_reclassifier import _DEFAULT_DB, assert_fts_consistent, openrouter_llm

_BACKEND = Path(__file__).resolve().parents[4]
_ROOTS = [_BACKEND / "biomni_workflows", _BACKEND / "biomni_workflows" / "nextflow_nfcore",
          _BACKEND / "biomni_workflows" / "nextflow", _BACKEND]
_SKIP_SOURCES = ("nfcore", "nfcore_subwf")  # local files are display stubs, not the code that runs

_PROPOSE = """You check a bioinformatics workflow's DESCRIPTION against its CODE (the code is what actually runs).

WORKFLOW: {name}
DESCRIPTION: {description}
DECLARED INPUTS: {input_types}
CODE (excerpt of the .nf file):
{code}

List clauses of the DESCRIPTION, copied VERBATIM, that CONTRADICT the code about (a) the input data the workflow
takes, or (b) the analysis steps it performs — including claims of steps the code does not do, and denials of steps
the code does (e.g. "does NOT perform variant calling" when the code runs a variant caller). For each, quote the code
line that shows the contradiction. Do NOT list clauses that are merely unverifiable from the excerpt, vague, or about
biology/context. Most descriptions have no contradiction.
Reply with ONLY: {{"contradictions": [{{"clause": "<verbatim>", "code_evidence": "<code line>"}}], "reason": "<short>"}}"""

_VERIFY = """A reviewer says these DESCRIPTION clauses contradict the workflow's CODE (the code is what runs).

WORKFLOW: {name}
DESCRIPTION: {description}
CODE (excerpt):
{code}
CLAIMED CONTRADICTIONS: {items}

For each clause answer true only if the code clearly shows the clause is false about the inputs taken or the steps
performed; false if the clause is true, unverifiable from this excerpt, or you are uncertain.
Reply with ONLY: {{"confirm": {{"<clause>": true|false, ...}}}}"""


def _code_path(filename: str) -> Optional[Path]:
    for r in _ROOTS:
        p = r / filename
        if p.is_file():
            return p
    return None


def _excerpt(path: Path, limit: int = 3500) -> str:
    text = path.read_text(errors="replace")
    params = "\n".join(l for l in text.splitlines() if l.strip().startswith("params."))[:1200]
    body = re.sub(r"\n\s*\n+", "\n", text)
    return (params + "\n...\n" + body)[:limit]


def _rows(db: Path, names=None, limit=None) -> List[Dict]:
    conn = sqlite3.connect(str(db))
    rows = conn.execute("SELECT id, name, COALESCE(source,''), COALESCE(description,''), COALESCE(input_types,'[]'), "
                        "filename FROM workflows WHERE executable=1 AND length(COALESCE(description,'')) > 0").fetchall()
    conn.close()
    out = []
    for wid, name, src, desc, it, fn in rows:
        if src in _SKIP_SOURCES or (names and name not in names):
            continue
        p = _code_path(fn or "")
        if p:
            out.append({"id": wid, "name": name, "source": src, "description": desc, "input_types": it, "code": _excerpt(p)})
    return out[:limit] if limit else out


def propose(db: Path, llm, workers: int, names=None, limit=None) -> List[Dict]:
    def one(r):
        d = _json(llm(_PROPOSE.format(name=r["name"], description=r["description"][:1500],
                                      input_types=r["input_types"][:400], code=r["code"])))
        if d is None or not isinstance(d.get("contradictions"), list):
            return {**r, "contradictions": None, "status": "llm_failed"}
        items = [x for x in d["contradictions"] if isinstance(x, dict) and isinstance(x.get("clause"), str)
                 and x["clause"].strip() and x["clause"] in r["description"]]
        return {**r, "contradictions": items, "dropped_nonverbatim": len(d["contradictions"]) - len(items),
                "reason": str(d.get("reason", ""))[:200], "status": "ok"}
    with ThreadPoolExecutor(max(1, workers)) as ex:
        return list(ex.map(one, _rows(db, names, limit)))


def verify(props: List[Dict], llm, workers: int) -> List[Dict]:
    def one(p):
        if not p.get("contradictions"):
            return {**p, "confirmed": []}
        d = _json(llm(_VERIFY.format(name=p["name"], description=p["description"][:1500], code=p["code"],
                                     items=json.dumps(p["contradictions"]))))
        conf = (d or {}).get("confirm") or {}
        return {**p, "confirmed": [x["clause"] for x in p["contradictions"] if conf.get(x["clause"]) is True]}
    with ThreadPoolExecutor(max(1, workers)) as ex:
        return list(ex.map(one, props))


def apply(db: Path, verified: List[Dict]) -> int:
    assert_fts_consistent(db)
    conn = sqlite3.connect(str(db))
    n = 0
    for v in verified:
        if v.get("confirmed"):
            n += conn.execute("UPDATE workflows SET description = ? WHERE id = ? AND description = ?",
                              (cleaned(v["description"], v["confirmed"]), v["id"], v["description"])).rowcount
    conn.commit()
    conn.close()
    return n


def _cli(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("step", choices=["propose", "verify", "apply"])
    ap.add_argument("--output"); ap.add_argument("--verified"); ap.add_argument("--db", default=str(_DEFAULT_DB))
    ap.add_argument("--model", default="google/gemini-3.8-flash"); ap.add_argument("--verify-model", default="anthropic/claude-sonnet-5.5")
    ap.add_argument("--workers", type=int, default=12); ap.add_argument("--names", default=""); ap.add_argument("--limit", type=int)
    a = ap.parse_args(argv)
    if a.step == "propose":
        res = propose(Path(a.db), openrouter_llm(a.model), a.workers, [n for n in a.names.split("|") if n] or None, a.limit)
        with open(a.output, "w") as f:
            for r in res:
                f.write(json.dumps(r) + "\n")
        sys.stderr.write(f"rows {len(res)}; flagged {sum(1 for r in res if r.get('contradictions'))}; failed {sum(r['status'] != 'ok' for r in res)}\n")
    elif a.step == "verify":
        res = verify([json.loads(l) for l in open(a.output) if l.strip()], openrouter_llm(a.verify_model), a.workers)
        with open(a.verified, "w") as f:
            for r in res:
                f.write(json.dumps(r) + "\n")
        sys.stderr.write(f"rows with confirmed contradictions {sum(1 for r in res if r.get('confirmed'))}\n")
    else:
        sys.stderr.write(f"updated {apply(Path(a.db), [json.loads(l) for l in open(a.verified) if l.strip()])} rows\n")
    return 0


if __name__ == "__main__":  # pragma: no cover
    sys.exit(_cli(sys.argv[1:]))
