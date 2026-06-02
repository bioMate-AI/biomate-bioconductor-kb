#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ComplexHeatmap
// Complex heatmaps are efficient to visualize associations between different sources of data sets and 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ComplexHeatmap/inst/doc/most_probably_asked_questions.R
// Upstream  : markdown
// Downstream: AMARETTO, EnrichedHeatmap, InteractiveComplexHeatmap, multistateQTL, recoup
//
// Install: BiocManager::install("ComplexHeatmap")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_COMPLEXHEATMAP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-complexheatmap"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-complexheatmap:2.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-complexheatmap:2.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_complexheatmap_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_complexheatmap_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_complexheatmap_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Heatmap)
    library(jsonlite)

    # --- Matrix [] ---
    # Key functions: rnorm, hclust, dist, cutree, Heatmap, cluster_within_group
    ---------------------------------------------------------------------
    m = matrix(rnorm(1000*10), nr = 1000)
    hc = hclust(dist(m))
    group = cutree(hc, k = 6)
    # --- Matrix [] ---
    # Key functions: rnorm, Heatmap, unit, draw, decorate_column_dend, yaxis
    ---------------------------------------------------------------------
    m = matrix(rnorm(100), 10)
    # --- Hclust [] ---
    # Key functions: hclust, dist, rnorm, Heatmap, rowAnnotation, anno_points, anno_barplot
    ---------------------------------------------------------------------
    hc = hclust(dist(matrix(rnorm(100), 10)))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_complexheatmap_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_complexheatmap_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_complexheatmap_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_COMPLEXHEATMAP:", paste0("    complexheatmap: ", packageVersion("ComplexHeatmap"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_complexheatmap_results.csv
    touch ${prefix}_complexheatmap_output.rds
    echo "BIOC_COMPLEXHEATMAP:" > versions.yml
    echo "    complexheatmap: 0.0.0" >> versions.yml
    """
}


workflow BIOC_COMPLEXHEATMAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_COMPLEXHEATMAP(ch_input)

    emit:
    results  = BIOC_COMPLEXHEATMAP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_COMPLEXHEATMAP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_COMPLEXHEATMAP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_COMPLEXHEATMAP.out.versions  // channel: path(versions.yml)
}
