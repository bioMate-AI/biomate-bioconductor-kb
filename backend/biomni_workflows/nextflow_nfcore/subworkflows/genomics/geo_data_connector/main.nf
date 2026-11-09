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
// Required for a real run.  Do not provide a plausible-looking fallback here:
// it used to make an accession-only card appear runnable while silently fetching
// the placeholder GSE999999 rather than the accession the researcher supplied.
params.accession = null

// Optional: path to a local GSE series matrix file (skips download when set)
params.local_series_matrix = null

// A GSE can contain more than one platform/ExpressionSet.  Selecting the first
// one is scientifically unsafe: different platforms can have different sample
// sets and feature annotations.  Leave null for single-platform series; for a
// multi-platform series pass one of the GEO platform IDs (for example GPL570).
params.platform_id = null

// ─── PROCESS 1: GEO_FETCH ───────────────────────────────────────────────────

// [Data Retrieval]
process GEO_FETCH {
    tag "${meta.id}"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}/geo_fetch" }, mode: 'copy'

    container 'quay.io/biocontainers/bioconductor-geoquery:2.74.0--r44hdfd78af_0'

    input:
    val(meta)   // meta map; meta.accession holds the GSE/GSM ID

    output:
    tuple val(meta), path("series_matrix.rds")   , emit: series_matrix_rds
    tuple val(meta), path("sample_metadata.csv") , emit: sample_metadata
    tuple val(meta), path("geo_metadata.json")   , emit: geo_metadata
    path "versions.yml"                           , emit: versions

    stub:
    """
    touch series_matrix.rds
    echo '"geo_accession","title","source_name_ch1","organism_ch1"' > sample_metadata.csv
    echo '"GSM1","Sample_1","tumor","Homo sapiens"' >> sample_metadata.csv
    cat <<-END_METADATA > geo_metadata.json
    {"source":"stub","accession":"${meta.accession}","platform_id":"GPL_STUB","platform_count":1}
    END_METADATA
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        r-base: "4.4.0 (stub)"
        bioconductor-geoquery: "2.72.0 (stub)"
END_VERSIONS
    """

    script:
    def accession = meta.accession ?: params.accession
    def platformId = meta.platform_id ?: params.platform_id
    """
    Rscript - <<'REOF'
suppressPackageStartupMessages({
    library(GEOquery)
    library(Biobase)
})

accession <- "${accession}"
requested_platform <- "${platformId ?: ''}"

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

# getGEO() returns one ExpressionSet per platform.  Never silently take the
# first when the series has several platforms: the researcher must select the
# platform after reviewing the available IDs.
if (is.list(geo_data) && !is(geo_data, "ExpressionSet")) {
    available_platforms <- names(geo_data)
    if (is.null(available_platforms) || any(!nzchar(available_platforms))) {
        available_platforms <- paste0("platform_", seq_along(geo_data))
        names(geo_data) <- available_platforms
    }
    if (length(geo_data) > 1 && !nzchar(requested_platform)) {
        stop(
            "GEO series contains multiple platforms (",
            paste(available_platforms, collapse = ", "),
            "). Re-run with --platform_id set to one of these IDs; no platform was selected automatically."
        )
    }
    if (nzchar(requested_platform)) {
        if (!(requested_platform %in% available_platforms)) {
            stop(
                "Requested platform_id '", requested_platform,
                "' is not available. Available platforms: ",
                paste(available_platforms, collapse = ", ")
            )
        }
        selected_platform <- requested_platform
    } else {
        selected_platform <- available_platforms[[1]]
    }
    geo_obj <- geo_data[[selected_platform]]
    platform_count <- length(geo_data)
} else {
    geo_obj <- geo_data
    selected_platform <- requested_platform
    platform_count <- 1L
}

saveRDS(geo_obj, "series_matrix.rds")

# Export pData (sample phenotype metadata)
pd <- pData(geo_obj)
write.csv(pd, "sample_metadata.csv", row.names = TRUE, quote = TRUE)

writeLines(c(
    "{",
    '  "source": "geoquery",',
    sprintf('  "accession": "%s",', accession),
    sprintf('  "platform_id": "%s",', selected_platform),
    sprintf('  "platform_count": %d,', platform_count),
    sprintf('  "sample_count": %d', nrow(pd)),
    "}"
), "geo_metadata.json")

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

// ─── PROCESS 1B: GEO_LOAD_LOCAL ─────────────────────────────────────────────

// A local GEO series-matrix file is an advertised alternative to remote fetch.
// Preserve the exact same outputs as GEO_FETCH so downstream workflow wiring is
// identical.  Supports either an RDS object previously emitted by this workflow
// or a downloaded GEO SOFT/series-matrix file that GEOquery can parse.
process GEO_LOAD_LOCAL {
    tag "${meta.id} (local series matrix)"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}/geo_fetch" }, mode: 'copy'

    container 'quay.io/biocontainers/bioconductor-geoquery:2.74.0--r44hdfd78af_0'

    input:
    tuple val(meta), path(local_series_matrix)

    output:
    tuple val(meta), path("series_matrix.rds")   , emit: series_matrix_rds
    tuple val(meta), path("sample_metadata.csv") , emit: sample_metadata
    tuple val(meta), path("geo_metadata.json")   , emit: geo_metadata
    path "versions.yml"                           , emit: versions

    stub:
    """
    touch series_matrix.rds
    echo '"geo_accession","title","source_name_ch1","organism_ch1"' > sample_metadata.csv
    echo '"GSM1","Sample_1","local_stub","Homo sapiens"' >> sample_metadata.csv
    cat <<-END_METADATA > geo_metadata.json
    {"source":"local_series_matrix_stub","accession":"${meta.accession ?: ''}","platform_id":"GPL_STUB","platform_count":1}
    END_METADATA
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        r-base: "4.4.0 (stub)"
        bioconductor-geoquery: "2.72.0 (stub)"
