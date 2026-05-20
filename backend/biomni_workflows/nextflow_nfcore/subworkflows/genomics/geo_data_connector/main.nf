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

// GEO accession: either a series (GSE…) or a sample (GSM…)
params.accession = 'GSE999999'

// Optional: path to a local GSE series matrix file (skips download when set)
params.local_series_matrix = null

// ─── PROCESS 1: GEO_FETCH ───────────────────────────────────────────────────

process GEO_FETCH {
    tag "${meta.id}"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}/geo_fetch" }, mode: 'copy'

    container 'quay.io/biocontainers/bioconductor-geoquery:2.72.0--r44_0'

    input:
    val(meta)   // meta map; meta.accession holds the GSE/GSM ID

    output:
    tuple val(meta), path("series_matrix.rds")   , emit: series_matrix_rds
    tuple val(meta), path("sample_metadata.csv") , emit: sample_metadata
    path "versions.yml"                           , emit: versions

    stub:
    """
    touch series_matrix.rds
    echo '"geo_accession","title","source_name_ch1","organism_ch1"' > sample_metadata.csv
    echo '"GSM1","Sample_1","tumor","Homo sapiens"' >> sample_metadata.csv
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        r-base: "4.4.0 (stub)"
        bioconductor-geoquery: "2.72.0 (stub)"
    END_VERSIONS
    """

    script:
    def accession = meta.accession ?: params.accession
    """
    Rscript - <<'REOF'
suppressPackageStartupMessages({
    library(GEOquery)
    library(Biobase)
})

accession <- "${accession}"

message("Fetching GEO accession: ", accession)

# Download -- handle both GSE and GSM prefixes
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

// ─── PROCESS 2: GEO_COUNT_MATRIX ────────────────────────────────────────────

process GEO_COUNT_MATRIX {
    tag "${meta.id}"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}/count_matrix" }, mode: 'copy'

    container 'quay.io/biocontainers/bioconductor-geoquery:2.72.0--r44_0'

    input:
    tuple val(meta), path(series_matrix_rds)

    output:
    tuple val(meta), path("count_matrix.csv")     , emit: count_matrix
    tuple val(meta), path("feature_metadata.csv") , emit: feature_metadata
    path "versions.yml"                            , emit: versions

    stub:
    """
    echo '"gene_id","GSM1","GSM2"' > count_matrix.csv
    echo '"GAPDH","100","120"' >> count_matrix.csv
    echo '"ID","Symbol"' > feature_metadata.csv
    echo '"GAPDH","GAPDH"' >> feature_metadata.csv
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        r-base: "4.4.0 (stub)"
        bioconductor-geoquery: "2.72.0 (stub)"
    END_VERSIONS
    """

    script:
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

# -- Extract expression matrix
if (is(geo_obj, "ExpressionSet")) {
    expr_mat  <- exprs(geo_obj)
    feat_data <- as.data.frame(fData(geo_obj))
} else if (is(geo_obj, "SummarizedExperiment")) {
    suppressPackageStartupMessages(library(SummarizedExperiment))
    expr_mat  <- assay(geo_obj)
    feat_data <- as.data.frame(rowData(geo_obj))
} else {
    # Fallback: try list slot \$exprs
    expr_mat  <- geo_obj\$exprs
    feat_data <- geo_obj\$featureData
    if (!is.data.frame(feat_data)) {
        feat_data <- data.frame(ID = rownames(expr_mat), row.names = rownames(expr_mat))
    }
}

if (is.null(expr_mat) || nrow(expr_mat) == 0) {
    stop("No expression matrix found in the RDS object.")
}

# -- count_matrix.csv
count_df <- as.data.frame(expr_mat)
count_df  <- cbind(gene_id = rownames(count_df), count_df)
rownames(count_df) <- NULL

write.csv(count_df, "count_matrix.csv", row.names = FALSE, quote = TRUE)

# -- feature_metadata.csv
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

// ─── PROCESS 3: GEO_CLINICAL_METADATA ───────────────────────────────────────

process GEO_CLINICAL_METADATA {
    tag "${meta.id}"
    label 'process_low'
    publishDir { "${params.outdir}/${meta.id}/clinical_metadata" }, mode: 'copy'

    container 'quay.io/biocontainers/bioconductor-geoquery:2.72.0--r44_0'

    input:
    tuple val(meta), path(sample_metadata_csv)

    output:
    tuple val(meta), path("clinical_metadata_clean.csv"), emit: clinical_metadata_clean
    path "versions.yml"                                  , emit: versions

    stub:
    """
    echo '"sample_id","time","event","treatment","age","sex"' > clinical_metadata_clean.csv
    echo '"GSM1","24","1","Drug_A_100nM","55","male"' >> clinical_metadata_clean.csv
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        r-base: "4.4.0 (stub)"
        bioconductor-geoquery: "2.72.0 (stub)"
    END_VERSIONS
    """

    script:
    """
    Rscript - <<'REOF'
raw <- read.csv("${sample_metadata_csv}", row.names = 1, stringsAsFactors = FALSE,
                check.names = FALSE)

# -- Canonical column renaming map
# Maps GEO free-text column variants to standardised names used by survival /
# DE tools downstream.
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

# -- Standardise event coding
if ("event" %in% colnames(clean)) {
    ev <- tolower(trimws(as.character(clean\$event)))
    clean\$event <- ifelse(
        ev %in% c("dead", "deceased", "1", "true", "yes", "died"), 1L,
        ifelse(ev %in% c("alive", "living", "0", "false", "no", "censored"), 0L,
               NA_integer_)
    )
}

# -- Standardise sex coding
if ("sex" %in% colnames(clean)) {
    sx <- tolower(trimws(as.character(clean\$sex)))
    clean\$sex <- ifelse(sx %in% c("male", "m"), "male",
                  ifelse(sx %in% c("female", "f"), "female", sx))
}

# -- Coerce numeric columns
for (col in c("time", "age")) {
    if (col %in% colnames(clean)) {
        clean[[col]] <- suppressWarnings(as.numeric(clean[[col]]))
    }
}

# -- Add sample_id as explicit column
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
