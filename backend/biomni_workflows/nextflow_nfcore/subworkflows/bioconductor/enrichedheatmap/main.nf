#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: EnrichedHeatmap
// Enriched heatmap is a special type of heatmap which visualizes the enrichment of genomic signals on 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/EnrichedHeatmap/inst/doc/EnrichedHeatmap.R
// Upstream  : GetoptLong, RColorBrewer, circlize, genefilter, grid
// Downstream: none
//
// Install: BiocManager::install("EnrichedHeatmap")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ENRICHEDHEATMAP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-enrichedheatmap"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-enrichedheatmap:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-enrichedheatmap:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_enrichedheatmap_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_enrichedheatmap_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_enrichedheatmap_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(EnrichedHeatmap)
    library(jsonlite)

    # --- Enriched Heatmap [] ---
    # Key functions: EnrichedHeatmap
    mat1_smoothed = normalizeToMatrix(H3K4me3, tss, value_column = "coverage",
    EnrichedHeatmap(mat1_smoothed, col = col_fun, name = "H3K4me3_smoothed",
    EnrichedHeatmap(mat1, col = col_fun, name = "H3K4me3", column_title = "unsmoothed")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_enrichedheatmap_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_enrichedheatmap_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_enrichedheatmap_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ENRICHEDHEATMAP:", paste0("    enrichedheatmap: ", packageVersion("EnrichedHeatmap"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_enrichedheatmap_results.csv
    touch ${prefix}_enrichedheatmap_output.rds
    echo "BIOC_ENRICHEDHEATMAP:" > versions.yml
    echo "    enrichedheatmap: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ENRICHEDHEATMAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ENRICHEDHEATMAP(ch_input)

    emit:
    results  = BIOC_ENRICHEDHEATMAP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ENRICHEDHEATMAP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ENRICHEDHEATMAP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ENRICHEDHEATMAP.out.versions  // channel: path(versions.yml)
}
