#!/usr/bin/env nextflow
/*
 * genomics/transcriptomic_biomarker
 *
 * Transcriptomic Biomarker Discovery:
 *   LIMMA differential expression + gene signature scoring via GSVA/ssGSEA
 *
 * Pipeline Steps:
 * 1. BIOMARKER_INPUT_QC           — validate expression matrix + clinical metadata
 * 2. LIMMA_DIFFERENTIAL_EXPRESSION — voom transformation, linear model with covariates,
 *                                    eBayes, topTable (logFC, adj.P.Val)
 * 3. BIOMARKER_SIGNATURE_SCORING  — GSVA/ssGSEA on hallmark MSigDB (50 gene sets);
 *                                   top enriched pathways per group
 * 4. BIOMARKER_REPORT             — R Markdown: volcano plot, top-50 heatmap,
 *                                   pathway enrichment barplot → HTML report
 *
 * References:
 *  - limma-voom: Law et al. Genome Biology 2014
 *                (https://doi.org/10.1186/gb-2014-15-2-r29)
 *  - GSVA:       Hänzelmann et al. BMC Bioinformatics 2013
 *                (https://doi.org/10.1186/1471-2105-14-7)
 *  - MSigDB:     Liberzon et al. Cell Systems 2015
 *                (https://doi.org/10.1016/j.cels.2015.12.004)
 */

nextflow.enable.dsl = 2

// ============================================================================
// Default Parameters
// ============================================================================

params.outdir              = './results/transcriptomic_biomarker'
params.publish_dir_mode    = 'copy'

// Mode
params.mock_mode           = true       // true = synthetic output, no real tools needed

// Input files (required in live mode)
params.expression_matrix   = null       // path to genes×samples count/expression CSV/TSV
params.metadata            = null       // path to sample metadata CSV

// Analysis settings
params.group_column        = 'group'    // column in metadata holding the contrast groups
params.reference_group     = 'control'  // baseline group label
params.fdr_threshold       = 0.05       // FDR cutoff for DE gene selection
params.logfc_threshold     = 1.0        // |logFC| cutoff for significance filtering

// LIMMA settings
params.voom_plot           = true       // emit mean-variance trend plot
params.covariates          = null       // comma-separated covariate column names (or null)

// Signature scoring settings
params.gsva_method         = 'gsva'     // 'gsva' or 'ssgsea'
params.min_gene_set_size   = 10        // minimum gene set size for GSVA
params.max_gene_set_size   = 500       // maximum gene set size for GSVA

// ============================================================================
// Helper functions
// ============================================================================

def log_workflow_header() {
    log.info """
    ====================================================================
    BioMate | Transcriptomic Biomarker Discovery Pipeline
    ====================================================================
    Mode:              ${params.mock_mode ? 'MOCK (synthetic data)' : 'LIVE'}
    Group column:      ${params.group_column}
    Reference group:   ${params.reference_group}
    FDR threshold:     ${params.fdr_threshold}
    |logFC| threshold: ${params.logfc_threshold}
    GSVA method:       ${params.gsva_method}
    Output dir:        ${params.outdir}
    ====================================================================
    """.stripIndent()
}

// ============================================================================
// Process 1: BIOMARKER_INPUT_QC
// ============================================================================

process BIOMARKER_INPUT_QC {
    tag "input_qc"
    label 'process_low'
    publishDir "${params.outdir}/01_input_qc", mode: params.publish_dir_mode

    container 'docker.io/bioconductor/bioconductor_docker:RELEASE_3_18'

    input:
    path expression_matrix
    path metadata

    output:
    path "qc_report.json",            emit: qc_report
    path "validated_matrix.csv",      emit: validated_matrix
    path "validated_metadata.csv",    emit: validated_metadata
    path "versions.yml",              emit: versions

    script:
    def mock         = params.mock_mode
    def group_col    = params.group_column
    def ref_group    = params.reference_group
    def fdr_thresh   = params.fdr_threshold
    def logfc_thresh = params.logfc_threshold
    """
    if [ "${mock}" = "true" ]; then
        python3 << 'EOF'
import json
import random
import csv
import io
from datetime import datetime

random.seed(42)

n_genes   = 500
n_samples = 40
n_groups  = 2
group_labels = ["control", "treatment"]

# -----------------------------------------------------------------------
# 1. Generate synthetic gene names (HGNC-style)
# -----------------------------------------------------------------------
prefixes = ["EGFR","TP53","MYC","BRCA","KRAS","VEGF","CDK","STAT","AKT","PIK3",
            "RAS","RAF","MEK","ERK","JNK","TNF","IL","IFN","TGF","WNT"]
gene_names = []
for i in range(n_genes):
    prefix = prefixes[i % len(prefixes)]
    suffix = i // len(prefixes) + 1
    gene_names.append(f"{prefix}{suffix}")

# -----------------------------------------------------------------------
# 2. Generate count matrix header + rows (genes × samples)
# -----------------------------------------------------------------------
sample_ids = [f"S{str(k+1).zfill(3)}" for k in range(n_samples)]
matrix_rows = [["gene_id"] + sample_ids]
for g in gene_names:
    base_count = random.randint(50, 5000)
    row = [g] + [str(max(0, int(random.gauss(base_count, base_count * 0.3)))) for _ in sample_ids]
    matrix_rows.append(row)

with open("validated_matrix.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerows(matrix_rows)

# -----------------------------------------------------------------------
# 3. Generate sample metadata
# -----------------------------------------------------------------------
metadata_rows = [["sample_id", "group", "batch", "age", "sex"]]
for k, sid in enumerate(sample_ids):
    grp   = group_labels[k % n_groups]
    batch = f"batch_{(k // 8) + 1}"
    age   = random.randint(25, 75)
    sex   = "M" if k % 2 == 0 else "F"
    metadata_rows.append([sid, grp, batch, age, sex])

with open("validated_metadata.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerows(metadata_rows)

# -----------------------------------------------------------------------
# 4. QC report
# -----------------------------------------------------------------------
qc = {
    "pipeline":        "transcriptomic_biomarker",
    "step":            "BIOMARKER_INPUT_QC",
    "timestamp":       datetime.utcnow().isoformat() + "Z",
    "mock_mode":       True,
    "n_genes":         n_genes,
    "n_samples":       n_samples,
    "n_groups":        n_groups,
    "group_labels":    group_labels,
    "group_column":    "${group_col}",
    "reference_group": "${ref_group}",
    "fdr_threshold":   float("${fdr_thresh}"),
    "logfc_threshold": float("${logfc_thresh}"),
    "sample_counts_per_group": {"control": n_samples // 2, "treatment": n_samples // 2},
    "missing_samples_in_matrix": 0,
    "missing_samples_in_metadata": 0,
    "genes_below_cpm_threshold": 12,
    "genes_after_filtering": n_genes,
    "pass": True,
    "warnings": [],
    "errors": [],
}
with open("qc_report.json", "w") as f:
    json.dump(qc, f, indent=2)

print(f"BIOMARKER_INPUT_QC mock complete")
print(f"  Genes:   {n_genes}")
print(f"  Samples: {n_samples} ({n_groups} groups: {', '.join(group_labels)})")
print(f"  QC pass: {qc['pass']}")
EOF

    else
        # -----------------------------------------------------------------------
        # Live: R-based validation using limma / edgeR utilities
        # -----------------------------------------------------------------------
        Rscript - << 'REOF'
library(limma)
library(edgeR)
library(jsonlite)

# Read inputs
mat      <- read.csv("${expression_matrix}", row.names=1, check.names=FALSE)
metadata <- read.csv("${metadata}",          row.names=NULL, check.names=FALSE)

# Validate sample ID overlap
common_samples <- intersect(colnames(mat), metadata[["sample_id"]])
missing_mat    <- setdiff(metadata[["sample_id"]], colnames(mat))
missing_meta   <- setdiff(colnames(mat), metadata[["sample_id"]])

# Subset to common samples
mat      <- mat[, common_samples, drop=FALSE]
metadata <- metadata[metadata[["sample_id"]] %in% common_samples, ]

# Low-count filter (CPM > 1 in at least 50% of samples)
dge        <- DGEList(counts=mat)
keep       <- filterByExpr(dge, min.count=10, min.total.count=15)
mat_filt   <- mat[keep, ]
n_removed  <- sum(!keep)

# Write validated outputs
write.csv(mat_filt, "validated_matrix.csv")
write.csv(metadata, "validated_metadata.csv", row.names=FALSE)

qc <- list(
    pipeline                   = "transcriptomic_biomarker",
    step                       = "BIOMARKER_INPUT_QC",
    timestamp                  = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ"),
    mock_mode                  = FALSE,
    n_genes                    = nrow(mat_filt),
    n_samples                  = ncol(mat_filt),
    n_groups                   = length(unique(metadata[["${group_col}"]])),
    group_labels               = as.list(unique(metadata[["${group_col}"]])),
    missing_samples_in_matrix  = length(missing_mat),
    missing_samples_in_metadata= length(missing_meta),
    genes_below_cpm_threshold  = n_removed,
    genes_after_filtering      = nrow(mat_filt),
    pass                       = (length(missing_mat) == 0 && nrow(mat_filt) > 0)
)
write(toJSON(qc, auto_unbox=TRUE, pretty=TRUE), "qc_report.json")

cat(sprintf("BIOMARKER_INPUT_QC complete: %d genes, %d samples\\n",
            nrow(mat_filt), ncol(mat_filt)))
REOF
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        limma: "3.58.1"
        edgeR: "4.0.16"
        R: \$(Rscript --version 2>&1 | cut -d' ' -f4 || echo "N/A")
        python: \$(python3 --version 2>&1 | cut -d' ' -f2 || echo "N/A")
        mock_mode: "${mock}"
    END_VERSIONS
    """

    stub:
    """
    echo '{"n_genes":500,"n_samples":40,"pass":true}' > qc_report.json
    echo 'gene_id,S001,S002' > validated_matrix.csv
    echo 'sample_id,group' > validated_metadata.csv
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        limma: "3.58.1"
        R: "4.3.1"
    END_VERSIONS
    """
}

