#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RgnTX
// RgnTX allows the integration of transcriptome annotations so as to model the complex alternative spl
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RgnTX/inst/doc/RgnTX.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("RgnTX")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RGNTX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rgntx"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rgntx:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rgntx:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rgntx_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rgntx_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rgntx_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RgnTX)
    library(jsonlite)

    # --- Fig7 [] ---
    # Key functions: plotPermResults
    p1 <- plotPermResults(permTestTx_results, binwidth = 1)
    # --- Fig9 [] ---
    # Key functions: plotPermResults
    file <- system.file(package="RgnTX", "extdata", "permTestTx_results3.rds")
    permTestTx_results <- readRDS(file)
    p1 <- plotPermResults(permTestTx_results, binwidth = 1)
    # --- Fig10 [] ---
    # Key functions: plotPermResults
    file <- system.file(package="RgnTX", "extdata", "permTestTx_results.rds")
    permTestTx_results <- readRDS(file)
    p_a <- plotPermResults(permTestTx_results, binwidth = 1)
    # --- Fig12 [] ---
    # Key functions: permTestTx_customAll, plotPermResults
    permTestTx_results <- permTestTx_customAll(RSL = RSL, RS1 = RS1, RS2 = RS2)
    p_3 <- plotPermResults(permTestTx_results)
    # --- Fig14 [] ---
    # Key functions: plotShiftedZScoreTx
    file <- system.file(package="RgnTX", "extdata", "shiftedZScoreTx_results1.rds")
    shiftedZScoreTx_results <- readRDS(file)
    p1 <- plotShiftedZScoreTx(shiftedZScoreTx_results)
    # --- Fig15 [] ---
    # Key functions: plotShiftedZScoreTx
    file <- system.file(package="RgnTX", "extdata", "shiftedZScoreTx_results2.rds")
    shiftedZScoreTx_results <- readRDS(file)
    p2 <- plotShiftedZScoreTx(shiftedZScoreTx_results)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rgntx_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rgntx_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rgntx_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RGNTX:", paste0("    rgntx: ", packageVersion("RgnTX"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rgntx_results.csv
    touch ${prefix}_rgntx_output.rds
    echo "BIOC_RGNTX:" > versions.yml
    echo "    rgntx: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RGNTX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RGNTX(ch_input)

    emit:
    results  = BIOC_RGNTX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RGNTX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RGNTX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RGNTX.out.versions  // channel: path(versions.yml)
}
