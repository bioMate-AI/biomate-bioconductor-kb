"""LLM audit of false capability claims in `workflows.annotation` (the FTS-indexed keyword text).

Catalog text was patched in the past to make individual benchmark queries route (e.g. 2026-07-19 R9 fixes
appended "MaxQuant output processing proteinGroups isobaric labeling TMT iTRAQ" to nf-core/proteomicslfq,
an OpenMS mzML label-free pipeline). FTS dominates ranking, so a claim a workflow does not satisfy pulls
other workflows' queries onto it. This pass removes such claims catalog-wide; it never adds text.

Per workflow, model A lists VERBATIM annotation phrases that claim an analysis, input, technology or tool the
workflow does not perform/accept per its description and input kinds; model B confirms each. A removal is
applied only when the phrase occurs verbatim and both models agree. Originals are kept in the output JSONL.

Usage:
  PYTHONPATH=lib python3 -m galaxy.ai.chain_composer.annotation_claim_audit propose --output a.jsonl
  PYTHONPATH=lib python3 -m galaxy.ai.chain_composer.annotation_claim_audit verify --output a.jsonl --verified v.jsonl
  PYTHONPATH=lib python3 -m galaxy.ai.chain_composer.annotation_claim_audit apply --verified v.jsonl --db <db>
"""
from __future__ import annotations

import argparse
import json
import re
import sqlite3
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Dict, List, Optional

from .domain_reclassifier import _DEFAULT_DB, assert_fts_consistent, openrouter_llm

# Upstream-authored annotations are not edited: on Bioconductor rows `annotation` is the package's own
# DESCRIPTION text, and the verifier confused package scope with our narrower wrapper's scope (2026-11-05
# spot check: DSS's own DML/DMR sentence, MassArray's description). Only BioMate-authored keyword text is cleaned.
UPSTREAM_AUTHORED_SOURCES = ("bioconductor",)

_PROPOSE = """You audit the search keywords of one bioinformatics workflow for FALSE claims.

WORKFLOW: {name}
SOURCE: {source}
DESCRIPTION (ground truth): {description}
INPUT KINDS (ground truth): {kinds}
ANNOTATION (search keywords to audit): {annotation}

List phrases from ANNOTATION, copied VERBATIM, that claim an analysis, input data type, technology,
labelling chemistry or tool that this workflow does NOT perform or accept according to the DESCRIPTION and
INPUT KINDS (e.g. a raw-spectra pipeline described as processing another tool's output tables; a label-free
method described as isobaric/TMT; an RNA-seq pipeline described as calling somatic variants).
Do NOT list phrases that are true, merely related, general (e.g. "quantitative proteomics"), organisms the
workflow can run on, or that you are unsure about. Most annotations have nothing to remove.
Reply with ONLY: {{"remove": ["<verbatim phrase>", ...], "reason": "<short>"}}"""

_VERIFY = """A reviewer proposes removing these phrases from a workflow's search keywords because they claim
something the workflow does not do.

WORKFLOW: {name}
DESCRIPTION (may be incomplete): {description}
INPUT KINDS: {kinds}
ANNOTATION: {annotation}
PROPOSED REMOVALS: {remove}

Our DESCRIPTION may be incomplete. Judge each phrase against what the actual tool/pipeline does (use your
knowledge of it, e.g. its documented options) as well as the DESCRIPTION and INPUT KINDS. Answer true only if
the phrase is a FALSE claim — the workflow genuinely does not perform or accept it; false if the capability is
real (even if undescribed), merely related, general, or you are uncertain.
Reply with ONLY: {{"confirm": {{"<phrase>": true|false, ...}}}}"""


def _json(raw: str) -> Optional[dict]:
    raw = raw or ""
    i, j = raw.find("{"), raw.rfind("}")
    if i == -1 or j <= i:
        return None
    try:
        return json.loads(raw[i:j + 1])
    except Exception:  # noqa: BLE001
        return None


def _rows(db: Path, names: Optional[List[str]] = None):
    conn = sqlite3.connect(str(db))
    cols = {r[1] for r in conn.execute("PRAGMA table_info(workflows)")}
    kinds = "COALESCE(input_kinds,'[]')" if "input_kinds" in cols else "'[]'"
    sql = (f"SELECT name, COALESCE(source,''), COALESCE(description,''), {kinds}, annotation, id "
           "FROM workflows WHERE executable=1 AND annotation IS NOT NULL AND length(annotation) > 0")
    rows = conn.execute(sql).fetchall()
    conn.close()
    if names:
        rows = [r for r in rows if r[0] in set(names)]
    return [dict(zip(("name", "source", "description", "kinds", "annotation", "id"), r)) for r in rows]


def propose(db: Path, llm, workers: int, names=None) -> List[Dict]:
    def one(r):
        d = _json(llm(_PROPOSE.format(name=r["name"], source=r["source"], description=r["description"][:1200],
                                      kinds=r["kinds"], annotation=r["annotation"][:1500])))
        if d is None or not isinstance(d.get("remove"), list):
            return {**r, "remove": None, "status": "llm_failed"}
        verbatim = [p for p in d["remove"] if isinstance(p, str) and p.strip() and p in r["annotation"]]
        return {**r, "remove": verbatim, "dropped_nonverbatim": len(d["remove"]) - len(verbatim),
                "reason": str(d.get("reason", ""))[:200], "status": "ok"}
    with ThreadPoolExecutor(max(1, workers)) as ex:
        return list(ex.map(one, _rows(db, names)))


