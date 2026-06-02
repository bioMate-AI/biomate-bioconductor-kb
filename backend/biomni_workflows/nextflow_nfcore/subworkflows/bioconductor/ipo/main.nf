#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: IPO
// The outcome of XCMS data processing strongly depends on the parameter settings. IPO (`Isotopologue P
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/IPO/inst/doc/IPO.R
// Upstream  : faahKO
// Downstream: none
//
// Install: BiocManager::install("IPO")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_IPO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ipo"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ipo:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ipo:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ipo_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ipo_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ipo_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(IPO)
    library(jsonlite)

    # --- Retention Time Correction and Grouping Optimization [] ---
    # Key functions: getDefaultRetGroupStartingParams, optimizeRetGroup
    optimizedXcmsSetObject <- resultPeakpicking$best_settings$xset
    retcorGroupParameters <- getDefaultRetGroupStartingParams()
    retcorGroupParameters$profStep <- 1
    retcorGroupParameters$gapExtend <- 2.7
    resultRetcorGroup <- optimizeRetGroup(
        xset = optimizedXcmsSetObject,
        params = retcorGroupParameters,
        nSlaves = 1,
        subdir = NULL,
        plot = FALSE
    )


    # --- Exporting Optimized Parameters [] ---
    # Key functions: writeRScript
    writeRScript(
        resultPeakpicking$best_settings$parameters,
        resultRetcorGroup$best_settings
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ipo_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ipo_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ipo_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_IPO:", paste0("    ipo: ", packageVersion("IPO"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ipo_results.csv
    touch ${prefix}_ipo_output.rds
    echo "BIOC_IPO:" > versions.yml
    echo "    ipo: 0.0.0" >> versions.yml
    """
}


workflow BIOC_IPO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_IPO(ch_input)

    emit:
    results  = BIOC_IPO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_IPO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_IPO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_IPO.out.versions  // channel: path(versions.yml)
}
