#!/usr/bin/env nextflow
/*
 * genomics/geo_data_connector
 *
 * GEO / TCGA data connector — Sprint 2 RNA-seq gap closure.
 * Given a GEO accession (GSE or GSM), auto-fetches the count matrix and
 * clinical metadata, then emits channels ready for downstream DE workflows.
 *
 * Steps:
 *   1. GEO_FETCH            — Download series matrix via GEOquery::getGEO()
 *   2. GEO_COUNT_MATRIX     — Extract expression / count matrix (genes × samples)
 *   3. GEO_CLINICAL_METADATA — Clean and standardise clinical / phenotype metadata
 *
 * References:
 *   Davis S, Meltzer PS (2007) GEOquery: a bridge between the Gene Expression
 *   Omnibus (GEO) and BioConductor. Bioinformatics 23(14):1846-1847.
 *   https://doi.org/10.1093/bioinformatics/btm254
 */

nextflow.enable.dsl = 2

// ─── Parameters ─────────────────────────────────────────────────────────────

params.outdir    = './results'
params.mock_mode = true

// GEO accession: either a series (GSE…) or a sample (GSM…)
params.accession = 'GSE999999'

// Optional: path to a local GSE series matrix file (skips download when set)
params.local_series_matrix = null

// ─── PROCESS 1: GEO_FETCH ───────────────────────────────────────────────────

