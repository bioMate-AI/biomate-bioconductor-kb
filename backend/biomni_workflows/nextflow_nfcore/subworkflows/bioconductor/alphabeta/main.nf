#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: AlphaBeta
// AlphaBeta is a computational method for estimating epimutation rates and spectra from high-throughpu
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/AlphaBeta/inst/doc/AlphaBeta.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("AlphaBeta")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ALPHABETA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-alphabeta"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-alphabeta:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-alphabeta:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_alphabeta_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_alphabeta_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_alphabeta_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AlphaBeta)
    library(ABneutral)
    library(jsonlite)

    # --- Selection Model Estimation [] ---
    # Key functions: ABselectMM, ABselectUU
    rFile <- system.file("extdata/dm", "output.rds", package = "AlphaBeta")
    output <- readRDS(rFile)
    pedigree <- output$Pdata
    p0uu_in <- output$tmpp0
    output.data.dir <- tempdir()
    selectMM_out <- ABselectMM(
        pedigree.data = pedigree,
        p0uu = p0uu_in,
        eqp = p0uu_in,
        eqp.weight = 1,
        Nstarts = 2,
        out.dir = output.data.dir,
        out.name = "ABselectMM_estimates"
    )


    # --- Null Model Estimation [] ---
    # Key functions: ABnull
    rFile <- system.file("extdata/dm", "output.rds", package = "AlphaBeta")
    output <- readRDS(rFile)
    pedigree <- output$Pdata
    output.data.dir <- tempdir()
    null_out <- ABnull(
        pedigree.data = pedigree,
        out.dir = output.data.dir,
        out.name = "ABnull_estimates"
    )


    # --- Model Comparison [] ---
    # Key functions: FtestRSS
    file1 <- system.file(
        "extdata/models/",
        "ABneutral_CG_global_estimates.Rdata",
        package = "AlphaBeta"
    )
    file2 <- system.file(
        "extdata/models/",
        "ABnull_CG_global_estimates.Rdata",
        package = "AlphaBeta"
    )
    comparison <- FtestRSS(
        pedigree.select = file1,
        pedigree.null = file2
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_alphabeta_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_alphabeta_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_alphabeta_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ALPHABETA:", paste0("    alphabeta: ", packageVersion("AlphaBeta"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_alphabeta_results.csv
    touch ${prefix}_alphabeta_output.rds
    echo "BIOC_ALPHABETA:" > versions.yml
    echo "    alphabeta: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ALPHABETA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ALPHABETA(ch_input)

    emit:
    results  = BIOC_ALPHABETA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ALPHABETA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ALPHABETA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ALPHABETA.out.versions  // channel: path(versions.yml)
}
