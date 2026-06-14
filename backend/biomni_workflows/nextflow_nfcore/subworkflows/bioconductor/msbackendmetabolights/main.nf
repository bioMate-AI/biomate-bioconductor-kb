#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MsBackendMetaboLights
// MetaboLights is one of the main public repositories for storage of metabolomics experiments, which i
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MsBackendMetaboLights/inst/doc/MsBackendMetaboLights.R
// Upstream  : BiocStyle, Spectra
// Downstream: none
//
// Install: BiocManager::install("MsBackendMetaboLights")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSBACKENDMETABOLIGHTS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-msbackendmetabolights"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_msbackendmetabolights_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_msbackendmetabolights_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_msbackendmetabolights_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("MsBackendMetaboLights", "Spectra", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(MsBackendMetaboLights)
    library(Spectra)
    library(jsonlite)

    # --- Query MetaboLights Repository [] ---
    # Key functions: mtbls_list_files, mtbls_ftp_path
    all_files <- mtbls_list_files("MTBLS39")
    ftp_url <- mtbls_ftp_path("MTBLS39")
    assay_files <- grep("^a_", all_files, value = TRUE)
    assay_data <- read.table(
        file = paste0(ftp_url, assay_files[1]),
        sep = "\t",
        header = TRUE,
        check.names = FALSE
    )

    # --- Initialize Spectra Backend [] ---
    # Key functions: MsBackendMetaboLights, Spectra
    be <- MsBackendMetaboLights()
    s <- Spectra(
        "MTBLS39",
        filePattern = "63A.cdf",
        source = be
    )

    # --- Extract Spectra Metadata [] ---
    # Key functions: spectraVariables, spectraData
    vars <- spectraVariables(s)
    meta <- spectraData(
        s,
        columns = c(
            "mtbls_id", 
            "mtbls_assay_name", 
            "derived_spectral_data_file"
        )
    )

    # --- Synchronize and Cache Data [] ---
    # Key functions: mtbls_sync, mtbls_sync_data_files, mtbls_cached_data_files
    synced_be <- mtbls_sync(s@backend)
    res <- mtbls_sync_data_files("MTBLS39", fileName = "AM063A.cdf")
    cached_files <- mtbls_cached_data_files()


    # --- Save outputs ---
    .objs <- setdiff(ls(), c("args", "prefix", ".objs"))
    .cells <- function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                            if (is.data.frame(x) || is.matrix(x)) prod(dim(x)) else -1 }
    .dfs  <- Filter(function(v) is.data.frame(tryCatch(get(v), error = function(e) NULL)), .objs)
    .tabs <- Filter(function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                                  is.data.frame(x) || is.matrix(x) }, .objs)
    .cand <- if (length(.dfs) > 0) .dfs else .tabs
    if (length(.cand) > 0) {
        .main <- get(.cand[[ which.max(sapply(.cand, .cells)) ]])
        write.csv(as.data.frame(.main), "${prefix}_msbackendmetabolights_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_msbackendmetabolights_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_msbackendmetabolights_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSBACKENDMETABOLIGHTS:", paste0("    msbackendmetabolights: ", as.character(packageVersion("MsBackendMetaboLights")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msbackendmetabolights_results.csv
    touch ${prefix}_msbackendmetabolights_output.rds
    echo "BIOC_MSBACKENDMETABOLIGHTS:" > versions.yml
    echo "    msbackendmetabolights: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSBACKENDMETABOLIGHTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MSBACKENDMETABOLIGHTS(ch_input)

    emit:
    results  = BIOC_MSBACKENDMETABOLIGHTS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSBACKENDMETABOLIGHTS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSBACKENDMETABOLIGHTS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSBACKENDMETABOLIGHTS.out.versions  // channel: path(versions.yml)
}