process GEO_FETCH {
    tag "${meta.id}"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}/geo_fetch", mode: 'copy'

    container 'quay.io/biocontainers/bioconductor-geoquery:2.72.0--r44_0'

    input:
    val(meta)   // meta map; meta.accession holds the GSE/GSM ID

    output:
    tuple val(meta), path("series_matrix.rds")   , emit: series_matrix_rds
    tuple val(meta), path("sample_metadata.csv") , emit: sample_metadata
    path "versions.yml"                           , emit: versions

    script:
    def accession = meta.accession ?: params.accession
    if (params.mock_mode) {
        """
        Rscript - <<'REOF'
# Mock mode: generate a synthetic ExpressionSet-like RDS and pData CSV
# so downstream processes can be developed and tested without network access.
set.seed(42)

n_genes   <- 200L
n_samples <- 20L

accession <- "${accession}"

# ── Gene symbols ─────────────────────────────────────────────────────────────
landmark_genes <- c(
    "GAPDH", "TP53", "BRCA1", "BRCA2", "EGFR", "MYC", "KRAS", "PTEN",
    "RB1",   "AKT1", "VEGFA", "CDKN2A", "CDH1", "VHL", "MLH1",
    "MTOR",  "PIK3CA", "BRAF", "NRAS",  "ERBB2"
)
extra_genes <- paste0("GENE", formatC(seq_len(n_genes - length(landmark_genes)),
                                      width = 4, flag = "0"))
gene_symbols <- c(landmark_genes, extra_genes)

# ── Sample IDs (GSM-style accessions) ───────────────────────────────────────
gsm_start <- 1234567L
gsm_ids   <- paste0("GSM", seq(gsm_start, gsm_start + n_samples - 1L))

# ── Simulated count / expression matrix ─────────────────────────────────────
# Negative-binomial-like: base expression + treatment effect for half samples
set.seed(1)
base_expr <- matrix(
    rnbinom(n_genes * n_samples, mu = 500, size = 10),
    nrow = n_genes, ncol = n_samples,
    dimnames = list(gene_symbols, gsm_ids)
)
# Introduce a mild treatment effect in samples 11-20 for first 20 genes
treatment_mask <- c(rep(FALSE, 10), rep(TRUE, 10))
base_expr[1:20, treatment_mask] <- base_expr[1:20, treatment_mask] *
    round(runif(20, 1.5, 3.0), 1)

# ── pData (phenotype / sample metadata) ─────────────────────────────────────
set.seed(2)
pdata <- data.frame(
    geo_accession       = gsm_ids,
    title               = paste0("Sample_", seq_len(n_samples)),
    source_name_ch1     = rep(c("tumor", "normal"), each = n_samples / 2),
    organism_ch1        = "Homo sapiens",
    treatment_protocol_ch1 = ifelse(treatment_mask, "Drug_A_100nM", "Vehicle"),
    age                 = round(runif(n_samples, 35, 75)),
    Sex                 = sample(c("Male", "Female"), n_samples, replace = TRUE),
    overall_survival_months = round(runif(n_samples, 6, 60), 1),
    vital_status        = sample(c("Alive", "Dead"), n_samples, replace = TRUE,
                                 prob = c(0.6, 0.4)),
    platform_id         = "GPL570",
    data_processing     = "RMA normalised",
    stringsAsFactors    = FALSE,
    row.names           = gsm_ids
)

# ── Build a minimal list mimicking GEOquery's getGEO() output ────────────────
geo_obj <- list(
    accession    = accession,
    exprs        = base_expr,
    pData        = pdata,
    featureData  = data.frame(
        ID     = gene_symbols,
        Symbol = gene_symbols,
        row.names = gene_symbols,
        stringsAsFactors = FALSE
    )
)
class(geo_obj) <- "BioMateMockGEO"

saveRDS(geo_obj, "series_matrix.rds")
write.csv(pdata, "sample_metadata.csv", row.names = TRUE, quote = TRUE)

cat("Mock GEO_FETCH complete\\n")
cat("  Accession :", accession, "\\n")
cat("  Genes     :", n_genes,   "\\n")
cat("  Samples   :", n_samples, "\\n")
REOF

        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            r-base: \$(R --version | head -1 | awk '{print \$3}')
            bioconductor-geoquery: "2.72.0 (mock)"
        END_VERSIONS
        """
    } else {
        """
        Rscript - <<'REOF'
suppressPackageStartupMessages({
    library(GEOquery)
    library(Biobase)
})

accession <- "${accession}"

message("Fetching GEO accession: ", accession)

# Download — handle both GSE and GSM prefixes
# Use temp dir inside workdir to avoid container permission issues
tmp_dir <- file.path(getwd(), ".geo_cache")
dir.create(tmp_dir, showWarnings = FALSE, recursive = TRUE)

geo_data <- tryCatch(
    getGEO(accession,
           GSEMatrix   = TRUE,
           destdir     = tmp_dir,
           getGPL      = FALSE,
           AnnotGPL    = FALSE),
    error = function(e) {
        message("getGEO() failed: ", conditionMessage(e))
        stop(e)
    }
)

# getGEO() returns a list when GSEMatrix=TRUE; take first element
geo_obj <- if (is.list(geo_data) && !is(geo_data, "ExpressionSet")) {
    geo_data[[1]]
} else {
    geo_data
}

saveRDS(geo_obj, "series_matrix.rds")

# Export pData (sample phenotype metadata)
pd <- pData(geo_obj)
write.csv(pd, "sample_metadata.csv", row.names = TRUE, quote = TRUE)

message("GEO_FETCH complete")
message("  Accession : ", accession)
message("  Samples   : ", nrow(pd))
if (is(geo_obj, "ExpressionSet")) {
    message("  Features  : ", nrow(exprs(geo_obj)))
}
REOF

        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            r-base: \$(R --version | head -1 | awk '{print \$3}')
            bioconductor-geoquery: \$(Rscript -e 'cat(as.character(packageVersion("GEOquery")))')
        END_VERSIONS
        """
    }
}

// ─── PROCESS 2: GEO_COUNT_MATRIX ────────────────────────────────────────────