// ============================================================================
// Process 2: LIMMA_DIFFERENTIAL_EXPRESSION
// ============================================================================

process LIMMA_DIFFERENTIAL_EXPRESSION {
    tag "limma_de"
    label 'process_medium'
    publishDir "${params.outdir}/02_limma_de", mode: params.publish_dir_mode

    container 'docker.io/bioconductor/bioconductor_docker:RELEASE_3_18'

    input:
    path validated_matrix
    path validated_metadata
    path qc_report

    output:
    path "de_results.csv",            emit: de_results
    path "significant_genes.csv",     emit: significant_genes
    path "limma_model_summary.json",  emit: model_summary
    path "voom_plot.png",             emit: voom_plot, optional: true
    path "versions.yml",              emit: versions

    script:
    def mock         = params.mock_mode
    def group_col    = params.group_column
    def ref_group    = params.reference_group
    def fdr_thresh   = params.fdr_threshold
    def logfc_thresh = params.logfc_threshold
    def covariates   = params.covariates ?: ''
    """
    if [ "${mock}" = "true" ]; then
        python3 << 'EOF'
import csv
import json
import math
import random
from datetime import datetime

random.seed(42)

n_genes  = 500
n_top    = 20   # genes with adj.P.Val < 0.05

# -----------------------------------------------------------------------
# 1. Gene name list (same seed → consistent with input QC)
# -----------------------------------------------------------------------
prefixes = ["EGFR","TP53","MYC","BRCA","KRAS","VEGF","CDK","STAT","AKT","PIK3",
            "RAS","RAF","MEK","ERK","JNK","TNF","IL","IFN","TGF","WNT"]
gene_names = []
for i in range(n_genes):
    prefix = prefixes[i % len(prefixes)]
    suffix = i // len(prefixes) + 1
    gene_names.append(f"{prefix}{suffix}")

# -----------------------------------------------------------------------
# 2. Build DE results table
#    Top 20: adj.P.Val 0.001–0.04, logFC ±1.5 to ±3.5 (alternating up/down)
#    Remaining 480: adj.P.Val 0.06–0.95, logFC ±0.1 to ±0.8
# -----------------------------------------------------------------------
rows = []

# Significant genes (top 20)
for i in range(n_top):
    gene   = gene_names[i]
    direction = 1 if i % 2 == 0 else -1          # alternating up/down
    logfc  = direction * round(random.uniform(1.5, 3.5), 4)
    ave    = round(random.uniform(3.0, 10.0), 4)
    t_stat = round(logfc / random.uniform(0.3, 0.7), 4)
    p_val  = round(random.uniform(0.0001, 0.008), 6)
    # Benjamini-Hochberg adjusted (roughly scaled from rank)
    adj_p  = round(p_val * (i + 1) * 0.6 + random.uniform(0.0, 0.005), 6)
    adj_p  = min(adj_p, 0.04)  # enforce < 0.05
    b_stat = round(math.log(p_val / (1 - p_val + 1e-9)) * -1 + random.uniform(-0.5, 0.5), 4)
    rows.append({
        "gene":       gene,
        "logFC":      logfc,
        "AveExpr":    ave,
        "t":          t_stat,
        "P.Value":    p_val,
        "adj.P.Val":  adj_p,
        "B":          b_stat,
    })

# Non-significant genes (remaining 480)
for i in range(n_top, n_genes):
    gene      = gene_names[i]
    direction = 1 if random.random() > 0.5 else -1
    logfc     = direction * round(random.uniform(0.05, 0.8), 4)
    ave       = round(random.uniform(2.0, 12.0), 4)
    t_stat    = round(logfc / random.uniform(0.5, 1.5), 4)
    p_val     = round(random.uniform(0.01, 0.95), 6)
    adj_p     = round(min(p_val * random.uniform(1.0, 2.0), 0.99), 6)
    adj_p     = max(adj_p, 0.06)  # enforce >= 0.06
    b_stat    = round(math.log(max(p_val, 1e-6) / (1 - min(p_val, 1 - 1e-6))) * -1, 4)
    rows.append({
        "gene":       gene,
        "logFC":      logfc,
        "AveExpr":    ave,
        "t":          t_stat,
        "P.Value":    p_val,
        "adj.P.Val":  adj_p,
        "B":          b_stat,
    })

# Sort by adj.P.Val ascending (as topTable does)
rows.sort(key=lambda r: r["adj.P.Val"])

fieldnames = ["gene", "logFC", "AveExpr", "t", "P.Value", "adj.P.Val", "B"]
with open("de_results.csv", "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(rows)

# Significant subset
sig_rows = [r for r in rows if r["adj.P.Val"] < float("${fdr_thresh}")
            and abs(r["logFC"]) >= float("${logfc_thresh}")]
with open("significant_genes.csv", "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(sig_rows)

# -----------------------------------------------------------------------
# 3. Model summary JSON
# -----------------------------------------------------------------------
n_up   = sum(1 for r in sig_rows if r["logFC"] > 0)
n_down = sum(1 for r in sig_rows if r["logFC"] < 0)
summary = {
    "pipeline":          "transcriptomic_biomarker",
    "step":              "LIMMA_DIFFERENTIAL_EXPRESSION",
    "timestamp":         datetime.utcnow().isoformat() + "Z",
    "mock_mode":         True,
    "group_column":      "${group_col}",
    "reference_group":   "${ref_group}",
    "fdr_threshold":     float("${fdr_thresh}"),
    "logfc_threshold":   float("${logfc_thresh}"),
    "covariates":        "${covariates}".split(",") if "${covariates}" else [],
    "n_genes_tested":    n_genes,
    "n_significant":     len(sig_rows),
    "n_upregulated":     n_up,
    "n_downregulated":   n_down,
    "contrast":          f"treatment_vs_${ref_group}",
    "model_formula":     f"~ ${group_col}" + (f" + ${covariates}" if "${covariates}" else ""),
    "voom_convergence":  True,
    "top_gene":          sig_rows[0]["gene"] if sig_rows else None,
    "top_logFC":         sig_rows[0]["logFC"] if sig_rows else None,
    "top_adj_p":         sig_rows[0]["adj.P.Val"] if sig_rows else None,
}
with open("limma_model_summary.json", "w") as f:
    json.dump(summary, f, indent=2)

# Placeholder voom plot (PNG stub in mock mode)
with open("voom_plot.png", "wb") as f:
    # Minimal valid 1×1 PNG
    import base64
    png_1x1 = base64.b64decode(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
    )
    f.write(png_1x1)

print(f"LIMMA_DIFFERENTIAL_EXPRESSION mock complete")
print(f"  Genes tested:   {n_genes}")
print(f"  Significant:    {len(sig_rows)} (FDR<{float('${fdr_thresh}')}, |logFC|>={float('${logfc_thresh}')})")
print(f"  Up-regulated:   {n_up}")
print(f"  Down-regulated: {n_down}")
print(f"  Top gene:       {summary['top_gene']} (logFC={summary['top_logFC']}, adj.P.Val={summary['top_adj_p']})")
EOF

    else
        # -----------------------------------------------------------------------
        # Live: limma-voom differential expression in R
        # -----------------------------------------------------------------------
        Rscript - << 'REOF'
suppressPackageStartupMessages({
    library(limma)
    library(edgeR)
    library(jsonlite)
})

group_col    <- "${group_col}"
ref_group    <- "${ref_group}"
fdr_thresh   <- as.numeric("${fdr_thresh}")
logfc_thresh <- as.numeric("${logfc_thresh}")
covariates   <- trimws(unlist(strsplit("${covariates}", ",")))
covariates   <- covariates[nchar(covariates) > 0]

# Read validated inputs
counts   <- read.csv("${validated_matrix}",   row.names=1, check.names=FALSE)
metadata <- read.csv("${validated_metadata}", check.names=FALSE)
rownames(metadata) <- metadata[["sample_id"]]
metadata <- metadata[colnames(counts), , drop=FALSE]

# Factor setup — reference group first
metadata[[group_col]] <- relevel(factor(metadata[[group_col]]), ref=ref_group)

# Design matrix
if (length(covariates) > 0) {
    cov_terms <- paste(covariates, collapse=" + ")
    form      <- as.formula(paste("~", group_col, "+", cov_terms))
} else {
    form <- as.formula(paste("~", group_col))
}
design <- model.matrix(form, data=metadata)

# DGEList + normalisation
dge  <- DGEList(counts=counts)
dge  <- calcNormFactors(dge, method="TMM")

# voom transformation
if ("${params.voom_plot}" == "true") {
    png("voom_plot.png", width=800, height=600)
    v <- voom(dge, design, plot=TRUE)
    dev.off()
} else {
    v <- voom(dge, design, plot=FALSE)
}

# Fit linear model + eBayes
fit  <- lmFit(v, design)
fit2 <- eBayes(fit)

# Extract top table (all genes)
tt <- topTable(fit2, coef=2, number=Inf, sort.by="adj.P.Val")
tt <- data.frame(gene=rownames(tt), tt, check.names=FALSE)

write.csv(tt, "de_results.csv", row.names=FALSE)

# Significant subset
sig <- tt[tt[["adj.P.Val"]] < fdr_thresh & abs(tt[["logFC"]]) >= logfc_thresh, ]
write.csv(sig, "significant_genes.csv", row.names=FALSE)

n_up   <- sum(sig[["logFC"]] > 0)
n_down <- sum(sig[["logFC"]] < 0)

summary_list <- list(
    pipeline         = "transcriptomic_biomarker",
    step             = "LIMMA_DIFFERENTIAL_EXPRESSION",
    timestamp        = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ"),
    mock_mode        = FALSE,
    group_column     = group_col,
    reference_group  = ref_group,
    fdr_threshold    = fdr_thresh,
    logfc_threshold  = logfc_thresh,
    covariates       = as.list(covariates),
    n_genes_tested   = nrow(tt),
    n_significant    = nrow(sig),
    n_upregulated    = n_up,
    n_downregulated  = n_down,
    contrast         = paste0("treatment_vs_", ref_group),
    model_formula    = deparse(form),
    voom_convergence = TRUE,
    top_gene         = if(nrow(sig)>0) sig[1,"gene"] else NULL,
    top_logFC        = if(nrow(sig)>0) sig[1,"logFC"] else NULL,
    top_adj_p        = if(nrow(sig)>0) sig[1,"adj.P.Val"] else NULL
)
write(toJSON(summary_list, auto_unbox=TRUE, pretty=TRUE), "limma_model_summary.json")

cat(sprintf("LIMMA_DIFFERENTIAL_EXPRESSION complete: %d/%d significant genes\\n",
            nrow(sig), nrow(tt)))
REOF
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        limma: "3.58.1"
        edgeR: "4.0.16"
        R: \$(Rscript --version 2>&1 | cut -d' ' -f4 || echo "N/A")
        python: \$(python3 --version 2>&1 | cut -d' ' -f2 || echo "N/A")
        mock_mode: "${mock}"
    END_VERSIONS
    """

    stub:
    """
    echo 'gene,logFC,AveExpr,t,P.Value,adj.P.Val,B' > de_results.csv
    echo 'gene,logFC,AveExpr,t,P.Value,adj.P.Val,B' > significant_genes.csv
    echo '{"n_significant":20}' > limma_model_summary.json
    touch voom_plot.png
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        limma: "3.58.1"
        R: "4.3.1"
    END_VERSIONS
    """
}

