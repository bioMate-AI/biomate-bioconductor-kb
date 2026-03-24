#!/usr/bin/env nextflow
/*
 * drug_discovery/drug_moa_rnaseq
 *
 * Drug Mechanism-of-Action (MoA) Characterisation from RNA-seq Data.
 * Fills Gap 9 in BioMate's drug discovery opportunity analysis.
 *
 * Pipeline Steps:
 * 1. DIFFERENTIAL_EXPRESSION — Identify significantly DE genes between
 *    drug-treated and control samples using DESeq2 (live) or seeded
 *    synthetic data (mock); outputs ranked gene TSV and volcano JSON.
 * 2. GENE_SET_ENRICHMENT    — Run GSEA against MSigDB Hallmark gene sets
 *    (fgsea live; synthetic NES scores mock). Identifies enriched pathways
 *    and writes enrichment TSV + plot JSON.
 * 3. LINCS_CMAP_LOOKUP      — Match drug-induced transcriptomic signature
 *    against LINCS L1000 / CMap to identify similar drugs and confirm MoA.
 *    Outputs cmap_matches TSV and JSON.
 * 4. MOA_REPORT             — Aggregates DE, GSEA, and CMap results into
 *    an HTML report and JSON summary with PASS / WARN / FAIL QC status.
 *
 * QC thresholds:
 *   PASS  — ≥ 10 significant DE genes (padj < 0.05, |log2FC| > 1)
 *   WARN  — 5–9 significant DE genes
 *   FAIL  — < 5 significant DE genes
 *
 * References:
 *  - DESeq2:    Love et al. Genome Biology 2014 (doi:10.1186/s13059-014-0550-8)
 *  - fgsea:     Korotkevich et al. bioRxiv 2021 (github.com/ctlab/fgsea)
 *  - CMap/LINCS: Subramanian et al. Cell 2017 (doi:10.1016/j.cell.2017.10.049)
 *  - MSigDB Hallmark: Liberzon et al. Cell Systems 2015
 */

nextflow.enable.dsl = 2

// ============================================================================
// Default Parameters
// ============================================================================

params.outdir           = './results/drug_moa_rnaseq'
params.publish_dir_mode = 'copy'

// Mode flags
params.mock_mode        = true    // true = synthetic output, no real tools needed

// Drug / experiment parameters
params.drug_name        = 'Imatinib'
params.target_gene      = 'BCR-ABL1'
params.n_replicates     = 3

// Live-mode paths
params.gmt_file         = null   // falls back to gseapy built-in hallmarks if not provided
params.treated_counts   = null   // TSV count matrix: genes × treated-samples (live mode)
params.control_counts   = null   // TSV count matrix: genes × control-samples (live mode)

// ============================================================================
// Helper functions
// ============================================================================

def log_workflow_header() {
    log.info """
    ====================================================================
    BioMate | Drug MoA Characterisation from RNA-seq  (Gap 9)
    ====================================================================
    Mode:        ${params.mock_mode ? 'MOCK (synthetic data)' : 'LIVE (DESeq2 + fgsea + CMap)'}
    Drug:        ${params.drug_name}
    Target gene: ${params.target_gene}
    Replicates:  ${params.n_replicates}
    GMT file:    ${params.gmt_file}
    Output dir:  ${params.outdir}
    ====================================================================
    """.stripIndent()
}

// ============================================================================
// Process 1: Differential Expression Analysis
// ============================================================================