process GEO_COUNT_MATRIX {
    tag "${meta.id}"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}/count_matrix", mode: 'copy'

    container 'quay.io/biocontainers/bioconductor-geoquery:2.72.0--r44_0'

    input:
    tuple val(meta), path(series_matrix_rds)

    output:
    tuple val(meta), path("count_matrix.csv")     , emit: count_matrix
    tuple val(meta), path("feature_metadata.csv") , emit: feature_metadata
    path "versions.yml"                            , emit: versions

    script:
    if (params.mock_mode) {
        """
        Rscript - <<'REOF'
geo_obj <- readRDS("${series_matrix_rds}")

# ── Extract expression matrix ─────────────────────────────────────────────
if (inherits(geo_obj, "BioMateMockGEO")) {
    # Mock object produced by GEO_FETCH mock mode
    expr_mat  <- geo_obj\$exprs
    feat_data <- geo_obj\$featureData
} else {
    suppressPackageStartupMessages(library(Biobase))
    expr_mat  <- exprs(geo_obj)
    feat_data <- as.data.frame(fData(geo_obj))
}

# ── count_matrix.csv — rows=genes, cols=samples, first col=gene_id ────────
count_df <- as.data.frame(expr_mat)
count_df  <- cbind(gene_id = rownames(count_df), count_df)
rownames(count_df) <- NULL

write.csv(count_df, "count_matrix.csv", row.names = FALSE, quote = TRUE)

# ── feature_metadata.csv ──────────────────────────────────────────────────
if (is.data.frame(feat_data)) {
    write.csv(feat_data, "feature_metadata.csv", row.names = TRUE, quote = TRUE)
} else {
    write.csv(
        data.frame(ID = rownames(expr_mat), Symbol = rownames(expr_mat)),
        "feature_metadata.csv", row.names = FALSE
    )
}

cat("GEO_COUNT_MATRIX complete\\n")
cat("  Genes   :", nrow(expr_mat), "\\n")
cat("  Samples :", ncol(expr_mat), "\\n")
REOF

        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            r-base: \$(R --version | head -1 | awk '{print \$3}')
            bioconductor-geoquery: "2.72.0 (mock)"
        END_VERSIONS
        """
    } else {
        """
        Rscript - <<'REOF'
suppressPackageStartupMessages({
    library(Biobase)
})

geo_obj <- readRDS("${series_matrix_rds}")

# Unwrap list if necessary (getGEO can return a list of ExpressionSets)
if (is.list(geo_obj) && !is(geo_obj, "ExpressionSet")) {
    geo_obj <- geo_obj[[1]]
}

# ── Extract expression matrix ─────────────────────────────────────────────
if (is(geo_obj, "ExpressionSet")) {
    expr_mat  <- exprs(geo_obj)
    feat_data <- as.data.frame(fData(geo_obj))
} else if (is(geo_obj, "SummarizedExperiment")) {
    suppressPackageStartupMessages(library(SummarizedExperiment))
    expr_mat  <- assay(geo_obj)
    feat_data <- as.data.frame(rowData(geo_obj))
} else {
    # Fallback: try list slot \$exprs (BioMate mock or plain list)
    expr_mat  <- geo_obj\$exprs
    feat_data <- geo_obj\$featureData
    if (!is.data.frame(feat_data)) {
        feat_data <- data.frame(ID = rownames(expr_mat), row.names = rownames(expr_mat))
    }
}

if (is.null(expr_mat) || nrow(expr_mat) == 0) {
    stop("No expression matrix found in the RDS object.")
}

# ── count_matrix.csv ─────────────────────────────────────────────────────
count_df <- as.data.frame(expr_mat)
count_df  <- cbind(gene_id = rownames(count_df), count_df)
rownames(count_df) <- NULL

write.csv(count_df, "count_matrix.csv", row.names = FALSE, quote = TRUE)

# ── feature_metadata.csv ─────────────────────────────────────────────────
write.csv(feat_data, "feature_metadata.csv", row.names = TRUE, quote = TRUE)

message("GEO_COUNT_MATRIX complete")
message("  Genes   : ", nrow(expr_mat))
message("  Samples : ", ncol(expr_mat))
REOF

        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            r-base: \$(R --version | head -1 | awk '{print \$3}')
            bioconductor-biobase: \$(Rscript -e 'cat(as.character(packageVersion("Biobase")))')
        END_VERSIONS
        """
    }
}

// ─── PROCESS 3: GEO_CLINICAL_METADATA ───────────────────────────────────────