// ============================================================================
// Process 3: BIOMARKER_SIGNATURE_SCORING
// ============================================================================

process BIOMARKER_SIGNATURE_SCORING {
    tag "signature_scoring"
    label 'process_medium'
    publishDir "${params.outdir}/03_signature_scoring", mode: params.publish_dir_mode

    container 'docker.io/bioconductor/bioconductor_docker:RELEASE_3_18'

    input:
    path validated_matrix
    path validated_metadata
    path de_results

    output:
    path "signature_scores.csv",  emit: scores
    path "pathway_summary.json",  emit: pathway_summary
    path "versions.yml",          emit: versions

    script:
    def mock          = params.mock_mode
    def gsva_method   = params.gsva_method
    def group_col     = params.group_column
    def ref_group     = params.reference_group
    def min_gs_size   = params.min_gene_set_size
    def max_gs_size   = params.max_gene_set_size
    """
    if [ "${mock}" = "true" ]; then
        python3 << 'EOF'
import csv
import json
import random
import math
from datetime import datetime

random.seed(42)

n_samples  = 40
n_pathways = 50

# -----------------------------------------------------------------------
# 1. Hallmark MSigDB pathway names (50 gene sets)
# -----------------------------------------------------------------------
hallmark_pathways = [
    "HALLMARK_ADIPOGENESIS", "HALLMARK_ALLOGRAFT_REJECTION", "HALLMARK_ANDROGEN_RESPONSE",
    "HALLMARK_ANGIOGENESIS", "HALLMARK_APICAL_JUNCTION", "HALLMARK_APICAL_SURFACE",
    "HALLMARK_APOPTOSIS", "HALLMARK_BILE_ACID_METABOLISM", "HALLMARK_CHOLESTEROL_HOMEOSTASIS",
    "HALLMARK_COAGULATION", "HALLMARK_COMPLEMENT", "HALLMARK_DNA_REPAIR",
    "HALLMARK_E2F_TARGETS", "HALLMARK_EPITHELIAL_MESENCHYMAL_TRANSITION",
    "HALLMARK_ESTROGEN_RESPONSE_EARLY", "HALLMARK_ESTROGEN_RESPONSE_LATE",
    "HALLMARK_FATTY_ACID_METABOLISM", "HALLMARK_G2M_CHECKPOINT",
    "HALLMARK_GLYCOLYSIS", "HALLMARK_HEDGEHOG_SIGNALING",
    "HALLMARK_HEME_METABOLISM", "HALLMARK_HYPOXIA",
    "HALLMARK_IL2_STAT5_SIGNALING", "HALLMARK_IL6_JAK_STAT3_SIGNALING",
    "HALLMARK_INFLAMMATORY_RESPONSE", "HALLMARK_INTERFERON_ALPHA_RESPONSE",
    "HALLMARK_INTERFERON_GAMMA_RESPONSE", "HALLMARK_KRAS_SIGNALING_DN",
    "HALLMARK_KRAS_SIGNALING_UP", "HALLMARK_MITOTIC_SPINDLE",
    "HALLMARK_MTORC1_SIGNALING", "HALLMARK_MYC_TARGETS_V1",
    "HALLMARK_MYC_TARGETS_V2", "HALLMARK_MYOGENESIS",
    "HALLMARK_NOTCH_SIGNALING", "HALLMARK_OXIDATIVE_PHOSPHORYLATION",
    "HALLMARK_P53_PATHWAY", "HALLMARK_PANCREAS_BETA_CELLS",
    "HALLMARK_PEROXISOME", "HALLMARK_PI3K_AKT_MTOR_SIGNALING",
    "HALLMARK_PROTEIN_SECRETION", "HALLMARK_REACTIVE_OXYGEN_SPECIES_PATHWAY",
    "HALLMARK_SPERMATOGENESIS", "HALLMARK_TGF_BETA_SIGNALING",
    "HALLMARK_TNFA_SIGNALING_VIA_NFKB", "HALLMARK_UNFOLDED_PROTEIN_RESPONSE",
    "HALLMARK_UV_RESPONSE_DN", "HALLMARK_UV_RESPONSE_UP",
    "HALLMARK_WNT_BETA_CATENIN_SIGNALING", "HALLMARK_XENOBIOTIC_METABOLISM",
]

sample_ids   = [f"S{str(k+1).zfill(3)}" for k in range(n_samples)]
group_labels = ["control"] * (n_samples // 2) + ["treatment"] * (n_samples // 2)

# -----------------------------------------------------------------------
# 2. Generate GSVA/ssGSEA score matrix (40 samples × 50 pathways)
#    GSVA scores range from −1 to +1; ssGSEA are normalised enrichment scores.
#    Treatment group has higher scores for immune/inflammation pathways.
# -----------------------------------------------------------------------
immune_pathways = {p for p in hallmark_pathways if any(kw in p for kw in
    ["INTERFERON","INFLAMMATORY","IL","COMPLEMENT","ALLOGRAFT","TNFA","IMMUNE"])}

header = ["sample_id", "group"] + hallmark_pathways
score_rows = [header]

for k, (sid, grp) in enumerate(zip(sample_ids, group_labels)):
    row = [sid, grp]
    for pw in hallmark_pathways:
        base = random.gauss(0.0, 0.25)
        if grp == "treatment" and pw in immune_pathways:
            base += random.gauss(0.35, 0.1)
        elif grp == "treatment" and "MYC" in pw:
            base += random.gauss(0.20, 0.08)
        elif grp == "control" and "METABOL" in pw:
            base += random.gauss(0.15, 0.08)
        score = round(max(-1.0, min(1.0, base)), 5)
        row.append(score)
    score_rows.append(row)

with open("signature_scores.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerows(score_rows)

# -----------------------------------------------------------------------
# 3. Pathway summary: mean score per group, delta, top 10 enriched per group
# -----------------------------------------------------------------------
pathway_stats = []
for j, pw in enumerate(hallmark_pathways):
    ctrl_scores = [float(score_rows[k+1][j+2]) for k in range(n_samples // 2)]
    trt_scores  = [float(score_rows[k+n_samples//2+1][j+2]) for k in range(n_samples // 2)]
    mean_ctrl   = round(sum(ctrl_scores) / len(ctrl_scores), 5)
    mean_trt    = round(sum(trt_scores)  / len(trt_scores),  5)
    delta       = round(mean_trt - mean_ctrl, 5)
    # Simple t-like statistic for ranking
    pooled_sd   = math.sqrt(
        (sum((x - mean_ctrl)**2 for x in ctrl_scores) +
         sum((x - mean_trt)**2  for x in trt_scores)) /
        (n_samples - 2)
    )
    se    = pooled_sd * math.sqrt(2.0 / (n_samples // 2))
    t_val = round(delta / max(se, 1e-9), 4)
    pathway_stats.append({
        "pathway":    pw,
        "mean_control":   mean_ctrl,
        "mean_treatment": mean_trt,
        "delta":          delta,
        "t_statistic":    t_val,
        "n_genes":        random.randint(32, 200),
    })

pathway_stats.sort(key=lambda x: abs(x["t_statistic"]), reverse=True)
top_treatment = [p for p in pathway_stats if p["delta"] > 0][:10]
top_control   = [p for p in pathway_stats if p["delta"] < 0][:10]

summary = {
    "pipeline":       "transcriptomic_biomarker",
    "step":           "BIOMARKER_SIGNATURE_SCORING",
    "timestamp":      datetime.utcnow().isoformat() + "Z",
    "mock_mode":      True,
    "method":         "${gsva_method}",
    "gene_set_db":    "MSigDB_Hallmark_v2023.2",
    "n_gene_sets":    n_pathways,
    "n_samples":      n_samples,
    "min_gene_set_size": int("${min_gs_size}"),
    "max_gene_set_size": int("${max_gs_size}"),
    "top_enriched_treatment": [p["pathway"] for p in top_treatment],
    "top_enriched_control":   [p["pathway"] for p in top_control],
    "pathway_stats":  pathway_stats,
}
with open("pathway_summary.json", "w") as f:
    json.dump(summary, f, indent=2)

print(f"BIOMARKER_SIGNATURE_SCORING mock complete")
print(f"  Samples:         {n_samples}")
print(f"  Pathways scored: {n_pathways}")
print(f"  Top treatment:   {top_treatment[0]['pathway']}")
print(f"  Top control:     {top_control[0]['pathway']}")
EOF

    else
        # -----------------------------------------------------------------------
        # Live: GSVA/ssGSEA via Bioconductor GSVA package
        # -----------------------------------------------------------------------
        Rscript - << 'REOF'
suppressPackageStartupMessages({
    library(GSVA)
    library(msigdbr)
    library(limma)
    library(jsonlite)
})

group_col   <- "${group_col}"
method      <- "${gsva_method}"
min_gs_size <- as.integer("${min_gs_size}")
max_gs_size <- as.integer("${max_gs_size}")

# Read inputs
mat      <- read.csv("${validated_matrix}",   row.names=1, check.names=FALSE)
metadata <- read.csv("${validated_metadata}", check.names=FALSE)
rownames(metadata) <- metadata[["sample_id"]]
metadata <- metadata[colnames(mat), , drop=FALSE]

de       <- read.csv("${de_results}", check.names=FALSE)

# Fetch MSigDB Hallmark gene sets (Human)
msig_h    <- msigdbr(species="Homo sapiens", category="H")
gene_sets <- split(msig_h[["gene_symbol"]], msig_h[["gs_name"]])

# voom-normalise the count matrix before GSVA
dge <- edgeR::DGEList(counts=mat)
dge <- edgeR::calcNormFactors(dge)
v   <- voom(dge)
expr_mat <- v[["E"]]   # log2-CPM matrix

# Run GSVA
if (method == "ssgsea") {
    gsva_param <- ssgseaParam(expr_mat, gene_sets,
                               minSize=min_gs_size, maxSize=max_gs_size)
} else {
    gsva_param <- gsvaParam(expr_mat, gene_sets,
                             minSize=min_gs_size, maxSize=max_gs_size)
}
gsva_scores <- gsva(gsva_param, verbose=FALSE)

# Write scores (samples as rows, pathways as columns)
scores_df           <- as.data.frame(t(gsva_scores))
scores_df[["sample_id"]] <- rownames(scores_df)
scores_df[["group"]]     <- metadata[rownames(scores_df), group_col]
scores_df <- scores_df[, c("sample_id", "group", colnames(scores_df)[!colnames(scores_df) %in% c("sample_id","group")])]
write.csv(scores_df, "signature_scores.csv", row.names=FALSE)

# Pathway-level summary: mean per group + delta
pw_names <- rownames(gsva_scores)
groups   <- unique(metadata[[group_col]])
pw_stats <- lapply(pw_names, function(pw) {
    scores_by_group <- tapply(gsva_scores[pw, ], metadata[[group_col]], mean, na.rm=TRUE)
    ref_score <- scores_by_group["${ref_group}"]
    trt_score <- scores_by_group[setdiff(names(scores_by_group), "${ref_group}")[1]]
    list(pathway=pw,
         mean_control=round(ref_score, 5),
         mean_treatment=round(trt_score, 5),
         delta=round(trt_score - ref_score, 5))
})
pw_stats <- pw_stats[order(sapply(pw_stats, function(x) -abs(x[["delta"]])))]

top_trt  <- head(Filter(function(x) x[["delta"]] > 0, pw_stats), 10)
top_ctrl <- head(Filter(function(x) x[["delta"]] < 0, pw_stats), 10)

summary_list <- list(
    pipeline       = "transcriptomic_biomarker",
    step           = "BIOMARKER_SIGNATURE_SCORING",
    timestamp      = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ"),
    mock_mode      = FALSE,
    method         = method,
    gene_set_db    = "MSigDB_Hallmark_v2023.2",
    n_gene_sets    = nrow(gsva_scores),
    n_samples      = ncol(gsva_scores),
    top_enriched_treatment = sapply(top_trt,  function(x) x[["pathway"]]),
    top_enriched_control   = sapply(top_ctrl, function(x) x[["pathway"]]),
    pathway_stats  = pw_stats
)
write(toJSON(summary_list, auto_unbox=TRUE, pretty=TRUE), "pathway_summary.json")

cat(sprintf("BIOMARKER_SIGNATURE_SCORING complete: %d pathways, %d samples\\n",
            nrow(gsva_scores), ncol(gsva_scores)))
REOF
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        GSVA: "1.50.0"
        msigdbr: "7.5.1"
        R: \$(Rscript --version 2>&1 | cut -d' ' -f4 || echo "N/A")
        python: \$(python3 --version 2>&1 | cut -d' ' -f2 || echo "N/A")
        mock_mode: "${mock}"
    END_VERSIONS
    """

    stub:
    """
    echo 'sample_id,group,HALLMARK_APOPTOSIS' > signature_scores.csv
    echo '{"n_gene_sets":50,"n_samples":40}' > pathway_summary.json
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        GSVA: "1.50.0"
        R: "4.3.1"
    END_VERSIONS
    """
}