process DIFFERENTIAL_EXPRESSION {
    tag "${params.drug_name}_vs_control"
    label 'process_medium'
    publishDir "${params.outdir}/01_differential_expression", mode: params.publish_dir_mode

    container 'biomate/biomni-drug-discovery-nf:latest'

    input:
    path treated_counts   // count matrix TSV: genes × treated samples (placeholder in mock mode)
    path control_counts   // count matrix TSV: genes × control samples

    output:
    path "de_results.tsv",    emit: de_results
    path "volcano_data.json", emit: volcano_data
    path "versions.yml",      emit: versions

    script:
    def mock        = params.mock_mode
    def drug_name   = params.drug_name
    def target_gene = params.target_gene
    def n_reps      = params.n_replicates
    """
    if [ "${mock}" = "true" ]; then
        python3 << 'EOF'
import json
import math
import random
from datetime import datetime

random.seed(42)

drug_name   = "${drug_name}"
target_gene = "${target_gene}"
n_reps      = int("${n_reps}")

# ---------------------------------------------------------------------------
# Biologically plausible kinase-pathway genes for kinase inhibitor targets
# ---------------------------------------------------------------------------
KINASE_GENES = [
    "MAPK1", "PIK3CA", "AKT1", "STAT3", "MYC",
    "CDK2",  "BCL2",   "EGFR", "KRAS",  "TP53",
    "MTOR",  "RAF1",   "BRAF", "JAK2",  "SRC",
    "RB1",   "CCND1",  "CDKN1A", "MDM2", "PTEN",
]

# Pad to 200 genes with generic identifiers
generic_genes = [f"GENE{i:04d}" for i in range(1, 181)]
all_genes     = KINASE_GENES + generic_genes
random.shuffle(all_genes)
all_genes     = all_genes[:200]

# ---------------------------------------------------------------------------
# Assign DE statistics
# ~20 % of genes are significantly DE (padj < 0.05, |log2FC| > 1).
# Kinase genes get stronger signal (80 % sig probability).
# ---------------------------------------------------------------------------
rows = []
for idx, gene_name in enumerate(all_genes, 1):
    is_kinase = gene_name in KINASE_GENES
    is_sig    = random.random() < (0.80 if is_kinase else 0.17)

    if is_sig:
        log2fc    = random.choice([-1, 1]) * random.uniform(1.0, 4.5 if is_kinase else 3.0)
        padj      = random.uniform(0.0001, 0.045)
        base_mean = random.uniform(500, 8000) if is_kinase else random.uniform(50, 3000)
        lfcse     = round(abs(log2fc) * random.uniform(0.08, 0.25), 4)
    else:
        log2fc    = random.uniform(-0.9, 0.9)
        padj      = random.uniform(0.052, 1.0)
        base_mean = random.uniform(10, 2000)
        lfcse     = round(abs(log2fc) * random.uniform(0.15, 0.4) + 0.01, 4)

    pvalue = min(padj * random.uniform(1.5, 8.0), 1.0)
    stat   = round(log2fc / (lfcse + 1e-6), 4)

    rows.append({
        "gene_id":        f"ENSG{idx:011d}",
        "gene_name":      gene_name,
        "log2FoldChange": round(log2fc, 4),
        "padj":           round(padj, 6),
        "pvalue":         round(pvalue, 6),
        "baseMean":       round(base_mean, 2),
        "lfcSE":          lfcse,
        "stat":           stat,
    })

rows.sort(key=lambda r: r["padj"])

# Write DE results TSV
header = "gene_id\\tgene_name\\tlog2FoldChange\\tpadj\\tpvalue\\tbaseMean\\tlfcSE\\tstat"
with open("de_results.tsv", "w") as f:
    f.write(header + "\\n")
    for r in rows:
        f.write(
            f"{r['gene_id']}\\t{r['gene_name']}\\t{r['log2FoldChange']}\\t"
            f"{r['padj']}\\t{r['pvalue']}\\t{r['baseMean']}\\t"
            f"{r['lfcSE']}\\t{r['stat']}\\n"
        )

# Volcano plot data JSON
points = []
for r in rows:
    neg_log10 = -math.log10(max(r["padj"], 1e-300))
    points.append({
        "gene_id":        r["gene_id"],
        "gene_name":      r["gene_name"],
        "log2FoldChange": r["log2FoldChange"],
        "neg_log10_padj": round(neg_log10, 4),
        "significant":    r["padj"] < 0.05 and abs(r["log2FoldChange"]) > 1,
    })

volcano = {
    "drug_name":   drug_name,
    "target_gene": target_gene,
    "mock_mode":   True,
    "timestamp":   datetime.utcnow().isoformat() + "Z",
    "points":      points,
}
with open("volcano_data.json", "w") as f:
    json.dump(volcano, f, indent=2)

n_sig = sum(1 for r in rows if r["padj"] < 0.05 and abs(r["log2FoldChange"]) > 1)
print(f"DE analysis (mock): {len(rows)} genes tested, {n_sig} significantly DE")
print(f"  Drug: {drug_name}  Target: {target_gene}  n_replicates: {n_reps}")
EOF

    else
        # ---------------------------------------------------------------------------
        # Live: run pydeseq2 (Python DESeq2) on pre-supplied count-matrix TSV files.
        # Each TSV: rows = genes, columns = samples, first column = gene_id (header).
        # pydeseq2 is a faithful Python reimplementation of DESeq2 (Muzellec et al. 2022).
        # ---------------------------------------------------------------------------
        python3 << 'PYEOF'
import json, math, sys
import numpy as np
import pandas as pd
from datetime import datetime, timezone

drug_name   = "${drug_name}"
target_gene = "${target_gene}"

# ── Load count matrices ──────────────────────────────────────────────────────
treated_df = pd.read_csv("${treated_counts}", sep="\\t", index_col=0)
control_df = pd.read_csv("${control_counts}", sep="\\t", index_col=0)

counts_df  = pd.concat([treated_df, control_df], axis=1)
n_treated  = treated_df.shape[1]
n_control  = control_df.shape[1]
conditions = ["treated"] * n_treated + ["control"] * n_control

meta_df = pd.DataFrame({"condition": conditions}, index=counts_df.columns)

print(f"Loaded counts: {counts_df.shape[0]} genes x {counts_df.shape[1]} samples")
print(f"  Treated samples: {n_treated}  Control samples: {n_control}")

# ── Run pydeseq2 ─────────────────────────────────────────────────────────────
from pydeseq2.dds import DeseqDataSet
from pydeseq2.ds  import DeseqStats

counts_int = counts_df.T.astype(int)   # pydeseq2 expects samples x genes
dds = DeseqDataSet(
    counts   = counts_int,
    metadata = meta_df,
    design_factors = "condition",
    ref_level      = ["condition", "control"],
    n_cpus         = 4,
    quiet          = False,
)
dds.deseq2()

stat_res = DeseqStats(dds, contrast=["condition", "treated", "control"], quiet=False)
stat_res.summary()

res_df = stat_res.results_df.copy()
res_df.index.name = "gene_id"
res_df["gene_name"] = res_df.index
res_df = res_df.dropna(subset=["padj"]).sort_values("padj")

# ── Write DE results TSV ─────────────────────────────────────────────────────
out_cols = ["gene_name", "log2FoldChange", "padj", "pvalue", "baseMean", "lfcSE", "stat"]
out_cols = [c for c in out_cols if c in res_df.columns]
res_df.reset_index()[["gene_id"] + out_cols].to_csv("de_results.tsv", sep="\\t", index=False)

# ── Write volcano JSON ────────────────────────────────────────────────────────
points = []
for gene_id, row in res_df.iterrows():
    points.append({
        "gene_id":        gene_id,
        "gene_name":      row.get("gene_name", gene_id),
        "log2FoldChange": float(row["log2FoldChange"]) if not math.isnan(row["log2FoldChange"]) else 0.0,
        "neg_log10_padj": float(-math.log10(max(row["padj"], 1e-300))),
        "significant":    bool(row["padj"] < 0.05 and abs(row["log2FoldChange"]) > 1),
    })

volcano = {
    "drug_name":   drug_name,
    "target_gene": target_gene,
    "mock_mode":   False,
    "timestamp":   datetime.now(timezone.utc).isoformat(),
    "points":      points,
}
with open("volcano_data.json", "w") as f:
    json.dump(volcano, f, indent=2)

n_sig = sum(1 for p in points if p["significant"])
print(f"DE analysis (live/pydeseq2): {len(res_df)} genes tested, {n_sig} significantly DE")
PYEOF
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        deseq2: \$(Rscript -e "cat(as.character(packageVersion('DESeq2')))" 2>/dev/null || echo "mock")
        python: \$(python3 --version 2>&1 | cut -d' ' -f2 2>/dev/null || echo "3.10.0")
        mock_mode: "${mock}"
    END_VERSIONS
    """

    stub:
    """
    printf 'gene_id\\tgene_name\\tlog2FoldChange\\tpadj\\tpvalue\\tbaseMean\\tlfcSE\\tstat\\n' > de_results.tsv
    echo '{"drug_name":"mock","points":[]}' > volcano_data.json
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        deseq2: "1.42.0"
        python: "3.10.0"
    END_VERSIONS
    """
}

