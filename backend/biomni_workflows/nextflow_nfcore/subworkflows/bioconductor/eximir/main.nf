#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ExiMiR
// This package contains functions for reading raw data in ImaGene TXT format obtained from Exiqon miRC
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ExiMiR/inst/doc/ExiMiR-vignette.R
// Upstream  : affy
// Downstream: none
//
// Install: BiocManager::install("ExiMiR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EXIMIR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-eximir"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-eximir:2.48.0--r44_0' :
        'quay.io/biocontainers/bioconductor-eximir:2.48.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_eximir_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_eximir_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_eximir_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(NormiR)
    library(jsonlite)

    # --- Eximir Vignette.Rnw:694 696 [] ---
    # Key functions: data
    library(ExiMiR)
    data(GSE19183)
    # --- Eximir Vignette.Rnw:699 705 [] ---
    # Key functions: expresso
    library(affy)
    eset.rma <- expresso(GSE19183, bgcorrect.method='rma',
    			       normalize.method='quantiles',
    			       pmcorrect.method='pmonly',
    			       summary.method='medianpolish')
    # --- Eximir Vignette.Rnw:708 713 [] ---
    # Key functions: NormiR
    eset.spike <- NormiR(GSE19183, bgcorrect.method='rma',
    			       normalize.method='spikein',
    			       normalize.param=list(figures.show=FALSE),
    			       pmcorrect.method='pmonly',
    			       summary.method='medianpolish')
    # --- Eximir Vignette.Rnw:723 726 [] ---
    # Key functions: data
    library(ExiMiR)
    data(galenv)
    data(GSE20122)
    # --- Eximir Vignette.Rnw:730 733 [] ---
    # Key functions: NormiR
    eset.rma <- NormiR(GSE20122, bg.correct=FALSE,
    			     normalize.method='quantile',
    			     summary.method='medianpolish')
    # --- Eximir Vignette.Rnw:736 740 [] ---
    # Key functions: NormiR
    eset.spike <- NormiR(GSE20122, bg.correct=FALSE,
    			       normalize.method='spikein',
    			       normalize.param=list(figures.show=FALSE),
    			       summary.method='medianpolish')

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_eximir_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_eximir_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_eximir_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EXIMIR:", paste0("    eximir: ", packageVersion("ExiMiR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_eximir_results.csv
    touch ${prefix}_eximir_output.rds
    echo "BIOC_EXIMIR:" > versions.yml
    echo "    eximir: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EXIMIR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EXIMIR(ch_input)

    emit:
    results  = BIOC_EXIMIR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EXIMIR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EXIMIR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EXIMIR.out.versions  // channel: path(versions.yml)
}