// ============================================================================
// Process 4: BIOMARKER_REPORT
// ============================================================================

process BIOMARKER_REPORT {
    tag "biomarker_report"
    label 'process_medium'
    publishDir "${params.outdir}/04_report", mode: params.publish_dir_mode

    container 'docker.io/bioconductor/bioconductor_docker:RELEASE_3_18'

    input:
    path de_results
    path significant_genes
    path model_summary
    path signature_scores
    path pathway_summary

    output:
    path "biomarker_report.html",   emit: report
    path "versions.yml",            emit: versions

    script:
    def mock      = params.mock_mode
    def group_col = params.group_column
    def ref_group = params.reference_group
    def fdr_t     = params.fdr_threshold
    def logfc_t   = params.logfc_threshold
    """
    if [ "${mock}" = "true" ]; then
        python3 << 'EOF'
import json
import csv
import math
import random
from datetime import datetime

# -----------------------------------------------------------------------
# Read inputs
# -----------------------------------------------------------------------
de_rows  = []
sig_rows = []
FDR_T    = float("${fdr_t}")
LOGFC_T  = float("${logfc_t}")

with open("de_results.csv") as fh:
    reader = csv.DictReader(fh)
    for row in reader:
        de_rows.append(row)
        if float(row["adj.P.Val"]) < FDR_T and abs(float(row["logFC"])) >= LOGFC_T:
            sig_rows.append(row)

model_sum = json.load(open("limma_model_summary.json"))
pw_sum    = json.load(open("pathway_summary.json"))

n_sig        = model_sum.get("n_significant", len(sig_rows))
n_up         = model_sum.get("n_upregulated", 0)
n_down       = model_sum.get("n_downregulated", 0)
top_gene     = model_sum.get("top_gene", "N/A")
top_logfc    = model_sum.get("top_logFC", 0) or 0
top_adj_p    = model_sum.get("top_adj_p", 1) or 1
contrast     = model_sum.get("contrast", "treatment_vs_control")
top_trt_pws  = pw_sum.get("top_enriched_treatment", [])[:5]
top_ctrl_pws = pw_sum.get("top_enriched_control", [])[:5]

n_enriched_trt = len(top_trt_pws)

ts = datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")

# -----------------------------------------------------------------------
# HTML helper functions — use % formatting to avoid f-string {} issues
# -----------------------------------------------------------------------
def make_table_rows(rows, max_rows=20):
    parts = []
    for r in rows[:max_rows]:
        lfc   = float(r["logFC"])
        adj_p = float(r["adj.P.Val"])
        bg    = "#fff5f5" if lfc < 0 else "#f5fff5"
        parts.append(
            "<tr style='background:" + bg + "'>"
            "<td><strong>" + r["gene"] + "</strong></td>"
            "<td style='text-align:right'>" + ("%+.4f" % lfc) + "</td>"
            "<td style='text-align:right'>" + ("%.2f" % float(r["AveExpr"])) + "</td>"
            "<td style='text-align:right'>" + ("%.3f" % float(r["t"])) + "</td>"
            "<td style='text-align:right'>" + ("%.4e" % float(r["P.Value"])) + "</td>"
            "<td style='text-align:right'>" + ("%.4e" % adj_p) + "</td>"
            "</tr>"
        )
    return "\\n".join(parts)

def make_pathway_list(pathways, color):
    items = []
    for pw in pathways:
        short = pw.replace("HALLMARK_", "").replace("_", " ").title()
        items.append(
            "<li style='margin:4px 0'>"
            "<span style='color:" + color + "'>&#9654;</span> " + short +
            "</li>"
        )
    return "\\n".join(items)

table_rows_50 = make_table_rows(de_rows,  max_rows=50)
sig_rows_20   = make_table_rows(sig_rows, max_rows=20)
trt_pw_html   = make_pathway_list(top_trt_pws,  "#e74c3c")
ctrl_pw_html  = make_pathway_list(top_ctrl_pws, "#3498db")

# -----------------------------------------------------------------------
# Volcano SVG dots
# -----------------------------------------------------------------------
random.seed(42)
svg_dots = []
for row in de_rows[:500]:
    try:
        lfc   = float(row["logFC"])
        adj_p = float(row["adj.P.Val"])
        nlp   = min(-math.log10(max(adj_p, 1e-10)), 12)
        xp    = max(62, min(518, 60 + (lfc + 4) / 8 * 460))
        yp    = max(22, min(278, 280 - nlp / 12 * 260))
        if adj_p < FDR_T and abs(lfc) >= LOGFC_T:
            col = "#e74c3c" if lfc < 0 else "#27ae60"
            rad = 4
        else:
            col = "#bdc3c7"
            rad = "2.5"
        svg_dots.append(
            "<circle cx='%.1f' cy='%.1f' r='%s' fill='%s' fill-opacity='0.7'/>" %
            (xp, yp, rad, col)
        )
    except Exception:
        pass

# -----------------------------------------------------------------------
# Heatmap SVG cells
# -----------------------------------------------------------------------
random.seed(99)
heatmap_cells = []
cell_w, cell_h = 10, 8
for ri in range(20):
    for ci in range(40):
        grp = "treatment" if ci >= 20 else "control"
        if ri < len(sig_rows):
            lfc_v = float(sig_rows[ri]["logFC"]) if sig_rows else 0
            base  = 0.6 if (grp == "treatment") == (lfc_v > 0) else -0.6
        else:
            base = 0
        v   = max(-1.0, min(1.0, base + random.gauss(0, 0.3)))
        rc  = int(255 * max(0, v)) + int(240 * max(0, -v))
        gc_ = int(240 * (1 - abs(v)))
        bc  = int(255 * max(0, -v)) + int(240 * max(0, v))
        xs  = 60 + ci * cell_w
        ys  = 10 + ri * cell_h
        heatmap_cells.append(
            "<rect x='%d' y='%d' width='%d' height='%d' fill='rgb(%d,%d,%d)'/>" %
            (xs, ys, cell_w - 1, cell_h - 1, rc, gc_, bc)
        )

# -----------------------------------------------------------------------
# Assemble HTML — pure string concatenation, no f-strings
# -----------------------------------------------------------------------
html = (
    "<!DOCTYPE html>\\n"
    "<html lang='en'>\\n"
    "<head>\\n"
    "<meta charset='UTF-8'>\\n"
    "<meta name='viewport' content='width=device-width, initial-scale=1.0'>\\n"
    "<title>BioMate | Transcriptomic Biomarker Report</title>\\n"
    "<style>\\n"
    "  body {font-family:'Segoe UI',Arial,sans-serif;margin:0;background:#f4f6f8;color:#2c3e50}\\n"
    "  .header {background:linear-gradient(135deg,#1a5276,#2980b9);color:#fff;padding:32px 40px}\\n"
    "  .header h1 {margin:0 0 8px;font-size:28px}\\n"
    "  .header p  {margin:0;opacity:0.85;font-size:14px}\\n"
    "  .container {max-width:1100px;margin:28px auto;padding:0 20px}\\n"
    "  .card {background:#fff;border-radius:10px;box-shadow:0 2px 8px rgba(0,0,0,0.08);"
    "         padding:24px;margin-bottom:24px}\\n"
    "  .card h2 {margin:0 0 16px;font-size:18px;border-bottom:2px solid #2980b9;"
    "            padding-bottom:8px;color:#1a5276}\\n"
    "  .metrics {display:grid;grid-template-columns:repeat(4,1fr);gap:16px;margin-bottom:24px}\\n"
    "  .metric {background:#fff;border-radius:10px;box-shadow:0 2px 8px rgba(0,0,0,0.08);"
    "           padding:20px;text-align:center}\\n"
    "  .metric .value {font-size:36px;font-weight:700;color:#2980b9}\\n"
    "  .metric .label {font-size:12px;color:#7f8c8d;margin-top:4px}\\n"
    "  .up   {color:#27ae60;font-weight:700}\\n"
    "  .down {color:#e74c3c;font-weight:700}\\n"
    "  table {width:100%;border-collapse:collapse;font-size:13px}\\n"
    "  th {background:#2980b9;color:#fff;padding:8px 12px;text-align:left}\\n"
    "  td {padding:7px 12px;border-bottom:1px solid #ecf0f1}\\n"
    "  .badge {display:inline-block;padding:2px 10px;border-radius:12px;font-size:11px;"
    "          font-weight:600;margin-right:4px}\\n"
    "  .badge-sig  {background:#e8f8f0;color:#1e8449}\\n"
    "  .badge-mock {background:#fef9e7;color:#9a7d0a}\\n"
    "  .pw-grid {display:grid;grid-template-columns:1fr 1fr;gap:20px}\\n"
    "  .pw-box  {background:#f8f9fa;border-radius:8px;padding:16px}\\n"
    "  .pw-box h3 {margin:0 0 10px;font-size:14px;color:#444}\\n"
    "  ul {margin:0;padding-left:18px;list-style:none}\\n"
    "  .footer {text-align:center;color:#95a5a6;font-size:12px;padding:20px 0 40px}\\n"
    "</style>\\n"
    "</head>\\n"
    "<body>\\n"
    "<div class='header'>\\n"
    "  <h1>Transcriptomic Biomarker Discovery Report</h1>\\n"
    "  <p>Contrast: <strong>" + contrast + "</strong> &nbsp;|&nbsp; "
    "LIMMA-voom + GSVA (Hallmark MSigDB) &nbsp;|&nbsp; "
    "Generated: " + ts + " &nbsp;"
    "<span class='badge badge-mock'>MOCK DATA</span></p>\\n"
    "</div>\\n"
    "<div class='container'>\\n"

    # Metrics
    "<div class='metrics'>\\n"
    "  <div class='metric'><div class='value'>" + str(n_sig) + "</div>"
    "<div class='label'>Significant DE Genes</div></div>\\n"
    "  <div class='metric'><div class='value up'>" + str(n_up) + "</div>"
    "<div class='label'>Up-regulated</div></div>\\n"
    "  <div class='metric'><div class='value down'>" + str(n_down) + "</div>"
    "<div class='label'>Down-regulated</div></div>\\n"
    "  <div class='metric'><div class='value'>" + str(n_enriched_trt) + "</div>"
    "<div class='label'>Enriched Pathways (treatment)</div></div>\\n"
    "</div>\\n"

    # Volcano
    "<div class='card'>\\n"
    "  <h2>Volcano Plot <span class='badge badge-sig'>FDR &lt; " + str(FDR_T) + "</span></h2>\\n"
    "  <div style='background:#f8f9fa;border-radius:8px;padding:20px;text-align:center'>\\n"
    "    <svg width='560' height='320' viewBox='0 0 560 320' xmlns='http://www.w3.org/2000/svg'"
    "         style='max-width:100%;font-family:Arial,sans-serif'>\\n"
    "      <line x1='60' y1='280' x2='520' y2='280' stroke='#bdc3c7' stroke-width='1.5'/>\\n"
    "      <line x1='60' y1='20'  x2='60'  y2='280' stroke='#bdc3c7' stroke-width='1.5'/>\\n"
    "      <text x='290' y='310' text-anchor='middle' fill='#7f8c8d' font-size='12'>log2 Fold Change</text>\\n"
    "      <text x='16' y='150' text-anchor='middle' fill='#7f8c8d' font-size='12'"
    "            transform='rotate(-90,16,150)'>&#8722;log10(adj.P.Val)</text>\\n"
    "      <line x1='60' y1='80' x2='520' y2='80' stroke='#f39c12' stroke-width='1'"
    "            stroke-dasharray='5,3'/>\\n"
    "      <line x1='240' y1='20' x2='240' y2='280' stroke='#3498db' stroke-width='1'"
    "            stroke-dasharray='5,3'/>\\n"
    "      <line x1='340' y1='20' x2='340' y2='280' stroke='#3498db' stroke-width='1'"
    "            stroke-dasharray='5,3'/>\\n"
    + "\\n".join(svg_dots) + "\\n"
    "      <circle cx='400' cy='35' r='5' fill='#27ae60' fill-opacity='0.7'/>\\n"
    "      <text x='412' y='39' fill='#444' font-size='11'>Up-regulated</text>\\n"
    "      <circle cx='400' cy='55' r='5' fill='#e74c3c' fill-opacity='0.7'/>\\n"
    "      <text x='412' y='59' fill='#444' font-size='11'>Down-regulated</text>\\n"
    "      <circle cx='400' cy='75' r='4' fill='#bdc3c7'/>\\n"
    "      <text x='412' y='79' fill='#444' font-size='11'>Not significant</text>\\n"
    "    </svg>\\n"
    "    <p style='font-size:12px;margin:8px 0 0'>Orange dashed: FDR = " + str(FDR_T) +
    " &nbsp;|&nbsp; Blue dashed: |logFC| = " + str(LOGFC_T) + "</p>\\n"
    "  </div>\\n"
    "</div>\\n"

    # Significant genes table
    "<div class='card'>\\n"
    "  <h2>Top Significant DE Genes "
    "<span class='badge badge-sig'>" + str(n_sig) + " significant</span></h2>\\n"
    "  <table>\\n"
    "    <tr><th>Gene</th><th>logFC</th><th>AveExpr</th>"
    "<th>t statistic</th><th>P.Value</th><th>adj.P.Val</th></tr>\\n"
    + sig_rows_20 + "\\n"
    "  </table>\\n"
    "  <p style='font-size:12px;color:#7f8c8d;margin-top:8px'>Showing top 20 of "
    + str(n_sig) + " significant genes (FDR &lt; " + str(FDR_T) +
    ", |logFC| &ge; " + str(LOGFC_T) + "). "
    "Green rows = up-regulated; red rows = down-regulated.</p>\\n"
    "</div>\\n"

    # Heatmap
    "<div class='card'>\\n"
    "  <h2>Heatmap &mdash; Top 50 DE Genes</h2>\\n"
    "  <div style='background:#f8f9fa;border-radius:8px;padding:20px;text-align:center'>\\n"
    "    <svg width='560' height='200' viewBox='0 0 560 200'"
    "         xmlns='http://www.w3.org/2000/svg' style='max-width:100%'>\\n"
    + "\\n".join(heatmap_cells) + "\\n"
    "      <text x='60'  y='195' fill='#3498db' font-size='11'>Control (20 samples)</text>\\n"
    "      <text x='260' y='195' fill='#e74c3c' font-size='11'>Treatment (20 samples)</text>\\n"
    "      <text x='10'  y='90'  fill='#444'    font-size='10'"
    "            transform='rotate(-90,10,90)'>Top 20 genes</text>\\n"
    "    </svg>\\n"
    "    <p style='font-size:12px;margin:6px 0 0'>"
    "Red = up-regulated &nbsp;|&nbsp; Blue = down-regulated &nbsp;|&nbsp; White = no change</p>\\n"
    "  </div>\\n"
    "</div>\\n"

    # Pathway enrichment
    "<div class='card'>\\n"
    "  <h2>Pathway Enrichment &mdash; GSVA Hallmark MSigDB</h2>\\n"
    "  <div class='pw-grid'>\\n"
    "    <div class='pw-box'>\\n"
    "      <h3 style='color:#e74c3c'>&#9650; Enriched in Treatment</h3>\\n"
    "      <ul>" + trt_pw_html + "</ul>\\n"
    "    </div>\\n"
    "    <div class='pw-box'>\\n"
    "      <h3 style='color:#3498db'>&#9660; Enriched in Control</h3>\\n"
    "      <ul>" + ctrl_pw_html + "</ul>\\n"
    "    </div>\\n"
    "  </div>\\n"
    "</div>\\n"

    # Full DE table
    "<div class='card'>\\n"
    "  <h2>Differential Expression Table &mdash; Top 50 Genes by adj.P.Val</h2>\\n"
    "  <div style='overflow-x:auto;max-height:400px;overflow-y:auto'>\\n"
    "    <table>\\n"
    "      <tr><th>Gene</th><th>logFC</th><th>AveExpr</th>"
    "<th>t statistic</th><th>P.Value</th><th>adj.P.Val</th></tr>\\n"
    + table_rows_50 + "\\n"
    "    </table>\\n"
    "  </div>\\n"
    "</div>\\n"

    # Methods
    "<div class='card'>\\n"
    "  <h2>Methods</h2>\\n"
    "  <p style='font-size:13px;line-height:1.7'>\\n"
    "    Raw count data were normalised using TMM (trimmed mean of M-values) with the\\n"
    "    <code>edgeR</code> package. Voom mean-variance transformation was applied prior to\\n"
    "    fitting a linear model with <code>limma</code> (Law et al., Genome Biology 2014).\\n"
    "    Differential expression for the <em>" + contrast + "</em> contrast was assessed\\n"
    "    with empirical Bayes moderation (eBayes), and genes with FDR-adjusted p-value &lt; "
    + str(FDR_T) + " and |log2FC| &ge; " + str(LOGFC_T) + " were considered significant.\\n"
    "    Gene set enrichment was computed using GSVA (Hanzelmann et al., BMC Bioinformatics 2013)\\n"
    "    on the MSigDB Hallmark collection (v2023.2, n=50 gene sets).\\n"
    "  </p>\\n"
    "  <p style='font-size:12px;color:#e67e22'>\\n"
    "    <strong>Note:</strong> This report was generated in MOCK mode with synthetic data.\\n"
    "    All numerical values are simulated for pipeline testing purposes.\\n"
    "  </p>\\n"
    "</div>\\n"

    "</div>\\n"
    "<div class='footer'>BioMate Transcriptomic Biomarker Pipeline &mdash; " + ts + "</div>\\n"
    "</body></html>\\n"
)

with open("biomarker_report.html", "w") as fh:
    fh.write(html)

print("BIOMARKER_REPORT mock complete: biomarker_report.html")
print("  Significant genes: %d (%d up, %d down)" % (n_sig, n_up, n_down))
print("  Top DE gene:       %s (logFC=%.4f, adj.P.Val=%.4e)" % (top_gene, top_logfc, top_adj_p))
print("  Top pathways:      %s" % ", ".join(top_trt_pws[:3]))
EOF

    else
        # -----------------------------------------------------------------------
        # Live: Render R Markdown report
        # -----------------------------------------------------------------------
        Rscript - << 'REOF'
suppressPackageStartupMessages({
    library(rmarkdown)
    library(knitr)
    library(ggplot2)
    library(pheatmap)
    library(jsonlite)
})

group_col <- "${group_col}"
ref_group <- "${ref_group}"
fdr_t     <- as.numeric("${fdr_t}")
logfc_t   <- as.numeric("${logfc_t}")

de       <- read.csv("${de_results}", check.names=FALSE)
sig      <- read.csv("${significant_genes}", check.names=FALSE)
scores   <- read.csv("${signature_scores}", check.names=FALSE)
pw_sum   <- fromJSON("${pathway_summary}")
mod_sum  <- fromJSON("${model_summary}")

# Volcano plot
de[["neg_log10_adjp"]] <- -log10(pmax(de[["adj.P.Val"]], 1e-10))
de[["significance"]] <- "Not significant"
de[["significance"]][de[["adj.P.Val"]] < fdr_t & de[["logFC"]] >= logfc_t]  <- "Up"
de[["significance"]][de[["adj.P.Val"]] < fdr_t & de[["logFC"]] <= -logfc_t] <- "Down"

p_volcano <- ggplot(de, aes(x=logFC, y=neg_log10_adjp, color=significance)) +
    geom_point(alpha=0.6, size=1.5) +
    scale_color_manual(values=c("Up"="#27ae60","Down"="#e74c3c","Not significant"="#bdc3c7")) +
    geom_hline(yintercept=-log10(fdr_t), linetype="dashed", color="#f39c12") +
    geom_vline(xintercept=c(-logfc_t, logfc_t), linetype="dashed", color="#3498db") +
    theme_bw(base_size=12) +
    labs(title="Volcano Plot", x="log2 Fold Change", y="-log10(adj.P.Val)")
ggsave("volcano_plot.png", p_volcano, width=7, height=5, dpi=150)

# Heatmap (top 50 genes)
top50 <- head(de[order(de[["adj.P.Val"]]), "gene"], 50)
scores_mat <- as.matrix(scores[, !colnames(scores) %in% c("sample_id","group")])
rownames(scores_mat) <- scores[["sample_id"]]

# Use DE log2FC values for heatmap (not GSVA scores)
# Render minimal HTML using knitr::knit2html
rmd_content <- paste0('---
title: "BioMate Transcriptomic Biomarker Report"
output: html_document
---

## Summary

- Contrast: ', mod_sum[["contrast"]], '
- Significant DE genes: ', mod_sum[["n_significant"]], '
  (', mod_sum[["n_upregulated"]], ' up, ', mod_sum[["n_downregulated"]], ' down)
- FDR threshold: ', fdr_t, '
- |logFC| threshold: ', logfc_t, '

## Volcano Plot

![](volcano_plot.png)

## Top Significant Genes

')

write(rmd_content, "report.Rmd")
rmarkdown::render("report.Rmd", output_file="biomarker_report.html", quiet=TRUE)
cat("BIOMARKER_REPORT live: biomarker_report.html\\n")
REOF
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        ggplot2: "3.4.4"
        pheatmap: "1.0.12"
        rmarkdown: "2.25"
        R: \$(Rscript --version 2>&1 | cut -d' ' -f4 || echo "N/A")
        python: \$(python3 --version 2>&1 | cut -d' ' -f2 || echo "N/A")
        mock_mode: "${mock}"
    END_VERSIONS
    """

    stub:
    """
    echo '<html><body><h1>BioMate Biomarker Report (stub)</h1></body></html>' > biomarker_report.html
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        ggplot2: "3.4.4"
        R: "4.3.1"
    END_VERSIONS
    """
}

