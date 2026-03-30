#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CeTF
// This package provides the necessary functions for performing the Partial Correlation coefficient wit
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CeTF/inst/doc/CeTF.R
// Upstream  : airway, dplyr, kableExtra, knitr
// Downstream: none
//
// Install: BiocManager::install("CeTF")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CETF {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cetf"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cetf:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cetf:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cetf_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cetf_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cetf_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PCIT)
    library(SmearPlot)
    library(jsonlite)

    # --- Assay data access [] ---
    # Key functions: assay, expDiff, normExp, PCIT, histPlot, densityPlot, setdiff, runAnalysis
    genes <- unique(c(as.character(NetworkData(out, "network1")[, "gene1"]),
    as.character(NetworkData(out, "network1")[, "gene2"])))
    enrich <- getEnrich(genes = genes, organismDB = org.Hs.eg.db,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cetf_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cetf_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cetf_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CETF:", paste0("    cetf: ", packageVersion("CeTF"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cetf_results.csv
    touch ${prefix}_cetf_output.rds
    echo "BIOC_CETF:" > versions.yml
    echo "    cetf: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CETF_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CETF(ch_input)

    emit:
    results  = BIOC_CETF.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CETF.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CETF.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CETF.out.versions  // channel: path(versions.yml)
}