// ============================================================================
// Process 2: Gene Set Enrichment Analysis
// ============================================================================

process GENE_SET_ENRICHMENT {
    tag "${params.drug_name}_gsea"
    label 'process_medium'
    publishDir "${params.outdir}/02_gene_set_enrichment", mode: params.publish_dir_mode

    container 'biomate/biomni-drug-discovery-nf:latest'

    input:
    path de_results_tsv   // ranked gene list from DIFFERENTIAL_EXPRESSION

    output:
    path "enrichment.tsv",       emit: enrichment_tsv
    path "enrichment_plot.json", emit: enrichment_plot
    path "versions.yml",         emit: versions

    script:
    def mock        = params.mock_mode
    def drug_name   = params.drug_name
    def target_gene = params.target_gene
    def gmt_file    = params.gmt_file
    """
    if [ "${mock}" = "true" ]; then
        python3 << 'EOF'
import json
import random
from datetime import datetime

random.seed(123)

drug_name   = "${drug_name}"
target_gene = "${target_gene}"

# ---------------------------------------------------------------------------
# Biologically plausible MSigDB Hallmark pathways for a kinase inhibitor.
# Base NES values reflect expected biology (positive = up-regulated on drug).
# ---------------------------------------------------------------------------
HALLMARK_PATHWAYS = [
    ("HALLMARK_E2F_TARGETS",               "cell cycle / DNA replication",        2.31),
    ("HALLMARK_G2M_CHECKPOINT",            "G2/M cell cycle checkpoint",           2.18),
    ("HALLMARK_MYC_TARGETS_V1",            "MYC transcriptional targets",          1.95),
    ("HALLMARK_PI3K_AKT_MTOR_SIGNALING",   "PI3K/AKT/mTOR pathway",               1.72),
    ("HALLMARK_APOPTOSIS",                 "programmed cell death",               -1.88),
    ("HALLMARK_P53_PATHWAY",               "TP53 tumour-suppressor pathway",      -2.05),
    ("HALLMARK_DNA_REPAIR",                "DNA damage response",                  1.44),
    ("HALLMARK_OXIDATIVE_PHOSPHORYLATION", "mitochondrial oxidative phosphorylation", -1.31),
    ("HALLMARK_INFLAMMATORY_RESPONSE",     "innate immune / inflammatory response",-1.52),
    ("HALLMARK_UNFOLDED_PROTEIN_RESPONSE", "ER stress / unfolded protein response", 1.19),
]

# Collect significant DE gene names for leading-edge annotation
sig_genes = []
with open("${de_results_tsv}") as fh:
    next(fh)  # skip header
    for line in fh:
        parts = line.strip().split("\\t")
        if len(parts) >= 4:
            try:
                padj   = float(parts[3])
                log2fc = float(parts[2])
                if padj < 0.05 and abs(log2fc) > 1:
                    sig_genes.append(parts[1])
            except ValueError:
                pass

if not sig_genes:
    sig_genes = ["MAPK1", "AKT1", "MYC", "STAT3", "CDK2"]

rows = []
for pathway, description, base_nes in HALLMARK_PATHWAYS:
    nes       = round(base_nes + random.uniform(-0.15, 0.15), 3)
    padj      = round(random.uniform(0.001, 0.048), 4)
    pvalue    = round(padj * random.uniform(1.2, 5.0), 6)
    size      = random.randint(80, 350)
    n_leading = min(random.randint(5, 20), len(sig_genes))
    leading   = ",".join(random.sample(sig_genes, n_leading)) if n_leading > 0 else ""
    rows.append({
        "pathway":            pathway,
        "description":        description,
        "NES":                nes,
        "padj":               padj,
        "pvalue":             pvalue,
        "size":               size,
        "leading_edge_genes": leading,
    })

rows.sort(key=lambda r: abs(r["NES"]), reverse=True)

# Write enrichment TSV
header = "pathway\\tdescription\\tNES\\tpadj\\tpvalue\\tsize\\tleading_edge_genes"
with open("enrichment.tsv", "w") as f:
    f.write(header + "\\n")
    for r in rows:
        f.write(
            f"{r['pathway']}\\t{r['description']}\\t{r['NES']}\\t"
            f"{r['padj']}\\t{r['pvalue']}\\t{r['size']}\\t{r['leading_edge_genes']}\\n"
        )

# Write enrichment plot JSON
plot_data = {
    "drug_name":   drug_name,
    "target_gene": target_gene,
    "mock_mode":   True,
    "timestamp":   datetime.utcnow().isoformat() + "Z",
    "pathways":    rows,
}
with open("enrichment_plot.json", "w") as f:
    json.dump(plot_data, f, indent=2)

print(f"GSEA (mock): {len(rows)} Hallmark pathways enriched for {drug_name}")
for r in rows[:5]:
    direction = "UP" if r["NES"] > 0 else "DOWN"
    print(f"  [{direction}] {r['pathway']}  NES={r['NES']}  padj={r['padj']}")
EOF

    else
        # ---------------------------------------------------------------------------
        # Live: run gseapy prerank against MSigDB Hallmark gene sets.
        # gseapy is a Python GSEA implementation wrapping the GSEA Java algorithm.
        # Uses Wald stat from DE results as the gene ranking metric.
        # ---------------------------------------------------------------------------
        python3 << 'PYEOF'
import json, math, os
import pandas as pd
import gseapy as gp
from datetime import datetime, timezone

drug_name   = "${drug_name}"
target_gene = "${target_gene}"
gmt_file    = "${gmt_file}"

de_df = pd.read_csv("${de_results_tsv}", sep="\\t")
de_df = de_df.dropna(subset=["stat"])
de_df = de_df.sort_values("stat", ascending=False)

ranking = de_df.set_index("gene_name")["stat"].to_dict()
ranking_series = pd.Series(ranking).sort_values(ascending=False)

# Choose gene set source: use provided GMT file if it exists, otherwise use gseapy's
# built-in MSigDB Hallmark collection (fetched on demand from gseapy's cached sets).
if os.path.exists(gmt_file):
    gene_sets = gmt_file
    print(f"Using local GMT file: {gmt_file}")
else:
    gene_sets = "MSigDB_Hallmark_2020"
    print(f"GMT file not found at {gmt_file}; using gseapy built-in: {gene_sets}")

pre_res = gp.prerank(
    rnk          = ranking_series,
    gene_sets    = gene_sets,
    min_size     = 1,     # accept any overlap — filter by FDR at interpretation step
    max_size     = 500,
    permutation_num = 200,
    seed         = 42,
    verbose      = True,
    outdir       = None,
)

res_df = pre_res.res2d.copy()
res_df = res_df.rename(columns={
    "Term": "pathway", "NES": "NES", "FDR q-val": "padj",
    "NOM p-val": "pvalue", "Tag %": "tag_pct", "Lead_genes": "leading_edge_genes",
})
if "pathway" not in res_df.columns and "Term" not in res_df.columns:
    res_df = res_df.reset_index().rename(columns={"index": "pathway"})
res_df["description"] = res_df["pathway"]

for col in ["padj", "pvalue", "NES"]:
    if col in res_df.columns:
        res_df[col] = pd.to_numeric(res_df[col], errors="coerce")

res_df = res_df.sort_values("padj")

out_cols = [c for c in ["pathway","description","NES","padj","pvalue","leading_edge_genes"] if c in res_df.columns]
res_df[out_cols].to_csv("enrichment.tsv", sep="\\t", index=False)

rows = []
for _, row in res_df.head(10).iterrows():
    rows.append({
        "pathway":            str(row.get("pathway", "")),
        "description":        str(row.get("description", "")),
        "NES":                float(row["NES"]) if not math.isnan(float(row["NES"])) else 0.0,
        "padj":               float(row["padj"]) if not math.isnan(float(row["padj"])) else 1.0,
        "pvalue":             float(row.get("pvalue", 1.0)) if "pvalue" in row else 1.0,
        "leading_edge_genes": str(row.get("leading_edge_genes", "")),
    })

plot_data = {
    "drug_name":   drug_name,
    "target_gene": target_gene,
    "mock_mode":   False,
    "timestamp":   datetime.now(timezone.utc).isoformat(),
    "pathways":    rows,
}
with open("enrichment_plot.json", "w") as f:
    json.dump(plot_data, f, indent=2)

n_sig = int((res_df["padj"] < 0.05).sum()) if "padj" in res_df.columns else 0
print(f"GSEA (live/gseapy): {len(res_df)} pathways, {n_sig} significant (padj<0.05)")
for r in rows[:5]:
    direction = "UP" if r["NES"] > 0 else "DOWN"
    print(f"  [{direction}] {r['pathway']}  NES={r['NES']:.3f}  padj={r['padj']:.4f}")
PYEOF
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fgsea: \$(Rscript -e "cat(as.character(packageVersion('fgsea')))" 2>/dev/null || echo "mock")
        python: \$(python3 --version 2>&1 | cut -d' ' -f2 2>/dev/null || echo "3.10.0")
        mock_mode: "${mock}"
    END_VERSIONS
    """

    stub:
    """
    printf 'pathway\\tdescription\\tNES\\tpadj\\tpvalue\\tsize\\tleading_edge_genes\\n' > enrichment.tsv
    echo '{"pathways":[]}' > enrichment_plot.json
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fgsea: "1.28.0"
        python: "3.10.0"
    END_VERSIONS
    """
}

