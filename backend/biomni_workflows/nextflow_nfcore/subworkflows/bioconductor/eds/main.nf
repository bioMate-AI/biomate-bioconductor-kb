#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: eds
// This packages provides a single function, readEDS. This is a low-level utility for reading in Alevin
//
// Source : https://bioconductor.org/packages/3.20/bioc/https://bioconductor.org/packages/3.20/bioc/vignettes/eds/inst/doc/eds.html
// Upstream  : tximportData
// Downstream: none
//
// Install: BiocManager::install("eds")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EDS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-eds"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-eds:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-eds:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_eds_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_eds_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_eds_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(eds)
    library(jsonlite)

    # --- Code Block 2 [] ---
    # Key functions: files, path
    dir0 <- system.file("extdata",package="tximportData")
    samps <- list.files(file.path(dir0, "alevin"))
    dir <- file.path(dir0,"alevin",samps[3],"alevin")
    quant.mat.file <- file.path(dir, "quants_mat.gz")
    barcode.file <- file.path(dir, "quants_mat_rows.txt")
    # --- Code Block 4 [] ---
    # Key functions: readEDS
    mat <- readEDS(
        numOfGenes=num.genes,
        numOfOriginalCells=num.cells,
        countMatFilename=quant.mat.file)
    # --- Code Block 5 [] ---
    # Key functions: 1, namespace
    ## R version 4.4.1 (2024-06-14)
    ## Platform: x86_64-pc-linux-gnu
    ## Running under: Ubuntu 24.04.1 LTS
    ##
    ## Matrix products: default

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_eds_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_eds_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_eds_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EDS:", paste0("    eds: ", packageVersion("eds"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_eds_results.csv
    touch ${prefix}_eds_output.rds
    echo "BIOC_EDS:" > versions.yml
    echo "    eds: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EDS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EDS(ch_input)

    emit:
    results  = BIOC_EDS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EDS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EDS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EDS.out.versions  // channel: path(versions.yml)
}