process GEO_CLINICAL_METADATA {
    tag "${meta.id}"
    label 'process_low'
    publishDir "${params.outdir}/${meta.id}/clinical_metadata", mode: 'copy'

    container 'quay.io/biocontainers/bioconductor-geoquery:2.72.0--r44_0'

    input:
    tuple val(meta), path(sample_metadata_csv)

    output:
    tuple val(meta), path("clinical_metadata_clean.csv"), emit: clinical_metadata_clean
    path "versions.yml"                                  , emit: versions

    script:
    if (params.mock_mode) {
        """
        Rscript - <<'REOF'
raw <- read.csv("${sample_metadata_csv}", row.names = 1, stringsAsFactors = FALSE,
                check.names = FALSE)

# ── Canonical column renaming map ─────────────────────────────────────────
# Maps GEO free-text column variants → standardised names used by survival /
# DE tools downstream.
rename_map <- list(
    # Survival / event
    time  = c("overall_survival_months", "os_months", "survival_months",
               "days_to_last_followup",  "time",      "survival_time",
               "follow_up_months",       "months_to_event"),
    event = c("vital_status",  "os_event",    "event",
               "death_event",  "status",      "deceased",
               "overall_survival_status"),
    # Treatment
    treatment = c("treatment_protocol_ch1", "treatment",    "drug",
                   "drug_treatment",         "condition",    "arm",
                   "intervention"),
    # Demographics
    age = c("age", "age_at_diagnosis", "age_years",
             "patient_age",   "age_at_enrollment"),
    sex = c("Sex", "sex", "gender", "Gender",
             "biological_sex", "patient_sex")
)

clean <- raw

for (std_name in names(rename_map)) {
    candidates <- rename_map[[std_name]]
    matched    <- intersect(candidates, colnames(clean))
    if (length(matched) > 0 && !(std_name %in% colnames(clean))) {
        # Use the first matching column, rename it to the standard name
        colnames(clean)[colnames(clean) == matched[1]] <- std_name
    }
}

# ── Standardise event coding ──────────────────────────────────────────────
if ("event" %in% colnames(clean)) {
    ev <- tolower(trimws(as.character(clean\$event)))
    clean\$event <- ifelse(
        ev %in% c("dead", "deceased", "1", "true", "yes", "died"), 1L,
        ifelse(ev %in% c("alive", "living", "0", "false", "no", "censored"), 0L,
               NA_integer_)
    )
}

# ── Standardise sex coding ────────────────────────────────────────────────
if ("sex" %in% colnames(clean)) {
    sx <- tolower(trimws(as.character(clean\$sex)))
    clean\$sex <- ifelse(sx %in% c("male", "m"), "male",
                  ifelse(sx %in% c("female", "f"), "female", sx))
}

# ── Coerce numeric columns ────────────────────────────────────────────────
for (col in c("time", "age")) {
    if (col %in% colnames(clean)) {
        clean[[col]] <- suppressWarnings(as.numeric(clean[[col]]))
    }
}

# ── Add sample_id as explicit column ─────────────────────────────────────
clean <- cbind(sample_id = rownames(clean), clean)
rownames(clean) <- NULL

write.csv(clean, "clinical_metadata_clean.csv", row.names = FALSE, quote = TRUE)

cat("GEO_CLINICAL_METADATA complete\\n")
cat("  Samples :", nrow(clean), "\\n")
cat("  Columns :", paste(colnames(clean), collapse = ", "), "\\n")
REOF

        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            r-base: \$(R --version | head -1 | awk '{print \$3}')
            bioconductor-geoquery: "2.72.0 (mock)"
        END_VERSIONS
        """
    } else {
        """
        Rscript - <<'REOF'
raw <- read.csv("${sample_metadata_csv}", row.names = 1, stringsAsFactors = FALSE,
                check.names = FALSE)

# ── Canonical column renaming map ─────────────────────────────────────────
rename_map <- list(
    time  = c("overall_survival_months", "os_months", "survival_months",
               "days_to_last_followup",  "time",      "survival_time",
               "follow_up_months",       "months_to_event"),
    event = c("vital_status",  "os_event",    "event",
               "death_event",  "status",      "deceased",
               "overall_survival_status"),
    treatment = c("treatment_protocol_ch1", "treatment",    "drug",
                   "drug_treatment",         "condition",    "arm",
                   "intervention"),
    age   = c("age", "age_at_diagnosis", "age_years",
               "patient_age",   "age_at_enrollment"),
    sex   = c("Sex", "sex", "gender", "Gender",
               "biological_sex", "patient_sex")
)

clean <- raw

for (std_name in names(rename_map)) {
    candidates <- rename_map[[std_name]]
    matched    <- intersect(candidates, colnames(clean))
    if (length(matched) > 0 && !(std_name %in% colnames(clean))) {
        colnames(clean)[colnames(clean) == matched[1]] <- std_name
    }
}

# ── Standardise event coding ──────────────────────────────────────────────
if ("event" %in% colnames(clean)) {
    ev <- tolower(trimws(as.character(clean\$event)))
    clean\$event <- ifelse(
        ev %in% c("dead", "deceased", "1", "true", "yes", "died"), 1L,
        ifelse(ev %in% c("alive", "living", "0", "false", "no", "censored"), 0L,
               NA_integer_)
    )
}

# ── Standardise sex coding ────────────────────────────────────────────────
if ("sex" %in% colnames(clean)) {
    sx <- tolower(trimws(as.character(clean\$sex)))
    clean\$sex <- ifelse(sx %in% c("male", "m"), "male",
                  ifelse(sx %in% c("female", "f"), "female", sx))
}

# ── Coerce numeric columns ────────────────────────────────────────────────
for (col in c("time", "age")) {
    if (col %in% colnames(clean)) {
        clean[[col]] <- suppressWarnings(as.numeric(clean[[col]]))
    }
}

# ── Add sample_id as explicit column ─────────────────────────────────────
clean <- cbind(sample_id = rownames(clean), clean)
rownames(clean) <- NULL

write.csv(clean, "clinical_metadata_clean.csv", row.names = FALSE, quote = TRUE)

message("GEO_CLINICAL_METADATA complete")
message("  Samples : ", nrow(clean))
message("  Columns : ", paste(colnames(clean), collapse = ", "))
REOF

        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            r-base: \$(R --version | head -1 | awk '{print \$3}')
            bioconductor-geoquery: \$(Rscript -e 'cat(as.character(packageVersion("GEOquery")))')
        END_VERSIONS
        """
    }
}