// ============================================================================
// Process 3: LINCS L1000 / CMap Signature Lookup
// ============================================================================

process LINCS_CMAP_LOOKUP {
    tag "${params.drug_name}_cmap"
    label 'process_single'
    publishDir "${params.outdir}/03_lincs_cmap", mode: params.publish_dir_mode

    container 'biomate/biomni-drug-discovery-nf:latest'

    input:
    path de_results_tsv   // ranked gene list from DIFFERENTIAL_EXPRESSION

    output:
    path "cmap_matches.tsv",  emit: cmap_tsv
    path "cmap_matches.json", emit: cmap_json
    path "versions.yml",      emit: versions

    script:
    def mock        = params.mock_mode
    def drug_name   = params.drug_name
    def target_gene = params.target_gene
    """
    if [ "${mock}" = "true" ]; then
        python3 << 'EOF'
import json
import random
from datetime import datetime

random.seed(77)

drug_name   = "${drug_name}"
target_gene = "${target_gene}"

# ---------------------------------------------------------------------------
# Mock CMap hits: 5 similar drug signatures with biologically coherent
# annotations for a kinase-inhibitor query (e.g. Imatinib / BCR-ABL1).
# ---------------------------------------------------------------------------
CMAP_DRUGS = [
    {
        "drug_name":      "Dasatinib",
        "target":         "BCR-ABL1 / Src",
        "moa_annotation": "ABL/Src kinase inhibitor (2nd gen TKI)",
        "cell_line":      "K562",
    },
    {
        "drug_name":      "Nilotinib",
        "target":         "BCR-ABL1",
        "moa_annotation": "Selective BCR-ABL1 inhibitor (2nd gen TKI)",
        "cell_line":      "K562",
    },
    {
        "drug_name":      "Bosutinib",
        "target":         "BCR-ABL1 / Src",
        "moa_annotation": "Dual ABL/Src kinase inhibitor",
        "cell_line":      "K562",
    },
    {
        "drug_name":      "Ponatinib",
        "target":         "BCR-ABL1 T315I",
        "moa_annotation": "Pan-BCR-ABL1 inhibitor (3rd gen TKI)",
        "cell_line":      "K562",
    },
    {
        "drug_name":      "Gleevec_analogue_1",
        "target":         "BCR-ABL1 / c-KIT",
        "moa_annotation": "Imatinib-class RTK inhibitor",
        "cell_line":      "HL60",
    },
]

similarity_scores = [0.92, 0.88, 0.81, 0.74, 0.63]
random.shuffle(similarity_scores)

matches = []
for drug, sim in zip(CMAP_DRUGS, similarity_scores):
    matches.append({
        "drug_name":           drug["drug_name"],
        "target":              drug["target"],
        "similarity_score":    round(sim, 3),
        "moa_annotation":      drug["moa_annotation"],
        "cell_line":           drug["cell_line"],
        "cmap_perturbagen_id": f"BRD-K{random.randint(10000000, 99999999):08d}",
    })

matches.sort(key=lambda m: m["similarity_score"], reverse=True)

# Write TSV
header = "drug_name\\ttarget\\tsimilarity_score\\tmoa_annotation\\tcell_line\\tcmap_perturbagen_id"
with open("cmap_matches.tsv", "w") as f:
    f.write(header + "\\n")
    for m in matches:
        f.write(
            f"{m['drug_name']}\\t{m['target']}\\t{m['similarity_score']}\\t"
            f"{m['moa_annotation']}\\t{m['cell_line']}\\t{m['cmap_perturbagen_id']}\\n"
        )

# Write JSON
payload = {
    "query_drug":  drug_name,
    "target_gene": target_gene,
    "n_matches":   len(matches),
    "mock_mode":   True,
    "timestamp":   datetime.utcnow().isoformat() + "Z",
    "matches":     matches,
}
with open("cmap_matches.json", "w") as f:
    json.dump(payload, f, indent=2)

print(f"CMap lookup (mock): {len(matches)} similar drugs found for {drug_name}")
for m in matches:
    print(f"  [{m['similarity_score']:.3f}] {m['drug_name']} — {m['moa_annotation']}")
EOF

    else
        # ---------------------------------------------------------------------------
        # Live: derive top up/down gene signature from DE results and query the
        # LINCS CMap API (clue.io).  Set env var LINCS_API_KEY before running.
        # ---------------------------------------------------------------------------
        python3 << 'PYEOF'
import json
import os
import sys
import csv
import urllib.request
from datetime import datetime

drug_name   = "${drug_name}"
target_gene = "${target_gene}"

# Build top up/down gene lists from significant DE genes
sig_up   = []
sig_down = []
with open("${de_results_tsv}") as fh:
    reader = csv.DictReader(fh, delimiter="\\t")
    for row in reader:
        try:
            padj   = float(row["padj"])
            log2fc = float(row["log2FoldChange"])
        except (ValueError, KeyError):
            continue
        if padj < 0.05 and abs(log2fc) > 1:
            if log2fc > 0:
                sig_up.append((row["gene_name"], log2fc))
            else:
                sig_down.append((row["gene_name"], log2fc))

sig_up.sort(key=lambda x: -x[1])
sig_down.sort(key=lambda x: x[1])
top_up   = [g for g, _ in sig_up[:50]]
top_down = [g for g, _ in sig_down[:50]]

api_key = os.environ.get("LINCS_API_KEY", "")
if not api_key:
    print("WARNING: LINCS_API_KEY not set — CMap query may fail", file=sys.stderr)

query_payload = json.dumps({
    "up_genes":  top_up,
    "dn_genes":  top_down,
    "n_results": 10,
}).encode()

matches = []
try:
    req = urllib.request.Request(
        "https://api.clue.io/api/query",
        data=query_payload,
        headers={"user_key": api_key, "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        cmap_data = json.loads(resp.read())
    matches_raw = cmap_data.get("result", [])
    for hit in matches_raw[:5]:
        matches.append({
            "drug_name":           hit.get("pert_iname", "unknown"),
            "target":              hit.get("target", "unknown"),
            "similarity_score":    round(float(hit.get("score", 0.0)), 3),
            "moa_annotation":      hit.get("moa", "unknown"),
            "cell_line":           hit.get("cell_id", "unknown"),
            "cmap_perturbagen_id": hit.get("pert_id", "unknown"),
        })
except Exception as exc:
    print(f"WARNING: CMap API call failed: {exc}", file=sys.stderr)

matches.sort(key=lambda m: m["similarity_score"], reverse=True)

header = "drug_name\\ttarget\\tsimilarity_score\\tmoa_annotation\\tcell_line\\tcmap_perturbagen_id"
with open("cmap_matches.tsv", "w") as f:
    f.write(header + "\\n")
    for m in matches:
        f.write(
            f"{m['drug_name']}\\t{m['target']}\\t{m['similarity_score']}\\t"
            f"{m['moa_annotation']}\\t{m['cell_line']}\\t{m['cmap_perturbagen_id']}\\n"
        )

payload = {
    "query_drug":  drug_name,
    "target_gene": target_gene,
    "n_matches":   len(matches),
    "mock_mode":   False,
    "timestamp":   datetime.utcnow().isoformat() + "Z",
    "matches":     matches,
}
with open("cmap_matches.json", "w") as f:
    json.dump(payload, f, indent=2)

print(f"CMap lookup (live): {len(matches)} similar drugs found for {drug_name}")
PYEOF
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version 2>&1 | cut -d' ' -f2)
        mock_mode: "${mock}"
    END_VERSIONS
    """

    stub:
    """
    printf 'drug_name\\ttarget\\tsimilarity_score\\tmoa_annotation\\tcell_line\\tcmap_perturbagen_id\\n' > cmap_matches.tsv
    echo '{"n_matches":0,"matches":[]}' > cmap_matches.json
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: "3.10.0"
    END_VERSIONS
    """
}

