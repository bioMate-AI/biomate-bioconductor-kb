#!/usr/bin/env python3
"""
harvest_catalog.py — Harvest BioMate's enriched workflow catalog into coding-track pairs.

For EVERY catalog workflow row in backend/database/galaxy_ai_tools.db it emits one JSONL
record {id, name, domain, description, params, steps, nextflow_path, provenance_tier,
real_exec_status, source, nf_code?} to catalog_pairs.jsonl.

Provenance tiers (per-row, exact, testable):
  receipted : real_exec_status IN ('ok','ok_warnings')  -> committed execution receipt (GOLD)
  curated   : no receipt, BUT nextflow_path resolves to a real, substantive .nf on disk
  stub      : no receipt AND no local .nf (index-only / external module not vendored here)

Dedup: the catalog's `filename` column is UNIQUE, so nextflow_path is already dedup'd at the
catalog level (one record per catalog workflow). The repo has MORE .nf files on disk than the
catalog has rows (disk includes duplicate copies + generated stubs never indexed); we reconcile
by reporting both counts and only ever emitting one record per catalog row.

Leakage: a family-level holdout flag (holdout=true) is set for any row whose workflow family
appears in the eval/benchmark sets (nextflow_coding + the eval-case yaml `workflow:` refs).
Holdout rows stay in the harvest (no data exclusion) but MUST be excluded from any SFT export.

Writes manifest.json (committed) with per-tier counts, yields, sizes, sha256.
"""
import json, os, re, sqlite3, hashlib, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
DB = os.path.join(REPO, "backend", "database", "galaxy_ai_tools.db")
OUT = os.path.join(HERE, "catalog_pairs.jsonl")
MANIFEST = os.path.join(HERE, "manifest_catalog.json")
EVAL_DIR = os.path.join(REPO, "evaluation", "datasets")

# nextflow_path is relative; try these roots in order.
NF_ROOTS = [
    os.path.join(REPO, "backend", "biomni_workflows"),
    os.path.join(REPO, "backend"),
    REPO,
]


def resolve_nf(filename):
    """Resolve a catalog filename to an actual .nf on disk, or None."""
    if not filename:
        return None
    cands = []
    for root in NF_ROOTS:
        cands.append(os.path.join(root, filename))
        if not filename.endswith(".nf"):
            cands.append(os.path.join(root, filename, "main.nf"))
            cands.append(os.path.join(root, filename + ".nf"))
    for c in cands:
        if os.path.isfile(c):
            return c
    return None


def family_of(name, filename, domain):
    """
    Derive a coarse workflow 'family' slug for family-level leakage splitting.
    nf-core pipelines collapse to their base (rnaseq, sarek, ...); subworkflows/bioconductor
    collapse to the leaf directory / package slug.
    """
    fn = (filename or "").lower()
    # leaf of path, dropping trailing /main.nf
    leaf = fn
    if leaf.endswith("/main.nf"):
        leaf = leaf[: -len("/main.nf")]
    leaf = leaf.rsplit("/", 1)[-1]
    leaf = re.sub(r"\.nf$", "", leaf)
    # strip common vendor prefixes already handled by leaf; normalise separators
    slug = re.sub(r"[^a-z0-9]+", "", leaf)
    # also a name-based slug
    nslug = re.sub(r"[^a-z0-9]+", "", (name or "").lower())
    return slug, nslug


