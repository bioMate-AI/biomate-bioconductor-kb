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


    # --- Eval = False [] ---
    # Key functions: load, promoters, normalizeToMatrix, extdata, chr21_test_data.RData, coverage
    #  library(EnrichedHeatmap)

    ## -------------------------------------------------------------------------------------------------
    set.seed(123)
    load(system.file("extdata", "chr21_test_data.RData", package = "EnrichedHeatmap"))
    ls()

    ## -------------------------------------------------------------------------------------------------
    tss = promoters(genes, upstream = 0, downstream = 1)
    tss[1:5]
    H3K4me3[1:5]

    ## -------------------------------------------------------------------------------------------------
    mat1 = normalizeToMatrix(H3K4me3, tss, value_column = "coverage", 
        extend = 5000, mean_mode = "w0", w = 50)

    # --- Smooth [] ---
    # Key functions: normalizeToMatrix, EnrichedHeatmap, coverage, H3K4me3_smoothed, smoothed, unsmoothed
    mat1_smoothed = normalizeToMatrix(H3K4me3, tss, value_column = "coverage", 
        extend = 5000, mean_mode = "w0", w = 50, background = 0, smooth = TRUE)
    EnrichedHeatmap(mat1_smoothed, col = col_fun, name = "H3K4me3_smoothed",
        column_title = "smoothed") +
    EnrichedHeatmap(mat1, col = col_fun, name = "H3K4me3", column_title = "unsmoothed")

    # --- Extension [] ---
    # Key functions: normalizeToMatrix, EnrichedHeatmap, meth, absolute, methylation
    mat3 = normalizeToMatrix(meth, cgi, value_column = "meth", mean_mode = "absolute",
        extend = c(0, 5000), w = 50, background = NA, smooth = TRUE, target_ratio = 0.5)
    EnrichedHeatmap(mat3, col = meth_col_fun, name = "methylation", 
        column_title = "methylation near CGI")
    mat3 = normalizeToMatrix(meth, cgi, value_column = "meth", mean_mode = "absolute",
        extend = c(5000, 0), w = 50, background = NA, smooth = TRUE, target_ratio = 0.5)
    EnrichedHeatmap(mat3, col = meth_col_fun, name = "methylation", 
        column_title = "methylation near CGI")

    # --- Eval = False [] ---
    # Key functions: attr, normalizeToMatrix, attributes, upstream_index, target_index, downstream_index, extend, coverage
    #  attr(mat, "upstream_index")
    #  attr(mat, "target_index")
    #  attr(mat, "downstream_index")
    #  attr(mat, "extend")

    ## -------------------------------------------------------------------------------------------------
    mat1 = normalizeToMatrix(H3K4me3, tss, value_column = "coverage", 
        extend = 5000, mean_mode = "w0", w = 50)
    mat2 = mat1
    attributes(mat2) = NULL
    dim(mat2) = dim(mat1)
    mat2[1:4, 1:4]

    ## -------------------------------------------------------------------------------------------------
    attr(mat2, "upstream_index") = 1:100

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
