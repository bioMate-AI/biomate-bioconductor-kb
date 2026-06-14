#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PhIPData
// PhIPData defines an S4 class for phage-immunoprecipitation sequencing (PhIP-seq) experiments. Bulidi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PhIPData/inst/doc/PhIPData.R
// Upstream  : none
// Downstream: beer
//
// Install: BiocManager::install("PhIPData")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_PHIPDATA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-phipdata"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_phipdata_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_phipdata_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_phipdata_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("PhIPData", "jsonlite", "SummarizedExperiment")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
        library(SummarizedExperiment)
}
    library(PhIPData)
    library(jsonlite)

    # --- Phipdata [] ---
    # Key functions: PhIPData
    ---------------------------------------------------------------------
    phip_obj <- PhIPData(counts_dat, logfc_dat, prob_dat,
                         virscan_info, sample_meta,
                         exp_meta)
    phip_obj
    # --- Assays [] ---
    # Key functions: assays
    ---------------------------------------------------------------------
    assays(phip_obj)
    head(assays(phip_obj)\$counts)   # Returns the same as assays(phip_obj)[["counts"]]
    # --- Head [] ---
    # Key functions: assay
    ---------------------------------------------------------------------
    head(assay(phip_obj, "logfc"))   # Returns the same as assay(phip_obj, 2)
    # --- Head [] ---
    # Key functions: counts, logfc, prob
    ---------------------------------------------------------------------
    head(counts(phip_obj))
    head(logfc(phip_obj))
    head(prob(phip_obj))
    # --- Peptideinfo [] ---
    # Key functions: peptideInfo
    ---------------------------------------------------------------------
    # Only showing 2 columns for easier viewing
    peptideInfo(phip_obj)[, 8:9]
    # --- Sampleinfo [] ---
    # Key functions: sampleInfo
    ---------------------------------------------------------------------
    sampleInfo(phip_obj)
    # --- Metadata [] ---
    # Key functions: metadata
    ---------------------------------------------------------------------
    metadata(phip_obj)
    # --- Subset [] ---
    # Key functions: peptideInfo
    ---------------------------------------------------------------------
    ebv_sub <- subset(phip_obj, grepl("Epstein-Barr virus", species))
    peptideInfo(ebv_sub)[, "species"]
    # --- Subsetbeads [] ---
    # Key functions: subsetBeads
    ---------------------------------------------------------------------
    subsetBeads(phip_obj)
    # --- Librarysize [] ---
    # Key functions: librarySize
    ---------------------------------------------------------------------
    librarySize(phip_obj)
    # --- Head [] ---
    # Key functions: propReads
    ---------------------------------------------------------------------
    head(propReads(phip_obj))
    # --- Makelibrary [] ---
    # Key functions: makeLibrary
    ---------------------------------------------------------------------
    # Save virscan_info as the human_virus library
    makeLibrary(virscan_info, "human_virus")
    # --- Phipdata [] ---
    # Key functions: PhIPData, getLibrary
    ---------------------------------------------------------------------
    PhIPData(counts = counts_dat,
             sampleInfo = sample_meta,
             peptideInfo = getLibrary("human_virus"))
    # --- Removelibrary [] ---
    # Key functions: removeLibrary
    ---------------------------------------------------------------------
    removeLibrary("human_virus")

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
        write.csv(as.data.frame(.main), "${prefix}_phipdata_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_phipdata_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_phipdata_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_PHIPDATA:", paste0("    phipdata: ", as.character(packageVersion("PhIPData")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_phipdata_results.csv
    touch ${prefix}_phipdata_output.rds
    echo "BIOC_PHIPDATA:" > versions.yml
    echo "    phipdata: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PHIPDATA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PHIPDATA(ch_input)

    emit:
    results  = BIOC_PHIPDATA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PHIPDATA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PHIPDATA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PHIPDATA.out.versions  // channel: path(versions.yml)
}
