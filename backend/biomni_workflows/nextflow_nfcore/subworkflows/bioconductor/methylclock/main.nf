#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: methylclock
// This package allows to estimate chronological and gestational DNA methylation (DNAm) age as well as 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/methylclock/inst/doc/methylclock.R
// Upstream  : methylclockData, Biobase, tibble, impute, ggplot2
// Downstream: none
//
// Install: BiocManager::install("methylclock")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METHYLCLOCK {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-methylclock"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-methylclock:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-methylclock:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_methylclock_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_methylclock_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_methylclock_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(methylclock)
    library(jsonlite)

    # --- DNA Methylation Age Estimation [] ---
    # Key functions: DNAmAge
    age_est <- methylclock::DNAmAge(
        MethylationData,
        clocks = c("Horvath", "BNN"),
        min.perc = 0.25
    )


    # --- Gestational Age Estimation [] ---
    # Key functions: DNAmGA
    ga_est <- methylclock::DNAmGA(
        progress_data,
        age = progress_vars$EGA,
        cell.count = FALSE
    )


    # --- Visualization of Epigenetic Clocks [] ---
    # Key functions: plotDNAmAge, plotCorClocks
    methylclock::plotDNAmAge(
        ga_est$Knight,
        progress_vars$EGA,
        tit = "GA Knight's method",
        clock = "GA"
    )
    methylclock::plotCorClocks(age_gse58045)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_methylclock_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_methylclock_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_methylclock_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METHYLCLOCK:", paste0("    methylclock: ", packageVersion("methylclock"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methylclock_results.csv
    touch ${prefix}_methylclock_output.rds
    echo "BIOC_METHYLCLOCK:" > versions.yml
    echo "    methylclock: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METHYLCLOCK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METHYLCLOCK(ch_input)

    emit:
    results  = BIOC_METHYLCLOCK.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METHYLCLOCK.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METHYLCLOCK.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METHYLCLOCK.out.versions  // channel: path(versions.yml)
}