// ─── ENTRY WORKFLOW ──────────────────────────────────────────────────────────

workflow GEO_DATA_CONNECTOR {

    take:
    ch_input   // channel: val(meta)  — meta must contain .accession (GSE/GSM ID)

    main:

    // Step 1: fetch series matrix and raw pData from GEO
    GEO_FETCH(ch_input)

    // Step 2: extract count/expression matrix + feature metadata
    GEO_COUNT_MATRIX(GEO_FETCH.out.series_matrix_rds)

    // Step 3: clean and standardise clinical metadata
    GEO_CLINICAL_METADATA(GEO_FETCH.out.sample_metadata)

    emit:
    count_matrix      = GEO_COUNT_MATRIX.out.count_matrix        // [meta, count_matrix.csv]
    clinical_metadata = GEO_CLINICAL_METADATA.out.clinical_metadata_clean // [meta, clinical_metadata_clean.csv]
    series_matrix     = GEO_FETCH.out.series_matrix_rds          // [meta, series_matrix.rds]
    feature_metadata  = GEO_COUNT_MATRIX.out.feature_metadata    // [meta, feature_metadata.csv]
    versions          = GEO_FETCH.out.versions.mix(
                            GEO_COUNT_MATRIX.out.versions,
                            GEO_CLINICAL_METADATA.out.versions
                        )
}

// ─── Standalone entry workflow ───────────────────────────────────────────────

workflow {
    // Build meta from CLI params
    def accession = params.accession ?: 'GSE999999'
    ch_input = Channel.of([id: accession, accession: accession])

    GEO_DATA_CONNECTOR(ch_input)

    GEO_DATA_CONNECTOR.out.count_matrix.view { meta, csv ->
        "Count matrix written: ${csv}"
    }
    GEO_DATA_CONNECTOR.out.clinical_metadata.view { meta, csv ->
        "Clinical metadata written: ${csv}"
    }
    GEO_DATA_CONNECTOR.out.series_matrix.view { meta, rds ->
        "Series matrix RDS: ${rds}"
    }
    GEO_DATA_CONNECTOR.out.feature_metadata.view { meta, csv ->
        "Feature metadata written: ${csv}"
    }
}