def load_holdout_families():
    """
    Build the set of workflow-family tokens referenced by any eval/benchmark set.
    Sources:
      - evaluation/datasets/*/cases.yaml : `workflow:` values
      - evaluation/datasets/nextflow_coding/ : generic, tool-free (no bio families) -> none
    Returns a set of normalised family tokens.
    """
    toks = set()
    import glob

    for cases in glob.glob(os.path.join(EVAL_DIR, "*", "cases.yaml")):
        try:
            txt = open(cases, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        for m in re.finditer(r"workflow:\s*([A-Za-z0-9/_.-]+)", txt):
            raw = m.group(1).strip().lower()
            if raw in ("null", "none", ""):
                continue
            # normalise: drop vendor prefixes, take leaf, strip separators
            leaf = raw.split("/")[-1]
            leaf = re.sub(r"\.nf$", "", leaf)
            slug = re.sub(r"[^a-z0-9]+", "", leaf)
            if slug:
                toks.add(slug)
    return toks


def parse_params(params_schema):
    """Split params_schema JSON into required/optional param lists + data_inputs."""
    required, optional, data_inputs = [], [], []
    if not params_schema:
        return {"required": required, "optional": optional, "data_inputs": data_inputs}
    try:
        ps = json.loads(params_schema)
    except (json.JSONDecodeError, TypeError):
        return {"required": required, "optional": optional, "data_inputs": data_inputs}
    for p in ps.get("parameters", []) or []:
        entry = {
            "name": p.get("name"),
            "type": p.get("type"),
            "default": p.get("default"),
            "allowed_values": p.get("allowed_values") or [],
            "description": p.get("description"),
        }
        if p.get("optional"):
            optional.append(entry)
        else:
            required.append(entry)
    for d in ps.get("data_inputs", []) or []:
        data_inputs.append(
            {
                "name": d.get("name"),
                "type": d.get("type"),
                "optional": d.get("optional"),
                "description": d.get("description"),
            }
        )
    return {"required": required, "optional": optional, "data_inputs": data_inputs}


def parse_steps(step_metadata):
    """Extract a compact step list from step_metadata JSON."""
    if not step_metadata:
        return []
    try:
        sm = json.loads(step_metadata)
    except (json.JSONDecodeError, TypeError):
        return []
    out = []
    if isinstance(sm, list):
        for s in sm:
            if not isinstance(s, dict):
                continue
            out.append(
                {
                    "step": s.get("step"),
                    "phase": s.get("phase"),
                    "outputs": s.get("outputs") or [],
                    "params": [p.get("name") for p in (s.get("params") or []) if isinstance(p, dict)],
                }
            )
    return out


def main():
    if not os.path.isfile(DB):
        print(f"FATAL: DB not found at {DB}", file=sys.stderr)
        sys.exit(1)
    size_mb = os.path.getsize(DB) / 1e6
    con = sqlite3.connect(DB)
    con.row_factory = sqlite3.Row
    total = con.execute("SELECT count(*) AS c FROM workflows").fetchone()["c"]
    print(f"DB: {DB}  ({size_mb:.1f} MB)  workflows rows = {total}")

    holdout_fams = load_holdout_families()
    print(f"holdout family tokens (from eval cases.yaml): {len(holdout_fams)}")

    rows = con.execute(
        """SELECT id, name, domain, description, filename, source, format,
                  real_exec_status, params_schema, step_metadata
           FROM workflows ORDER BY id"""
    ).fetchall()

    tiers = {"receipted": 0, "curated": 0, "stub": 0}
    holdout_n = 0
    with_code = 0
    seen_paths = set()
    dupes = 0

    with open(OUT, "w", encoding="utf-8") as f:
        for r in rows:
            fn = r["filename"]
            if fn in seen_paths:
                dupes += 1
                continue
            seen_paths.add(fn)

            status = r["real_exec_status"]
            disk = resolve_nf(fn)
            nf_code = None
            if disk:
                try:
                    nf_code = open(disk, encoding="utf-8", errors="replace").read()
                except OSError:
                    nf_code = None

            if status in ("ok", "ok_warnings"):
                tier = "receipted"
            elif disk and nf_code:
                tier = "curated"
            else:
                tier = "stub"
            tiers[tier] += 1
            if nf_code:
                with_code += 1

            slug, nslug = family_of(r["name"], fn, r["domain"])
            is_holdout = bool(
                (slug and slug in holdout_fams) or (nslug and nslug in holdout_fams)
            )
            if is_holdout:
                holdout_n += 1

            rec = {
                "id": r["id"],
                "name": r["name"],
                "domain": r["domain"],
                "description": r["description"],
                "params": parse_params(r["params_schema"]),
                "steps": parse_steps(r["step_metadata"]),
                "nextflow_path": fn,
                "provenance_tier": tier,
                "real_exec_status": status,
                "source": r["source"],
                "format": r["format"],
                "family": slug,
                "holdout": is_holdout,
                "nf_resolved_path": (os.path.relpath(disk, REPO) if disk else None),
                "nf_code": nf_code,
            }
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")

    out_size = os.path.getsize(OUT)
    sha = hashlib.sha256(open(OUT, "rb").read()).hexdigest()
    disk_nf = int(
        os.popen(f"find {REPO} -name '*.nf' -type f 2>/dev/null | wc -l").read().strip() or 0
    )

    manifest = {
        "generated_from": os.path.relpath(DB, REPO),
        "db_size_mb": round(size_mb, 1),
        "catalog_rows": total,
        "emitted_records": sum(tiers.values()),
        "duplicate_paths_skipped": dupes,
        "tiers": tiers,
        "records_with_nf_code": with_code,
        "holdout_records": holdout_n,
        "holdout_family_tokens": sorted(holdout_fams),
        "nf_files_on_disk_repo": disk_nf,
        "output_file": os.path.basename(OUT),
        "output_bytes": out_size,
        "output_sha256": sha,
    }
    json.dump(manifest, open(MANIFEST, "w"), indent=2)
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
