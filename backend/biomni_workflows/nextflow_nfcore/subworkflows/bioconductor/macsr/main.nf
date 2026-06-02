#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MACSr
// The Model-based Analysis of ChIP-Seq (MACS) is a widely used toolkit for identifying transcript fact
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MACSr/inst/doc/MACSr.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MACSr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MACSR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-macsr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-macsr:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-macsr:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_macsr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_macsr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_macsr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MACSr)
    library(ExperimentHub)
    library(jsonlite)

    # --- Broad Peak Calling [] ---
    # Key functions: callpeak
    cp_broad <- MACSr::callpeak(
        tfile = CHIP,
        cfile = CTRL,
        gsize = 5.2e7,
        store_bdg = TRUE,
        name = "broad_peaks",
        outdir = tempdir(),
        broad = TRUE
    )
    broad_files <- cp_broad$outputs
    broad_args <- cp_broad$arguments


    # --- Cutoff Analysis [] ---
    # Key functions: callpeak
    cp_cutoff <- MACSr::callpeak(
        tfile = CHIP,
        cfile = CTRL,
        gsize = 5.2e7,
        store_bdg = TRUE,
        name = "cutoff_analysis",
        outdir = tempdir(),
        cutoff_analysis = TRUE
    )
    cutoff_log <- cp_cutoff$log


    # --- Fragment Size Prediction [] ---
    # Key functions: predictd
    pred_d <- MACSr::predictd(
        ifile = CHIP,
        gsize = 5.2e7,
        dmin = 80,
        dmax = 250,
        outdir = tempdir()
    )
    pred_log <- pred_d$log

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_macsr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_macsr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_macsr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MACSR:", paste0("    macsr: ", packageVersion("MACSr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_macsr_results.csv
    touch ${prefix}_macsr_output.rds
    echo "BIOC_MACSR:" > versions.yml
    echo "    macsr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MACSR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MACSR(ch_input)

    emit:
    results  = BIOC_MACSR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MACSR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MACSR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MACSR.out.versions  // channel: path(versions.yml)
}