// ============================================================================
// Process 4: MoA Aggregation Report
// ============================================================================

process MOA_REPORT {
    tag "${params.drug_name}_moa_report"
    label 'process_single'
    publishDir "${params.outdir}/04_moa_report", mode: params.publish_dir_mode

    container 'biomate/biomni-drug-discovery-nf:latest'

    input:
    path de_results_tsv   // from DIFFERENTIAL_EXPRESSION
    path enrichment_tsv   // from GENE_SET_ENRICHMENT
    path cmap_json        // from LINCS_CMAP_LOOKUP

    output:
    path "moa_summary.json", emit: moa_summary
    path "moa_report.html",  emit: moa_html
    path "versions.yml",     emit: versions

    script:
    def mock        = params.mock_mode
    def drug_name   = params.drug_name
    def target_gene = params.target_gene
    """
    python3 << 'EOF'
import json
import csv
import math
from datetime import datetime

drug_name   = "${drug_name}"
target_gene = "${target_gene}"
mock_mode   = "${mock}" == "true"

# -------------------------------------------------------------------------
# 1. Parse DE results
# -------------------------------------------------------------------------
de_genes  = []
sig_genes = []
with open("${de_results_tsv}") as fh:
    reader = csv.DictReader(fh, delimiter="\\t")
    for row in reader:
        de_genes.append(row)
        try:
            if float(row["padj"]) < 0.05 and abs(float(row["log2FoldChange"])) > 1:
                sig_genes.append(row)
        except (ValueError, KeyError):
            pass

n_de_genes = len(sig_genes)

# -------------------------------------------------------------------------
# 2. Parse GSEA enrichment results
# -------------------------------------------------------------------------
pathways = []
with open("${enrichment_tsv}") as fh:
    reader = csv.DictReader(fh, delimiter="\\t")
    for row in reader:
        try:
            pathways.append({
                "pathway":            row["pathway"],
                "NES":                float(row["NES"]),
                "padj":               float(row["padj"]),
                "leading_edge_genes": row.get("leading_edge_genes", ""),
            })
        except (ValueError, KeyError):
            pass

pathways.sort(key=lambda p: abs(p["NES"]), reverse=True)
top_pathways = pathways[:5]

# -------------------------------------------------------------------------
# 3. Parse CMap results
# -------------------------------------------------------------------------
cmap_data    = json.load(open("${cmap_json}"))
cmap_matches = cmap_data.get("matches", [])
cmap_top     = (
    cmap_matches[0]
    if cmap_matches
    else {"drug_name": "N/A", "similarity_score": 0.0, "moa_annotation": "N/A"}
)

# -------------------------------------------------------------------------
# 4. QC status
# -------------------------------------------------------------------------
if n_de_genes >= 10:
    qc_status = "PASS"
elif n_de_genes >= 5:
    qc_status = "WARN"
else:
    qc_status = "FAIL"

# -------------------------------------------------------------------------
# 5. MoA hypothesis
# -------------------------------------------------------------------------
top_pw_name = top_pathways[0]["pathway"] if top_pathways else "unknown pathway"
top_nes     = top_pathways[0]["NES"]     if top_pathways else 0.0
cmap_drug   = cmap_top.get("drug_name", "N/A")
cmap_sim    = cmap_top.get("similarity_score", 0.0)
direction   = "activation" if top_nes > 0 else "suppression"

moa_hypothesis = (
    f"Treatment with {drug_name} induces {direction} of the {top_pw_name} pathway "
    f"(NES={top_nes:.2f}), consistent with {cmap_drug} "
    f"(CMap similarity={cmap_sim:.2f}), supporting {target_gene} engagement."
)

# -------------------------------------------------------------------------
# 6. Write moa_summary.json
# -------------------------------------------------------------------------
summary = {
    "drug_name":    drug_name,
    "target_gene":  target_gene,
    "n_de_genes":   n_de_genes,
    "qc_status":    qc_status,
    "top_pathways": [
        {"name": p["pathway"], "NES": p["NES"], "padj": p["padj"]}
        for p in top_pathways
    ],
    "cmap_top_match": {
        "drug_name":      cmap_top.get("drug_name", "N/A"),
        "similarity":     cmap_top.get("similarity_score", 0.0),
        "moa_annotation": cmap_top.get("moa_annotation", "N/A"),
    },
    "moa_hypothesis": moa_hypothesis,
    "mock_mode":    mock_mode,
    "timestamp":    datetime.utcnow().isoformat() + "Z",
}
with open("moa_summary.json", "w") as f:
    json.dump(summary, f, indent=2)

# -------------------------------------------------------------------------
# 7. Build HTML report
# -------------------------------------------------------------------------
qc_color = {"PASS": "#28a745", "WARN": "#ffc107", "FAIL": "#dc3545"}.get(qc_status, "#6c757d")

# Top-20 DE gene rows
top_de = sorted(de_genes, key=lambda r: float(r.get("padj", 1)))[:20]
de_rows_html = ""
for r in top_de:
    try:
        padj   = float(r.get("padj", 1))
        log2fc = float(r.get("log2FoldChange", 0))
        sig    = " &#9733;" if padj < 0.05 and abs(log2fc) > 1 else ""
        fc_col = "#c0392b" if log2fc > 0 else "#2980b9"
        de_rows_html += (
            f"<tr><td>{r['gene_name']}</td>"
            f"<td style='color:{fc_col};text-align:right'>{log2fc:.3f}</td>"
            f"<td style='text-align:right'>{padj:.2e}</td>"
            f"<td style='text-align:right'>{r.get('baseMean', 'N/A')}</td>"
            f"<td>{sig}</td></tr>\\n"
        )
    except (ValueError, KeyError):
        pass

# Top-10 pathway rows
pw_rows_html = ""
for p in pathways[:10]:
    nes_col = "#c0392b" if p["NES"] > 0 else "#2980b9"
    edge    = p["leading_edge_genes"][:60] + "..." if len(p["leading_edge_genes"]) > 60 else p["leading_edge_genes"]
    pw_rows_html += (
        f"<tr><td>{p['pathway']}</td>"
        f"<td style='color:{nes_col};text-align:right'>{p['NES']:.3f}</td>"
        f"<td style='text-align:right'>{p['padj']:.4f}</td>"
        f"<td style='font-size:0.82em'>{edge}</td></tr>\\n"
    )

# CMap match rows
cmap_rows_html = ""
for m in cmap_matches:
    sim     = m.get("similarity_score", 0)
    sim_col = "#28a745" if sim >= 0.8 else ("#ffc107" if sim >= 0.6 else "#dc3545")
    cmap_rows_html += (
        f"<tr><td><b>{m['drug_name']}</b></td>"
        f"<td>{m.get('target', 'N/A')}</td>"
        f"<td style='color:{sim_col};text-align:right'>{sim:.3f}</td>"
        f"<td>{m.get('moa_annotation', 'N/A')}</td>"
        f"<td>{m.get('cell_line', 'N/A')}</td></tr>\\n"
    )

gen_ts = datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")

html = f'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Drug MoA Report &mdash; {drug_name}</title>
<style>
  body {{font-family: Arial, sans-serif; max-width: 1100px; margin: 0 auto; padding: 20px; color: #333;}}
  h1   {{color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 8px;}}
  h2   {{color: #34495e; margin-top: 32px;}}
  .info-grid {{display: grid; grid-template-columns: 1fr 1fr; gap: 8px;
               background: #f8f9fa; padding: 14px 18px; border-radius: 6px; margin-bottom: 18px;}}
  .info-item {{padding: 3px 0;}}
  .info-label {{font-weight: bold; color: #555;}}
  .qc-box {{padding: 14px 20px; border-radius: 8px; color: white; font-size: 1.15em;
             font-weight: bold; margin: 18px 0; background: {qc_color};}}
  .hypothesis-box {{background: #eaf3fb; border-left: 5px solid #3498db;
                    padding: 14px 20px; border-radius: 0 6px 6px 0; margin: 18px 0;
                    font-style: italic; line-height: 1.6;}}
  table {{border-collapse: collapse; width: 100%; margin: 14px 0; font-size: 0.93em;}}
  th    {{background: #2c3e50; color: white; padding: 8px 12px; text-align: left;}}
  td    {{padding: 6px 12px; border-bottom: 1px solid #dde;}}
  tr:nth-child(even) {{background: #f9f9fb;}}
  tr:hover {{background: #ebf5fb;}}
  .footer {{color: #aaa; font-size: 0.83em; margin-top: 40px;
             border-top: 1px solid #eee; padding-top: 10px;}}
</style>
</head>
<body>
<h1>&#127995; Drug Mechanism-of-Action Report</h1>

<div class="info-grid">
  <div class="info-item"><span class="info-label">Drug:</span> {drug_name}</div>
  <div class="info-item"><span class="info-label">Target Gene:</span> {target_gene}</div>
  <div class="info-item"><span class="info-label">Significant DE genes:</span> {n_de_genes}</div>
  <div class="info-item"><span class="info-label">Enriched pathways:</span> {len(pathways)}</div>
  <div class="info-item"><span class="info-label">Generated:</span> {gen_ts}</div>
  <div class="info-item"><span class="info-label">Top CMap match:</span> {cmap_drug} (sim={cmap_sim:.2f})</div>
</div>

<div class="qc-box">QC Status: {qc_status} &mdash; {n_de_genes} significant DE genes detected</div>

<h2>&#128161; MoA Hypothesis</h2>
<div class="hypothesis-box">{moa_hypothesis}</div>

<h2>&#128202; Top 20 Differentially Expressed Genes</h2>
<table>
  <tr><th>Gene</th><th>log2FC</th><th>padj</th><th>baseMean</th><th>Sig</th></tr>
  {de_rows_html}
</table>

<h2>&#127774; Top 10 Enriched Pathways (MSigDB Hallmark)</h2>
<table>
  <tr><th>Pathway</th><th>NES</th><th>padj</th><th>Leading Edge (truncated)</th></tr>
  {pw_rows_html}
</table>

<h2>&#128279; LINCS CMap Drug Similarity Matches</h2>
<table>
  <tr><th>Drug</th><th>Target</th><th>Similarity</th><th>MoA Annotation</th><th>Cell Line</th></tr>
  {cmap_rows_html}
</table>

<div class="footer">
  BioMate Drug MoA Pipeline &mdash; Gap 9 Drug Discovery Analysis &mdash;
  Generated {datetime.utcnow().isoformat()}Z
</div>
</body>
</html>'''

with open("moa_report.html", "w") as f:
    f.write(html)

print(f"MoA Report complete for {drug_name} / {target_gene}")
print(f"  QC status:   {qc_status}  ({n_de_genes} significant DE genes)")
print(f"  Top pathway: {top_pw_name}  NES={top_nes:.2f}")
print(f"  CMap top:    {cmap_drug}  similarity={cmap_sim:.2f}")
print(f"  Hypothesis:  {moa_hypothesis}")
EOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version 2>&1 | cut -d' ' -f2)
        mock_mode: "${mock}"
    END_VERSIONS
    """

    stub:
    """
    echo '{"qc_status":"PASS","n_de_genes":42,"moa_hypothesis":"stub"}' > moa_summary.json
    echo '<html><body>MoA Report stub</body></html>' > moa_report.html
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: "3.10.0"
    END_VERSIONS
    """
}

