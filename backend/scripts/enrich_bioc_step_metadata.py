#!/usr/bin/env python3
"""
PER-STEP structured metadata (outputs + visualization + QC) for each Bioconductor
workflow — the structure BioMate needs to visualize each step's output and surface
its QC.

A workflow's R is organized into sections (`# --- Step Name [Phase] ---`). Each
section is a STEP that produces specific outputs (write.csv/ggsave/pdf/saveRDS) using
specific visualization functions and QC operations. This parses those sections and
emits, per workflow, a `step_metadata` JSON array:

  [{ "step": "GO Over-Representation Analysis", "phase": "Core Analysis",
     "outputs": [{"file": "enrichGO_results.csv", "kind": "table"}],
     "visualizations": ["dot plot","enrichment map"], "qc": ["low-count filtering"] }, ...]

stored in DB column `step_metadata` so the UI can render per-step output viz + QC.
Reuses the viz/QC vocab from enrich_bioc_viz_qc. Usage: [--dry-run] [--no-db]
"""
from __future__ import annotations
import argparse, json, re, shutil, sqlite3, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from enrich_bioc_viz_qc import (  # shared vocab
    VIZ_FUNCS, QC_PATTERNS, GENERIC_VIZ, extract_r, viz_from_figure_files)

BIOC = HERE.parents[0] / "biomni_workflows/nextflow_nfcore/subworkflows/bioconductor"
DB = Path("/home/yzhang/biomate/backend/database/galaxy_ai_tools.db")
REL = "nextflow_nfcore/subworkflows/bioconductor"


def out_kind(fn: str) -> str:
    e = fn.lower().rsplit(".", 1)[-1]
    return {"csv": "table", "tsv": "table", "txt": "text", "pdf": "figure",
            "png": "figure", "tiff": "figure", "svg": "figure", "rds": "object",
            "rdata": "object", "html": "report"}.get(e, "file")


def section_outputs(code: str) -> list[dict]:
    files = []
    for m in re.findall(r'(?:write\.[a-z]+|write_[a-z]+|ggsave|saveRDS|pdf|png|tiff|svg|writeLines|saveWidget)\('
                        r'[^)]*?["\']([A-Za-z0-9_./-]+\.(?:csv|tsv|txt|pdf|png|tiff|svg|rds|rdata|html))["\']', code):
        if m not in [f["file"] for f in files] and not m.startswith("*"):
            files.append({"file": m, "kind": out_kind(m)})
    return files[:12]


def section_viz(code: str, outputs: list[dict]) -> list[str]:
    out = []
    for fn, label in VIZ_FUNCS.items():
        if re.search(r'\b' + re.escape(fn) + r'\s*\(', code) and label not in out:
            out.append(label)
    # generic plotting (ggplot/ggsave/pdf/png/...) with no named function -> derive a
    # specific label from the figure output filenames (pca_plot.pdf -> "PCA plot").
    figs = [o["file"] for o in outputs if o.get("kind") == "figure"]
    if figs or any(g in code for g in GENERIC_VIZ):
        for label in viz_from_figure_files(figs):
            if label not in out:
                out.append(label)
        if not out:
            out.append("plot")
    return out


def section_qc(code: str) -> list[str]:
    out = []
    for pat, label in QC_PATTERNS:
        if re.search(pat, code) and label not in out:
            out.append(label)
    return out


def phase_map(content: str) -> dict:
    """{step_number: phase} from the // Steps: header (//  * N. [Phase] name)."""
    return {n: ph.strip() for n, ph, _ in
            re.findall(r'//\s*\*\s*(\d+)\.\s*(?:\[([^\]]+)\]\s*)?(.+)', content)}


def header_steps(content: str) -> list[tuple]:
    """(num, phase, description) from the // Steps: header."""
    return [(n, (ph or "").strip(), desc.strip()) for n, ph, desc in
            re.findall(r'//\s*\*\s*(\d+)\.\s*(?:\[([^\]]+)\]\s*)?(.+)', content)]


def _attach_idx(steps: list[dict], keys: tuple, fallback: int) -> int:
    """Index of the step whose description best signals this concern; else fallback."""
    for i, s in enumerate(steps):
        if any(k in s["step"].lower() for k in keys):
            return i
    return fallback


