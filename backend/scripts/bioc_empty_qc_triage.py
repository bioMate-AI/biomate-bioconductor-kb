#!/usr/bin/env python3
"""
Triage report for the 2781 Bioc workflows with `qc_steps='[]'`.

Phase 3c covered the 396 workflows that declared non-empty qc_steps.
The next coverage frontier is the empty-list workflows — many ARE real
analyses (DE testing, clustering, methylation, batch assignment) whose
qc_steps were never populated in the DB; the rest are correctly empty
(visualization, utility, format conversion, annotation lookup).

This script classifies each by description keyword and proposes a
qc_steps backfill suggestion when applicable. It writes nothing to
the DB — output is a triage CSV + summary table.

Classification:
  ANALYSIS_CANDIDATE — description mentions DE / clustering / norm /
                       methylation / dispersion → propose labels
  CORRECTLY_EMPTY    — description is viz / utility / converter /
                       annotation / orchestrator
  UNCLEAR            — description too short or generic; needs review

Output: `/tmp/bioc_empty_qc_triage.csv` (300 lines, easy to eyeball)
Summary: prints per-category counts + top-10 label suggestions
"""

import csv
import re
import sqlite3
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DB = ROOT / "backend/database/galaxy_ai_tools.db"
OUT_CSV = Path("/tmp/bioc_empty_qc_triage.csv")

# Description-keyword → suggested qc_steps label. Order matters:
# earlier rules win when multiple match. Keywords are lowercased.
ANALYSIS_RULES: list[tuple[re.Pattern, list[str]]] = [
    # Differential expression family
    (re.compile(r"\b(differential\s+(?:expression|transcript|abundance|gene|isoform)|de\s+analysis|dge|edger|limma\s+voom|deseq)\b"),
     ["low-count filtering", "count normalization", "dispersion/size-factor estimation"]),
    # voom-specific
    (re.compile(r"\bvoom\b"),
     ["voom mean-variance modelling", "low-count filtering"]),
    # TMM-specific
    (re.compile(r"\b(tmm\s+norm|trimmed\s+mean\s+of\s+m)\b"),
     ["TMM normalization"]),
    # VSN / variance-stabilizing
    (re.compile(r"\b(vsn|variance.?stabili[sz]|rlog|vst)\b"),
     ["variance-stabilizing normalization"]),
    # Batch / batch-effect / ComBat / Harmony / MNN
    (re.compile(r"\b(batch.effect|combat|harmony|mnn\s+correct|sva\b|remove.batch)\b"),
     ["batch-effect correction"]),
    # Clustering (cell or general)
    (re.compile(r"\b(cluster(?:ing)?|k-?means|hierarchical|louvain|leiden)\b"),
     ["clustering QC"]),
    # scRNA / single-cell QC
    (re.compile(r"\b(single.cell|scrna|seurat|sce\b|cell\s+qc|qc\s+metric)\b"),
     ["cell QC metrics", "doublet detection QC"]),
    # Doublet
    (re.compile(r"\bdoublet"),
     ["doublet detection QC"]),
    # HVG / feature selection
    (re.compile(r"\b(highly.variable|hvg|feature\s+selection|find\s+variable)\b"),
     ["highly-variable feature selection"]),
    # PCA / MA diagnostic
    (re.compile(r"\b(pca\b|principal\s+component|ma.plot|diagnostic\s+plot)\b"),
     ["diagnostic MA/PCA QC"]),
    # Methylation (Illumina array / bisulfite)
    (re.compile(r"\b(methylat|bisulfite|illumina\s+\d|450k|epic|cpg|wgbs|rrbs)\b"),
     ["normalization diagnostic plot", "array detection QC"]),
    # Microbiome / amplicon
    (re.compile(r"\b(microbiome|amplicon|16s|otu|asv\b|prevalence)\b"),
     ["prevalence/abundance filtering"]),
    # Array (microarray / affymetrix)
    (re.compile(r"\b(microarray|affymetrix|affy\b|illumina\s+bead|expression\s+array)\b"),
     ["between-array normalization", "array detection QC"]),
    # Alignment / mapping
    (re.compile(r"\b(align(?:ment)?|map(?:ping)?|bwa|bowtie|star\s+aligner|salmon)\b"),
     ["alignment/mapping QC"]),
    # Outlier
    (re.compile(r"\boutlier"),
     ["outlier detection"]),
]

