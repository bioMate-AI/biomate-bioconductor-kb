#!/usr/bin/env python3
"""
PER-STEP PARAMETER attribution for each Bioconductor workflow.

Workflow-level params already exist in the `params_schema` column (typed + described,
17k+ params), but the per-step `step_metadata` entries carry only
{step, phase, outputs, visualizations, qc} — no params. The UI per-step path
(nextflow-workflow-viewer.tsx `step.parameters`, step-adjust-modal.tsx) therefore
renders nothing editable per step. This enricher attributes each workflow-level param
to the step(s) whose R section body references it, and writes them back into each
`step_metadata` entry so the serving layer can forward them to `step.parameters`.

ALIGNMENT WITH THE LIVE UI CONTRACT
-----------------------------------
The viewer renders `step.parameters` as a flat `Record<string, value>`:
  - inline preview:  Object.entries(step.parameters).map(([k,v]) => `${k}: ${v}`)
  - step-adjust-modal seeds overrides with `{ ...step.parameters }` (name -> value),
    and infers each widget's type from the *value* and from the workflow-level
    required_params/optional_params (matched by name) — NOT from a nested object.

So the SERVED `step.parameters` must be `{ name: default_value }`. To keep the stored
data rich + auditable (type/description/options the modal/parameter-group can use), we
store a `params` LIST of objects on each step_metadata entry:

  "params": [
    { "name": "n", "type": "number", "default": 10,
      "description": "Number of top genes", "options": [] }, ...
  ]

and the serving layer (nextflow_executor._steps_from_db_metadata) flattens it to
`parameters: { name: default }` for the UI. This script writes the LIST; the serving
change does the flatten. Each param object carries exactly what step-adjust-modal /
parameter-group consume: name, type in {string,number,boolean,select,file}, default,
description, options[].

Mirrors enrich_bioc_step_metadata.py / enrich_bioc_viz_qc.py: --dry-run, --no-db,
auto-backup before write, idempotent. DB path overridable via --db or
BIOC_PARAMS_DB env (so it can run against a COPY, never the canonical DB by accident).

Usage:
  python3 backend/scripts/enrich_bioc_step_params.py --db /tmp/params_test.db [--dry-run]
"""
from __future__ import annotations
import argparse, json, os, re, shutil, sqlite3, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from enrich_bioc_viz_qc import extract_r  # shared R-body extractor

BIOC = HERE.parents[0] / "biomni_workflows/nextflow_nfcore/subworkflows/bioconductor"
REL = "nextflow_nfcore/subworkflows/bioconductor"
DEFAULT_DB = Path("/home/yzhang/biomate/backend/database/galaxy_ai_tools.db")

# The 5 widget types parameter-group.tsx renders. Map schema types onto them.
_TYPE_MAP = {
    "string": "string", "str": "string", "text": "string",
    "number": "number", "int": "number", "integer": "number",
    "float": "number", "double": "number", "numeric": "number",
    "boolean": "boolean", "bool": "boolean", "flag": "boolean",
    "file": "file", "path": "file", "data": "file",
    "select": "select", "enum": "select", "choice": "select",
}
# Param names whose value is a file path / dataset, even if schema type is "string".
_FILE_SUFFIXES = ("_path", "_paths", "_dir", "_directory", "_input", "_inputs",
                  "_output", "_file", "_files", "_csv", "_tsv", "_fasta", "_fa",
                  "_rds", "_bam", "_vcf", "_gtf", "_gff", "_bed")


def ui_type(p: dict) -> str:
    """Map a params_schema param onto one of the 5 UI widget types."""
    name = str(p.get("name", "")).lower()
    allowed = p.get("allowed_values") or []
    raw = str(p.get("type", "string")).lower()
    if allowed:                      # constrained vocabulary -> dropdown
        return "select"
    if name.endswith(_FILE_SUFFIXES) or raw in ("file", "path", "data"):
        return "file"
    return _TYPE_MAP.get(raw, "string")