def steps_from_header(content: str, r: str) -> list[dict]:
    """Fallback for workflows whose R has no `# N.` sections: build steps from the
    `// Steps:` header and attach whole-R outputs/viz/QC to the semantically-matching step,
    so per-step visualizations + QC are still surfaced (derived from the real R, not faked)."""
    hs = header_steps(content)
    if not hs:
        return []
    steps = [{"step": desc, "phase": ph, "outputs": [], "visualizations": [], "qc": []}
             for _, ph, desc in hs]
    all_out = section_outputs(r)
    all_viz = section_viz(r, all_out)
    all_qc = section_qc(r)
    if all_viz:
        i = _attach_idx(steps, ("plot", "visuali", "view", "figure", "heatmap", "pca",
                                "umap", "tsne", "volcano", "diagram"), len(steps) - 1)
        steps[i]["visualizations"] = all_viz
    if all_qc:
        i = _attach_idx(steps, ("filter", "normaliz", "qc", "quality", "outlier",
                                "disp", "doublet", "prepar", "construct"), 0)
        steps[i]["qc"] = all_qc
    if all_out:
        steps[_attach_idx(steps, ("result", "output", "write", "save", "export",
                                  "extract", "view"), len(steps) - 1)]["outputs"] = all_out
    return steps


def synth_single_step(content: str, r: str) -> list[dict]:
    """Last-resort fallback for old-style workflows with neither `# N.` R sections nor a
    `// Steps:` header: surface a single analysis step carrying the whole-R outputs/viz/QC so
    the panel still shows what plots + QC the workflow produces (derived from real R)."""
    all_out = section_outputs(r)
    all_viz = section_viz(r, all_out)
    all_qc = section_qc(r)
    if not (all_out or all_viz or all_qc):
        return []
    m = re.search(r'//\s*Bioconductor workflow:\s*(.+)', content)
    name = m.group(1).strip() if m else "Analysis"
    return [{"step": name, "phase": "Core Analysis", "outputs": all_out,
             "visualizations": all_viz, "qc": all_qc}]


def step_meta(content: str) -> list[dict]:
    # the v3 R uses numbered section comments: "# N. Step name"; split on those
    r = extract_r(content)
    pmap = phase_map(content)
    markers = list(re.finditer(r'\n\s*#\s*(\d+)\.\s+(.+?)[ \t]*\n', r))
    if not markers:
        # R isn't section-commented -> derive steps from the // Steps: header, else synthesize
        # a single analysis step so the workflow's plots + QC still surface.
        return steps_from_header(content, r) or synth_single_step(content, r)
    steps = []
    for i, m in enumerate(markers):
        num, name = m.group(1), m.group(2).strip()
        body = r[m.end(): (markers[i + 1].start() if i + 1 < len(markers) else len(r))]
        outs = section_outputs(body)
        steps.append({"step": name, "phase": pmap.get(num, ""),
                      "outputs": outs,
                      "visualizations": section_viz(body, outs),
                      "qc": section_qc(body)})
    return steps


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--no-db", action="store_true")
    args = ap.parse_args()
    rows = {}
    n = nsteps = 0
    for nf in BIOC.rglob("*.nf"):
        c = nf.read_text(errors="replace")
        if "Document-derived" not in c and "real input-consuming" not in c:
            continue
        sm = step_meta(c)
        rows[f"{REL}/{nf.parent.name}/{nf.name}"] = sm
        n += 1; nsteps += len(sm)
    avg = nsteps / max(1, n)
    print(f"[stepmeta] {n} workflows, {nsteps} steps ({avg:.1f}/wf); "
          f"steps with viz: {sum(1 for sm in rows.values() for s in sm if s['visualizations'])}, "
          f"with outputs: {sum(1 for sm in rows.values() for s in sm if s['outputs'])}")
    if args.dry_run or args.no_db:
        # show a sample
        for k in list(rows)[:1]:
            print(json.dumps(rows[k], indent=1)[:600])
        return 0
    bak = DB.with_suffix(f".db.bak.{int(time.time())}")
    shutil.copy(DB, bak)
    con = sqlite3.connect(str(DB)); cur = con.cursor()
    cols = {r[1] for r in cur.execute("PRAGMA table_info(workflows)")}
    if "step_metadata" not in cols:
        cur.execute("ALTER TABLE workflows ADD COLUMN step_metadata TEXT")
    u = 0
    for fn, sm in rows.items():
        u += cur.execute("UPDATE workflows SET step_metadata=? WHERE source='bioconductor' AND filename=?",
                         (json.dumps(sm), fn)).rowcount
    con.commit(); con.close()
    print(f"[stepmeta] DB: step_metadata column + {u} rows updated (backup {bak.name})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
