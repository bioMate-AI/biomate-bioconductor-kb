#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: VplotR
// The pattern of digestion and protection from DNA nucleases such as DNAse I, micrococcal nuclease, an
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/VplotR/inst/doc/VplotR.R
// Upstream  : GenomicRanges, ggplot2
// Downstream: none
//
// Install: BiocManager::install("VplotR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VPLOTR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-vplotr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-vplotr:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-vplotr:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_vplotr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_vplotr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_vplotr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(VplotR)
    library(jsonlite)

    # --- Plotfootprint [] ---
    # Key functions: plotFootprint
    ---------------------------------------------------------------------
    p <- plotFootprint(
        MNase_sacCer3_Henikoff2011,
        ABF1_sacCer3
    )
    # --- Data [] ---
    # Key functions: genes, plotProfile
    ---------------------------------------------------------------------
    data(MNase_sacCer3_Henikoff2011_subset)
    genes_sacCer3 <- GenomicFeatures::genes(TxDb.Scerevisiae.UCSC.sacCer3.sgdGene::
        TxDb.Scerevisiae.UCSC.sacCer3.sgdGene
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_vplotr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_vplotr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_vplotr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_VPLOTR:", paste0("    vplotr: ", packageVersion("VplotR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_vplotr_results.csv
    touch ${prefix}_vplotr_output.rds
    echo "BIOC_VPLOTR:" > versions.yml
    echo "    vplotr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_VPLOTR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_VPLOTR(ch_input)

    emit:
    results  = BIOC_VPLOTR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_VPLOTR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_VPLOTR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_VPLOTR.out.versions  // channel: path(versions.yml)
}