def param_obj(p: dict, is_input: bool = False) -> dict:
    """Build the rich per-param object stored on the step (serving flattens default)."""
    t = "file" if is_input else ui_type(p)
    options = []
    for v in (p.get("allowed_values") or []):
        options.append({"label": str(v), "value": v})
    return {
        "name": p.get("name"),
        "type": t,
        "default": p.get("default"),
        "description": (p.get("description") or "").strip(),
        "options": options,
        "required": (not p.get("optional", True)) if not is_input else False,
    }


def split_sections(r: str) -> list[tuple[str, str]]:
    """(header, body) sections from the R, trying each marker convention in turn:
    `# N. Name`, `# STAGE N: Name`, `# --- Name ---`. Matches how the corpus is
    commented (enrich_bioc_step_metadata uses `# N.`; many workflows use STAGE/dash)."""
    for pat in (
        r'\n\s*#\s*(\d+)\.\s+(.+?)[ \t]*\n',
        r'\n\s*#\s*STAGE\s+\d+\s*:?\s*(.+?)[ \t]*\n',
        r'\n\s*#\s*-{2,}\s*(.+?)\s*-{2,}[ \t]*\n',
    ):
        ms = list(re.finditer(pat, r, re.I))
        if len(ms) >= 2:
            secs = []
            for i, m in enumerate(ms):
                head = m.groups()[-1].strip()
                body = r[m.end():(ms[i + 1].start() if i + 1 < len(ms) else len(r))]
                secs.append((head, body))
            return secs
    return []


_WORD = re.compile(r'[a-z0-9]+')


def _toks(s: str) -> set:
    return set(_WORD.findall(s.lower()))


def align_sections_to_steps(steps: list[dict], secs: list[tuple[str, str]]) -> list[str]:
    """For each step_metadata entry, return the R section BODY that best matches it.

    Match by token Jaccard between the step name and section header; fall back to
    positional (index) alignment, and to the whole-R concatenation when there are no
    sections. This makes param attribution robust to section-count != step-count."""
    if not secs:
        whole = "\n".join(b for _, b in secs) if secs else ""
        return ["" for _ in steps]
    bodies = []
    used = set()
    for i, st in enumerate(steps):
        st_toks = _toks(st.get("step", ""))
        best, best_score = -1, 0.0
        for j, (head, _b) in enumerate(secs):
            ht = _toks(head)
            if not st_toks or not ht:
                continue
            score = len(st_toks & ht) / len(st_toks | ht)
            if score > best_score:
                best, best_score = j, score
        if best_score >= 0.34 and best not in used:
            bodies.append(secs[best][1]); used.add(best)
        elif i < len(secs):                  # positional fallback
            bodies.append(secs[i][1])
        else:
            bodies.append(secs[-1][1])
    return bodies


def attribute(params: list[dict], inputs: list[dict],
              steps: list[dict], r: str) -> list[list[dict]]:
    """Return a list parallel to `steps`: each element is the list of param objects
    attributed to that step. A param lands on every step whose section body references
    its name as a token; params referenced in no section (workflow-level inputs /
    setup-stage values) land on the FIRST step so they stay editable."""
    secs = split_sections(r)
    bodies = align_sections_to_steps(steps, secs)
    per_step: list[list[dict]] = [[] for _ in steps]
    seen_per_step: list[set] = [set() for _ in steps]

    all_param_objs = [param_obj(p) for p in params] + [param_obj(d, is_input=True) for d in inputs]

    for obj in all_param_objs:
        nm = obj.get("name")
        if not nm:
            continue
        pat = re.compile(r'\b' + re.escape(str(nm)) + r'\b')
        hit_idxs = [i for i, b in enumerate(bodies) if b and pat.search(b)]
        if not hit_idxs:
            hit_idxs = [0]                    # unreferenced -> first (setup/input) step
        for i in hit_idxs:
            if nm not in seen_per_step[i]:
                per_step[i].append(obj)
                seen_per_step[i].add(nm)
    return per_step