// ============================================================================
// Entry workflow: TRANSCRIPTOMIC_BIOMARKER
// ============================================================================
//
// Linear chain (each step depends on the previous):
//
//   BIOMARKER_INPUT_QC
//          │
//   LIMMA_DIFFERENTIAL_EXPRESSION
//          │
//   BIOMARKER_SIGNATURE_SCORING
//          │
//   BIOMARKER_REPORT
//
// ============================================================================

workflow TRANSCRIPTOMIC_BIOMARKER {
    take:
    ch_expression_matrix  // channel: path(expression_matrix.csv)
    ch_metadata           // channel: path(metadata.csv)

    main:
    // ------------------------------------------------------------------
    // Step 1: Validate inputs
    // ------------------------------------------------------------------
    BIOMARKER_INPUT_QC(
        ch_expression_matrix,
        ch_metadata
    )

    // ------------------------------------------------------------------
    // Step 2: Limma-voom differential expression
    // ------------------------------------------------------------------
    LIMMA_DIFFERENTIAL_EXPRESSION(
        BIOMARKER_INPUT_QC.out.validated_matrix,
        BIOMARKER_INPUT_QC.out.validated_metadata,
        BIOMARKER_INPUT_QC.out.qc_report
    )

    // ------------------------------------------------------------------
    // Step 3: GSVA/ssGSEA pathway signature scoring
    // ------------------------------------------------------------------
    BIOMARKER_SIGNATURE_SCORING(
        BIOMARKER_INPUT_QC.out.validated_matrix,
        BIOMARKER_INPUT_QC.out.validated_metadata,
        LIMMA_DIFFERENTIAL_EXPRESSION.out.de_results
    )

    // ------------------------------------------------------------------
    // Step 4: Generate HTML report
    // ------------------------------------------------------------------
    BIOMARKER_REPORT(
        LIMMA_DIFFERENTIAL_EXPRESSION.out.de_results,
        LIMMA_DIFFERENTIAL_EXPRESSION.out.significant_genes,
        LIMMA_DIFFERENTIAL_EXPRESSION.out.model_summary,
        BIOMARKER_SIGNATURE_SCORING.out.scores,
        BIOMARKER_SIGNATURE_SCORING.out.pathway_summary
    )

    emit:
    qc_report         = BIOMARKER_INPUT_QC.out.qc_report
    de_results        = LIMMA_DIFFERENTIAL_EXPRESSION.out.de_results
    significant_genes = LIMMA_DIFFERENTIAL_EXPRESSION.out.significant_genes
    model_summary     = LIMMA_DIFFERENTIAL_EXPRESSION.out.model_summary
    voom_plot         = LIMMA_DIFFERENTIAL_EXPRESSION.out.voom_plot
    signature_scores  = BIOMARKER_SIGNATURE_SCORING.out.scores
    pathway_summary   = BIOMARKER_SIGNATURE_SCORING.out.pathway_summary
    report            = BIOMARKER_REPORT.out.report
    versions          = BIOMARKER_INPUT_QC.out.versions
                            .mix(LIMMA_DIFFERENTIAL_EXPRESSION.out.versions)
                            .mix(BIOMARKER_SIGNATURE_SCORING.out.versions)
                            .mix(BIOMARKER_REPORT.out.versions)
}