// ============================================================================
// Entry workflow: DRUG_MOA_RNASEQ
// ============================================================================
//
// Data flow:
//
//   ch_treated_counts ──► DIFFERENTIAL_EXPRESSION ──► de_results.tsv
//   ch_control_counts ──►         │                ──► volcano_data.json
//                                 ├──────────────────► GENE_SET_ENRICHMENT
//                                 │                        │
//                                 └──────────────────► LINCS_CMAP_LOOKUP
//                                                          │
//                                     ┌───────────────────┘
//                                     │
//                              MOA_REPORT (HTML + JSON summary)
//
// ============================================================================

workflow DRUG_MOA_RNASEQ {
    take:
    ch_treated_counts  // channel: path(count_matrix.tsv) — treated samples
    ch_control_counts  // channel: path(count_matrix.tsv) — control samples

    main:
    // ------------------------------------------------------------------
    // Step 1: Differential expression analysis
    // ------------------------------------------------------------------
    DIFFERENTIAL_EXPRESSION(ch_treated_counts, ch_control_counts)

    // ------------------------------------------------------------------
    // Step 2a: Gene set enrichment analysis (uses DE gene ranking)
    // ------------------------------------------------------------------
    GENE_SET_ENRICHMENT(DIFFERENTIAL_EXPRESSION.out.de_results)

    // ------------------------------------------------------------------
    // Step 2b: LINCS CMap signature lookup (uses DE gene signature)
    // ------------------------------------------------------------------
    LINCS_CMAP_LOOKUP(DIFFERENTIAL_EXPRESSION.out.de_results)

    // ------------------------------------------------------------------
    // Step 3: Aggregate into MoA report
    // ------------------------------------------------------------------
    MOA_REPORT(
        DIFFERENTIAL_EXPRESSION.out.de_results,
        GENE_SET_ENRICHMENT.out.enrichment_tsv,
        LINCS_CMAP_LOOKUP.out.cmap_json
    )

    emit:
    de_results_tsv   = DIFFERENTIAL_EXPRESSION.out.de_results
    enrichment_tsv   = GENE_SET_ENRICHMENT.out.enrichment_tsv
    cmap_matches_tsv = LINCS_CMAP_LOOKUP.out.cmap_tsv
    moa_report_html  = MOA_REPORT.out.moa_html
    moa_summary_json = MOA_REPORT.out.moa_summary
    versions         = DIFFERENTIAL_EXPRESSION.out.versions
                           .mix(GENE_SET_ENRICHMENT.out.versions)
                           .mix(LINCS_CMAP_LOOKUP.out.versions)
                           .mix(MOA_REPORT.out.versions)
}

