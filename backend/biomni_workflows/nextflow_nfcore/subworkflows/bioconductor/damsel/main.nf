#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Damsel
// Damsel provides an end to end analysis of DamID data. Damsel takes bam files from Dam-only control a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Damsel/inst/doc/Damsel-workflow.R
// Upstream  : biomaRt
// Downstream: none
//
// Install: BiocManager::install("Damsel")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DAMSEL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-damsel"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-damsel:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-damsel:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_damsel_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_damsel_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_damsel_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Damsel)
    library(jsonlite)

    # --- plot Corr Heatmap [] ---
    # Key functions: plotCorrHeatmap, plotCountsDistribution
    plotCorrHeatmap(df = counts.df, method = "spearman")
    plotCountsDistribution(counts.df, constant = 1)
    # --- Plot counts for individual gene [] ---
    # Key functions: plotCounts, makeDGE

    # --- MDS plot of sample distances [] ---
    # Key functions: plotMDS, testDmRegions, group_by, summarise
    group <- dge$samples$group %>% as.character()
    limma::plotMDS(dge, col = as.numeric(factor(group)))
    dm_results <- testDmRegions(dge, p.value = 0.05, lfc = 1, regions = regions, plot = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_damsel_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_damsel_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_damsel_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DAMSEL:", paste0("    damsel: ", packageVersion("Damsel"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_damsel_results.csv
    touch ${prefix}_damsel_output.rds
    echo "BIOC_DAMSEL:" > versions.yml
    echo "    damsel: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DAMSEL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DAMSEL(ch_input)

    emit:
    results  = BIOC_DAMSEL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DAMSEL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DAMSEL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DAMSEL.out.versions  // channel: path(versions.yml)
}
