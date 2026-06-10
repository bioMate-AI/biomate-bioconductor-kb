#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HoloFoodR
// Utility package to facilitate integration and analysis of EBI HoloFood data in R. This package strea
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HoloFoodR/inst/doc/HoloFoodR.R
// Upstream  : MGnifyR, knitr
// Downstream: none
//
// Install: BiocManager::install("HoloFoodR")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_HOLOFOODR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-holofoodr"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_holofoodr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_holofoodr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_holofoodr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(HoloFoodR)
    library(MgnifyClient)
    library(jsonlite)

    # --- Querying Database ---
    # Key functions: doQuery
    animals <- doQuery(
        resource = "animals",
        max.hits = 100
    )
    histological_animals <- animals[animals[["histological"]] == TRUE, ]
    animal_accessions <- histological_animals[["accession"]]

    # --- Retrieving Animal Metadata ---
    # Key functions: getData
    animal_details <- getData(
        accession.type = "animals",
        accession = animal_accessions[1:10]
    )
    samples_df <- animal_details[["samples"]]
    sample_accessions <- unique(samples_df[["accession"]])

    # --- Fetching Multi-Omic Results ---
    # Key functions: getResult
    mae_results <- getResult(
        accessions = sample_accessions[1:5]
    )
    experiment_names <- names(mae_results)

    # --- Extracting Metagenomic Assays ---
    # Key functions: getResult
    metagenomic_mae <- getResult(
        accessions = sample_accessions[1:3]
    )
    primary_assay <- metagenomic_mae[[1]]


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
        write.csv(as.data.frame(.main), "${prefix}_holofoodr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_holofoodr_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_holofoodr_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_HOLOFOODR:", paste0("    holofoodr: ", as.character(packageVersion("HoloFoodR")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_holofoodr_results.csv
    touch ${prefix}_holofoodr_output.rds
    echo "BIOC_HOLOFOODR:" > versions.yml
    echo "    holofoodr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HOLOFOODR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HOLOFOODR(ch_input)

    emit:
    results  = BIOC_HOLOFOODR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HOLOFOODR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HOLOFOODR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HOLOFOODR.out.versions  // channel: path(versions.yml)
}
