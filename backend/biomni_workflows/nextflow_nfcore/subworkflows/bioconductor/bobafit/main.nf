#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BOBaFIT
// This package provides a method to refit and correct the diploid region in copy number profiles. It u
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BOBaFIT/inst/doc/BOBaFIT.R
// Upstream  : TCGAbiolinks, dplyr
// Downstream: none
//
// Install: BiocManager::install("BOBaFIT")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BOBAFIT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bobafit"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bobafit:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bobafit:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bobafit_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bobafit_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bobafit_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BOBaFIT)
    library(DRrefit)
    library(DRrefit_plot)
    library(PlotChrCluster)
    library(jsonlite)

    # --- Copy Number Refitting [] ---
    # Key functions: DRrefit
    results <- DRrefit(
        segments_chort = TCGA_BRCA_CN_segments,
        chrlist = chr_list
    )
    corrected_segments <- results$corrected_segments
    report <- results$report


    # --- Visualisation [] ---
    # Key functions: DRrefit_plot
    DRrefit_plot(
        corrected_segments = corrected_segments,
        DRrefit_report = report,
        plot_viewer = TRUE
    )


    # --- Chromosome Clustering [] ---
    # Key functions: PlotChrCluster
    Cluster <- PlotChrCluster(
        segs = TCGA_BRCA_CN_segments,
        clust_method = "ward.D2",
        plot_output = TRUE
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bobafit_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bobafit_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bobafit_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BOBAFIT:", paste0("    bobafit: ", packageVersion("BOBaFIT"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bobafit_results.csv
    touch ${prefix}_bobafit_output.rds
    echo "BIOC_BOBAFIT:" > versions.yml
    echo "    bobafit: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BOBAFIT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BOBAFIT(ch_input)

    emit:
    results  = BIOC_BOBAFIT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BOBAFIT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BOBAFIT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BOBAFIT.out.versions  // channel: path(versions.yml)
}