def verify(props: List[Dict], llm, workers: int) -> List[Dict]:
    def one(p):
        if not p.get("remove"):
            return {**p, "confirmed": []}
        d = _json(llm(_VERIFY.format(name=p["name"], description=p["description"][:1200], kinds=p["kinds"],
                                     annotation=p["annotation"][:1500], remove=json.dumps(p["remove"]))))
        conf = (d or {}).get("confirm") or {}
        return {**p, "confirmed": [x for x in p["remove"] if conf.get(x) is True]}
    with ThreadPoolExecutor(max(1, workers)) as ex:
        return list(ex.map(one, props))


def _cleaned_v1(annotation: str, phrases: List[str]) -> str:
    """The first version (2026-11-05, applied to dev): raw substring removal. Kept only so `repair` can
    recognise rows it wrote — it also cut phrases out of longer words ("sam" out of "samtools")."""
    out = annotation
    for ph in sorted(phrases, key=len, reverse=True):
        out = out.replace(ph, " ")
    return re.sub(r"\s{2,}", " ", out).strip()


def cleaned(annotation: str, phrases: List[str]) -> str:
    """Remove each phrase only where it stands as a whole token (not inside a longer word)."""
    out = annotation
    for ph in sorted(phrases, key=len, reverse=True):
        out = re.sub(r"(?<![A-Za-z0-9])" + re.escape(ph) + r"(?![A-Za-z0-9])", " ", out)
    return re.sub(r"\s{2,}", " ", out).strip()


def _where(v: Dict):
    return ("id = ?", v["id"]) if v.get("id") is not None else ("name = ?", v["name"])


def apply(db: Path, verified: List[Dict], exclude_sources=UPSTREAM_AUTHORED_SOURCES) -> int:
    assert_fts_consistent(db)
    conn = sqlite3.connect(str(db))
    n = 0
    for v in verified:
        if v.get("confirmed") and v.get("source") not in set(exclude_sources or ()):
            # guarded by the original text: a row changed since the audit is left alone
            col, key = _where(v)
            n += conn.execute(f"UPDATE workflows SET annotation = ? WHERE {col} AND annotation = ?",
                              (cleaned(v["annotation"], v["confirmed"]), key, v["annotation"])).rowcount
    conn.commit()
    conn.close()
    return n


def repair(db: Path, verified: List[Dict]) -> int:
    """Re-apply the confirmed removals with the token-bounded `cleaned` to rows that still hold exactly what
    `_cleaned_v1` wrote (rows changed since are left alone)."""
    assert_fts_consistent(db)
    conn = sqlite3.connect(str(db))
    n = 0
    for v in verified:
        if v.get("confirmed"):
            old, new = _cleaned_v1(v["annotation"], v["confirmed"]), cleaned(v["annotation"], v["confirmed"])
            if old != new:
                col, key = _where(v)
                n += conn.execute(f"UPDATE workflows SET annotation = ? WHERE {col} AND annotation = ?",
                                  (new, key, old)).rowcount
    conn.commit()
    conn.close()
    return n


def _cli(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("step", choices=["propose", "verify", "apply", "repair"])
    ap.add_argument("--output"); ap.add_argument("--verified"); ap.add_argument("--db", default=str(_DEFAULT_DB))
    ap.add_argument("--model", default="google/gemini-3.8-flash"); ap.add_argument("--verify-model", default="anthropic/claude-sonnet-5.5")
    ap.add_argument("--workers", type=int, default=12); ap.add_argument("--names", default="")
    a = ap.parse_args(argv)
    if a.step == "propose":
        res = propose(Path(a.db), openrouter_llm(a.model), a.workers, [n for n in a.names.split("|") if n] or None)
        with open(a.output, "w") as f:
            for r in res:
                f.write(json.dumps(r) + "\n")
        sys.stderr.write(f"rows {len(res)}; with proposals {sum(1 for r in res if r.get('remove'))}; failed {sum(r['status'] != 'ok' for r in res)}\n")
    elif a.step == "verify":
        res = verify([json.loads(l) for l in open(a.output) if l.strip()], openrouter_llm(a.verify_model), a.workers)
        with open(a.verified, "w") as f:
            for r in res:
                f.write(json.dumps(r) + "\n")
        sys.stderr.write(f"rows with confirmed removals {sum(1 for r in res if r.get('confirmed'))}; phrases {sum(len(r.get('confirmed') or []) for r in res)}\n")
    elif a.step == "repair":
        sys.stderr.write(f"repaired {repair(Path(a.db), [json.loads(l) for l in open(a.verified) if l.strip()])} rows\n")
    else:
        sys.stderr.write(f"updated {apply(Path(a.db), [json.loads(l) for l in open(a.verified) if l.strip()])} rows\n")
    return 0


if __name__ == "__main__":  # pragma: no cover
    sys.exit(_cli(sys.argv[1:]))
