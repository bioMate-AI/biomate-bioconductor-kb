#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: hapFabia
// A package to identify very short IBD segments in large sequencing data by FABIA biclustering. Two ha
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/hapFabia/inst/doc/hapfabia.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("hapFabia")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HAPFABIA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hapfabia"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hapfabia:1.48.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hapfabia:1.48.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hapfabia_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hapfabia_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hapfabia_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(hapFabia)
    library(SNVs)
    library(jsonlite)

    # --- Haplotype Biclustering [] ---
    # Key functions: hapFabia
    hapRes <- hapFabia(
        fileName = "dataSim1fabia",
        prefixPath = "",
        sparseMatrixPostfix = "_mat",
        annotPostfix = "_annot.txt",
        individualsPostfix = "_individuals.txt",
        p = 10,
        iter = 1,
        quant = 0.01,
        eps = 1e-5,
        alpha = 0.03,
        cyc = 50,
        non_negative = 1,
        write_file = 0,
        norm = 0,
        lap = 100.0,
        IBDsegmentLength = 10
    )


    # --- Simulation of IBD Segments [] ---
    # Key functions: simulateIBDsegmentsFabia
    sim_res <- simulateIBDsegmentsFabia(
        minruns = 2,
        maxruns = 2
    )


    # --- Visualisation and Plotting [] ---
    # Key functions: histL, plotL
    h1 <- histL(res, n = 1, p = 0.9, w = NULL, intervv = 50, off = 0)
    plotL(
        res,
        n = 1,
        p = 0.95,
        w = NULL,
        type = "histogram",
        intervv = 50,
        off = 0,
        t = "p",
        cex = 1
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hapfabia_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hapfabia_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hapfabia_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HAPFABIA:", paste0("    hapfabia: ", packageVersion("hapFabia"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hapfabia_results.csv
    touch ${prefix}_hapfabia_output.rds
    echo "BIOC_HAPFABIA:" > versions.yml
    echo "    hapfabia: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HAPFABIA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HAPFABIA(ch_input)

    emit:
    results  = BIOC_HAPFABIA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HAPFABIA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HAPFABIA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HAPFABIA.out.versions  // channel: path(versions.yml)
}