def enrich_workflow(params_schema: dict, step_metadata: list, r: str) -> list:
    """Return step_metadata with a `params` list added to each step (idempotent:
    replaces any prior `params`)."""
    params = params_schema.get("parameters", []) if isinstance(params_schema, dict) else []
    inputs = params_schema.get("data_inputs", []) if isinstance(params_schema, dict) else []
    if not isinstance(step_metadata, list) or not step_metadata:
        return step_metadata
    per_step = attribute(params, inputs, step_metadata, r)
    out = []
    for st, plist in zip(step_metadata, per_step):
        st2 = dict(st)
        st2["params"] = plist
        out.append(st2)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--no-db", action="store_true")
    ap.add_argument("--db", default=os.environ.get("BIOC_PARAMS_DB", str(DEFAULT_DB)))
    args = ap.parse_args()

    db = Path(args.db)
    if str(db.resolve()) == str(DEFAULT_DB.resolve()) and not (args.dry_run or args.no_db):
        print(f"[step-params] REFUSING to write canonical DB {db}. "
              f"Run with --db /tmp/params_test.db (work on a copy).", file=sys.stderr)
        return 2
    if not db.exists():
        print(f"[step-params] DB not found: {db}", file=sys.stderr)
        return 2

    con = sqlite3.connect(str(db)); cur = con.cursor()
    rows = cur.execute(
        "SELECT filename, params_schema, step_metadata FROM workflows "
        "WHERE source='bioconductor' AND step_metadata IS NOT NULL AND step_metadata!=''"
    ).fetchall()

    nf_cache: dict[str, str] = {}

    # `filename` in the DB is "<REL>/<dir>/<name>.nf"; BIOC == <backend>/<REL>, so
    # the .nf lives at <backend>/biomni_workflows/<filename>.
    BACKEND = HERE.parents[0]

    def read_r(fn: str) -> str:
        if fn in nf_cache:
            return nf_cache[fn]
        path = BACKEND / "biomni_workflows" / fn
        r = ""
        if path.exists():
            r = extract_r(path.read_text(errors="replace"))
        nf_cache[fn] = r
        return r

    updates: list[tuple[str, str]] = []
    n_wf = n_wf_params = n_steps = n_steps_params = total_params = 0
    sample = None

    for fn, ps, sm in rows:
        try:
            psj = json.loads(ps) if ps else {}
            smj = json.loads(sm) if sm else []
        except Exception:
            continue
        if not isinstance(smj, list) or not smj:
            continue
        r = read_r(fn)
        enriched = enrich_workflow(psj, smj, r)
        n_wf += 1
        wf_has = any(s.get("params") for s in enriched)
        if wf_has:
            n_wf_params += 1
        for s in enriched:
            n_steps += 1
            if s.get("params"):
                n_steps_params += 1
                total_params += len(s["params"])
        if sample is None and wf_has and len(enriched) >= 3:
            sample = (fn, smj, enriched)
        updates.append((fn, json.dumps(enriched)))

    print(f"[step-params] workflows processed: {n_wf}")
    print(f"[step-params] workflows with >=1 step carrying params: {n_wf_params} "
          f"({100*n_wf_params/max(1,n_wf):.1f}%)")
    print(f"[step-params] steps total: {n_steps} | steps with params: {n_steps_params} "
          f"({100*n_steps_params/max(1,n_steps):.1f}%) | param attributions: {total_params}")

    if sample:
        fn, before, after = sample
        print(f"\n[step-params] SAMPLE {fn}")
        print("  BEFORE step[0]:", json.dumps({k: before[0].get(k) for k in before[0]}, default=str)[:300])
        print("  AFTER  step[0].params:", json.dumps(after[0].get("params"), default=str)[:500])

    if args.dry_run or args.no_db:
        con.close()
        return 0

    bak = db.with_suffix(f".db.bak.{int(time.time())}")
    shutil.copy(db, bak)
    u = 0
    for fn, sm_json in updates:
        u += cur.execute(
            "UPDATE workflows SET step_metadata=? WHERE source='bioconductor' AND filename=?",
            (sm_json, fn)).rowcount
    con.commit(); con.close()
    print(f"[step-params] DB updated: {u} rows (backup {bak.name})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