END_VERSIONS
    """

    script:
    def platformId = meta.platform_id ?: params.platform_id
    """
    Rscript - <<'REOF'
suppressPackageStartupMessages({
    library(GEOquery)
    library(Biobase)
})

source_path <- "${local_series_matrix}"
requested_platform <- "${platformId ?: ''}"
local_accession <- "${meta.accession ?: ''}"

if (tolower(tools::file_ext(source_path)) == "rds") {
    geo_data <- readRDS(source_path)
} else {
    geo_data <- getGEO(
        filename = source_path,
        GSEMatrix = TRUE,
        getGPL = FALSE,
        AnnotGPL = FALSE
    )
}

if (is.list(geo_data) && !is(geo_data, "ExpressionSet")) {
    available_platforms <- names(geo_data)
    if (is.null(available_platforms) || any(!nzchar(available_platforms))) {
        available_platforms <- paste0("platform_", seq_along(geo_data))
        names(geo_data) <- available_platforms
    }
    if (length(geo_data) > 1 && !nzchar(requested_platform)) {
        stop(
            "Local GEO series matrix contains multiple platforms (",
            paste(available_platforms, collapse = ", "),
            "). Re-run with --platform_id set to one of these IDs; no platform was selected automatically."
        )
    }
    if (nzchar(requested_platform)) {
        if (!(requested_platform %in% available_platforms)) {
            stop(
                "Requested platform_id '", requested_platform,
                "' is not available. Available platforms: ",
                paste(available_platforms, collapse = ", ")
            )
        }
        selected_platform <- requested_platform
    } else {
        selected_platform <- available_platforms[[1]]
    }
    geo_obj <- geo_data[[selected_platform]]
    platform_count <- length(geo_data)
} else {
    geo_obj <- geo_data
    selected_platform <- requested_platform
    platform_count <- 1L
}

if (!is(geo_obj, "ExpressionSet")) {
    stop("Local input did not resolve to a GEO ExpressionSet. Supply an RDS emitted by this connector or a GEO series-matrix/SOFT file.")
}

saveRDS(geo_obj, "series_matrix.rds")
pd <- pData(geo_obj)
write.csv(pd, "sample_metadata.csv", row.names = TRUE, quote = TRUE)
writeLines(c(
    "{",
    '  "source": "local_series_matrix",',
    sprintf('  "accession": "%s",', local_accession),
    sprintf('  "platform_id": "%s",', selected_platform),
    sprintf('  "platform_count": %d,', platform_count),
    sprintf('  "sample_count": %d', nrow(pd)),
    "}"
), "geo_metadata.json")
REOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        r-base: \$(R --version | head -1 | awk '{print \$3}')
        bioconductor-geoquery: \$(Rscript -e 'cat(as.character(packageVersion("GEOquery")))')