// ============================================================================
// Standalone Entry Point (nextflow run main.nf)
// ============================================================================

workflow {
    log_workflow_header()

    // ------------------------------------------------------------------
    // In mock mode, create minimal placeholder count matrices.
    // The DIFFERENTIAL_EXPRESSION process ignores them and generates
    // synthetic data; they exist only to satisfy Nextflow's input contract.
    // ------------------------------------------------------------------
    if (params.mock_mode) {
        ch_treated_counts = Channel.of(
            "gene_id\tTreated_S1\tTreated_S2\tTreated_S3\n"
        ).map { content ->
            def f = file("${workDir}/mock_treated_counts.tsv")
            f.text = content
            f
        }
        ch_control_counts = Channel.of(
            "gene_id\tControl_C1\tControl_C2\tControl_C3\n"
        ).map { content ->
            def f = file("${workDir}/mock_control_counts.tsv")
            f.text = content
            f
        }
    } else {
        if (!params.treated_counts) {
            error "params.treated_counts is required in live mode. Pass --treated_counts <path>"
        }
        if (!params.control_counts) {
            error "params.control_counts is required in live mode. Pass --control_counts <path>"
        }
        ch_treated_counts = Channel.fromPath(params.treated_counts, checkIfExists: true)
        ch_control_counts = Channel.fromPath(params.control_counts, checkIfExists: true)
    }

    // Run the pipeline
    DRUG_MOA_RNASEQ(ch_treated_counts, ch_control_counts)

    // Display key output paths
    DRUG_MOA_RNASEQ.out.moa_summary_json.view { f  -> "MoA summary JSON:   ${f}" }
    DRUG_MOA_RNASEQ.out.moa_report_html.view  { f  -> "MoA report HTML:    ${f}" }
    DRUG_MOA_RNASEQ.out.de_results_tsv.view   { f  -> "DE results TSV:     ${f}" }
    DRUG_MOA_RNASEQ.out.enrichment_tsv.view   { f  -> "Enrichment TSV:     ${f}" }
    DRUG_MOA_RNASEQ.out.cmap_matches_tsv.view { f  -> "CMap matches TSV:   ${f}" }
}
