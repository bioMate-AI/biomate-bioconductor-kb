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
    library(DRrefit)
    library(DRrefit_plot)
    library(PlotChrCluster)
    library(jsonlite)

    # --- compute Normal Chromosomes [] ---
    # Key functions: computeNormalChromosomes
    chr_list <- computeNormalChromosomes(segments = TCGA_BRCA_CN_segments,
    # --- D Rrefit [] ---
    # Key functions: DRrefit
    results <- DRrefit (segments_chort = TCGA_BRCA_CN_segments, chrlist = chr_list)
    # --- DRrefit test [] ---
    # Key functions: DRrefit
    library(dplyr)
    samples <- TCGA_BRCA_CN_segments$ID %>% unique()
    test <- TCGA_BRCA_CN_segments %>% filter(ID %in% sample_test)
    # --- Call segments DRrefit 1 [] ---
    # Key functions: kable
    table <- results$corrected_segments[1,] %>% select(chr,start,end, ID, arm, chrarm,CN,CN_corrected)
    knitr::kable(table,digits = 3)
    # --- Call report DRrefit 2 [] ---
    # Key functions: kable
    knitr::kable(results$report[1,])
    # --- DRrefit plot [] ---
    # Key functions: DRrefit_plot
    DRrefit_plot(corrected_segments = corrected_segments,
    DRrefit_plot(corrected_segments = corrected_segments,
    # --- DRrefit plot 1 [] ---
    # Key functions: DRrefit_plot
    DRrefit_plot(corrected_segments = seg,
    # --- DRrefit plot 2 [] ---
    # Key functions: DRrefit_plot
    DRrefit_plot(corrected_segments = seg,
    # --- Plot Chr Cluster [] ---
    # Key functions: PlotChrCluster
    Cluster <- PlotChrCluster(segs = TCGA_BRCA_CN_segments,
    # --- PlotChrCluster test [] ---
    # Key functions: PlotChrCluster
    Cluster <- PlotChrCluster(segs = test,
    # --- Call report PlotChrCluster 3 [] ---
    # Key functions: kable
    knitr::kable(head(Cluster$report))
    knitr::kable(head(Cluster$plot_tables$`01428281-1653-4839-b5cf-167bc62eb147`))

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