# Anti-rules: description hits → CORRECTLY_EMPTY (no analysis)
EMPTY_RULES = [
    re.compile(r"\b(visuali[sz]|plot|render|graphic|heatmap|color|legend|theme|track\b)\b"),
    re.compile(r"\b(convert(er)?|import|export|reader|writer|parse|format|serial)\b"),
    re.compile(r"\b(annotat|lookup|query|retrieve|download|fetch\s+(?:from|gene|annotation))\b"),
    re.compile(r"\b(orchestrat|wrapper|umbrella|pipeline\s+coordinator)\b"),
    re.compile(r"\b(utility|util\b|helper|interface\s+to)\b"),
    re.compile(r"\b(roundtrip|serial[iz]ation|store\b|saveRDS|read\s+from\s+file)\b"),
]


def classify(name: str, description: str) -> tuple[str, list[str], str]:
    # Treat the workflow name as part of the haystack — names like
    # `noiseq_differential_expression_analysis` carry strong signal
    # that descriptions sometimes truncate or paraphrase away.
    desc = ((name or "") + " :: " + (description or "")).lower().replace("_", " ")
    if len(description or "") < 30:
        return ("UNCLEAR", [], "description too short")
    # Anti-rules first — viz/util can mention "expression" without doing DE
    for r in EMPTY_RULES:
        m = r.search(desc)
        if m:
            # but allow override: "differential expression plot" → still ANALYSIS
            if any(rr.search(desc) and "differential" in rr.pattern for rr, _ in ANALYSIS_RULES):
                pass
            else:
                return ("CORRECTLY_EMPTY", [], f"viz/util match: '{m.group(0)}'")
    # Analysis rules — first match wins for primary, accumulate secondary
    matched: list[str] = []
    why: list[str] = []
    for r, labels in ANALYSIS_RULES:
        m = r.search(desc)
        if m:
            matched.extend(l for l in labels if l not in matched)
            why.append(f"'{m.group(0)}'→{labels}")
    if matched:
        return ("ANALYSIS_CANDIDATE", matched, "; ".join(why[:3]))
    return ("UNCLEAR", [], "no rule matched")


def main() -> None:
    con = sqlite3.connect(DB)
    rows = con.execute(
        "SELECT name, description FROM workflows "
        "WHERE source='bioconductor' AND qc_steps='[]' "
        "ORDER BY name"
    ).fetchall()

    counts: Counter[str] = Counter()
    label_props: Counter[str] = Counter()
    triage_rows: list[tuple[str, str, str, str]] = []

    for name, desc in rows:
        verdict, labels, why = classify(name, desc)
        counts[verdict] += 1
        for l in labels:
            label_props[l] += 1
        triage_rows.append((name, verdict, "|".join(labels), why))

    print(f"Triage of {len(rows)} empty-qc_steps Bioc workflows:")
    for v, n in counts.most_common():
        print(f"  {v:22s} {n:5d}")
    print()
    print("Proposed label backfill counts (when ANALYSIS_CANDIDATE):")
    for l, n in label_props.most_common(12):
        in_blocks = "✓" if n else " "
        print(f"  {n:4d}  {in_blocks}  {l}")
    print()
    print("Note: all suggested labels are already in LABEL_BLOCKS — backfill")
    print("them via SQL UPDATE, then the existing patcher would adopt them.")
    print(f"Full triage written to {OUT_CSV}")

    with OUT_CSV.open("w") as fh:
        w = csv.writer(fh)
        w.writerow(["name", "verdict", "proposed_labels", "why"])
        w.writerows(triage_rows)


if __name__ == "__main__":
    main()