END_VERSIONS
    """
}

// ─── PROCESS 2: GEO_COUNT_MATRIX ────────────────────────────────────────────

// [Analysis]
process GEO_COUNT_MATRIX {
    tag "${meta.id}"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}/count_matrix" }, mode: 'copy'

    container 'quay.io/biocontainers/bioconductor-geoquery:2.74.0--r44hdfd78af_0'

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

// [Analysis]
process GEO_CLINICAL_METADATA {
    tag "${meta.id}"
    label 'process_low'
    publishDir { "${params.outdir}/${meta.id}/clinical_metadata" }, mode: 'copy'

    container 'quay.io/biocontainers/bioconductor-geoquery:2.74.0--r44hdfd78af_0'

    input:
    tuple val(meta), path(sample_metadata_csv)

    output:
    // This is the downstream contract used by differentialabundance: a
    // sample-metadata table whose sample IDs correspond to matrix columns.
    // Keep the canonical filename rather than exporting a private
    // "clinical_metadata_clean" name that chain wiring cannot consume.
    tuple val(meta), path("sample_metadata.csv"), emit: sample_metadata
    path "versions.yml"                                  , emit: versions

    stub:
    """
    echo '"sample_id","time","event","treatment","age","sex"' > sample_metadata.csv
    echo '"GSM1","24","1","Drug_A_100nM","55","male"' >> sample_metadata.csv
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

write.csv(clean, "sample_metadata.csv", row.names = FALSE, quote = TRUE)

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

    // Step 1: fetch series matrix and raw pData from GEO, or materialize the
    // explicitly supplied local series-matrix file.  Both branches emit the
    // same tuple contract for the analysis steps below.
    if (params.local_series_matrix) {
        ch_local_input = ch_input.map { meta -> tuple(meta, file(params.local_series_matrix, checkIfExists: true)) }
        GEO_LOAD_LOCAL(ch_local_input)
        ch_series_matrix = GEO_LOAD_LOCAL.out.series_matrix_rds
        ch_sample_metadata = GEO_LOAD_LOCAL.out.sample_metadata
        ch_geo_metadata = GEO_LOAD_LOCAL.out.geo_metadata
        ch_fetch_versions = GEO_LOAD_LOCAL.out.versions
    } else {
        GEO_FETCH(ch_input)
        ch_series_matrix = GEO_FETCH.out.series_matrix_rds
        ch_sample_metadata = GEO_FETCH.out.sample_metadata
        ch_geo_metadata = GEO_FETCH.out.geo_metadata
        ch_fetch_versions = GEO_FETCH.out.versions
    }

    // Step 2: extract count/expression matrix + feature metadata
    GEO_COUNT_MATRIX(ch_series_matrix)

    // Step 3: clean and standardise clinical metadata
    GEO_CLINICAL_METADATA(ch_sample_metadata)

    emit:
    count_matrix      = GEO_COUNT_MATRIX.out.count_matrix        // [meta, count_matrix.csv]
    sample_metadata   = GEO_CLINICAL_METADATA.out.sample_metadata // [meta, sample_metadata.csv]
    series_matrix     = ch_series_matrix                          // [meta, series_matrix.rds]
    feature_metadata  = GEO_COUNT_MATRIX.out.feature_metadata    // [meta, feature_metadata.csv]
    geo_metadata      = ch_geo_metadata                           // [meta, geo_metadata.json]
    versions          = ch_fetch_versions.mix(
                            GEO_COUNT_MATRIX.out.versions,
                            GEO_CLINICAL_METADATA.out.versions
                        )
}

// ─── Standalone entry workflow ───────────────────────────────────────────────

workflow {
    // Build meta from CLI params
    if (!params.accession && !params.local_series_matrix) {
        error "Provide --accession (for example, GSE12345) or --local_series_matrix; no placeholder accession is used."
    }
    def accession = params.accession ?: null
    def id = accession ?: "local_series_matrix"
    ch_input = Channel.of([id: id, accession: accession, platform_id: params.platform_id])

    GEO_DATA_CONNECTOR(ch_input)

    GEO_DATA_CONNECTOR.out.count_matrix.view { meta, csv ->
        "Count matrix written: ${csv}"
    }
    GEO_DATA_CONNECTOR.out.sample_metadata.view { meta, csv ->
        "Sample metadata written: ${csv}"
    }
    GEO_DATA_CONNECTOR.out.series_matrix.view { meta, rds ->
        "Series matrix RDS: ${rds}"
    }
    GEO_DATA_CONNECTOR.out.feature_metadata.view { meta, csv ->
        "Feature metadata written: ${csv}"
    }
    GEO_DATA_CONNECTOR.out.geo_metadata.view { meta, json ->
        "GEO retrieval metadata written: ${json}"
    }
}