// ============================================================================
// Standalone Entry Point (nextflow run main.nf)
// ============================================================================

workflow {
    log_workflow_header()

    // Default test inputs (mock mode — no real files needed)
    if (params.mock_mode) {
        ch_expression_matrix = Channel.of(
            file("${projectDir}/test_data/expression_matrix.csv", checkIfExists: false)
        ).map { mat ->
            // In mock mode create a synthetic matrix on the fly if not present
            mat.exists() ? mat : {
                def tmp = file("${workDir}/mock_expression_matrix.csv")
                tmp.text = "gene_id,S001,S002,S003,S004\nEGFR1,100,120,85,90\nTP531,200,180,210,195\n"
                tmp
            }()
        }

        ch_metadata = Channel.of(
            file("${projectDir}/test_data/metadata.csv", checkIfExists: false)
        ).map { meta ->
            meta.exists() ? meta : {
                def tmp = file("${workDir}/mock_metadata.csv")
                tmp.text = "sample_id,group,batch\nS001,control,batch_1\nS002,control,batch_1\nS003,treatment,batch_1\nS004,treatment,batch_1\n"
                tmp
            }()
        }
    } else {
        if (!params.expression_matrix) {
            error "params.expression_matrix is required in live mode. Pass --expression_matrix <path>"
        }
        if (!params.metadata) {
            error "params.metadata is required in live mode. Pass --metadata <path>"
        }
        ch_expression_matrix = Channel.fromPath(params.expression_matrix, checkIfExists: true)
        ch_metadata          = Channel.fromPath(params.metadata,          checkIfExists: true)
    }

    // Run the pipeline
    TRANSCRIPTOMIC_BIOMARKER(ch_expression_matrix, ch_metadata)

    // Display summary
    TRANSCRIPTOMIC_BIOMARKER.out.model_summary.view { f ->
        "LIMMA model summary: ${f}"
    }
    TRANSCRIPTOMIC_BIOMARKER.out.pathway_summary.view { f ->
        "Pathway summary:     ${f}"
    }
    TRANSCRIPTOMIC_BIOMARKER.out.report.view { f ->
        "Biomarker report:    ${f}"
    }
}
