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
    library(ComplexHeatmap)
    library(Heatmap)
    library(jsonlite)

    # --- Complex Row and Column Annotations [] ---
    # Key functions: Heatmap, rowAnnotation, anno_points, anno_barplot
    hc = hclust(dist(matrix(rnorm(100), 10)))
    ht = Heatmap(matrix(ncol = 0, nrow = 10),
        cluster_rows = hc,
        right_annotation = rowAnnotation(
            foo = anno_points(1:10),
            sth = 1:10,
            bar = anno_barplot(1:10)
        ),
        row_split = 2
    )


    # --- Heatmap Decoration and Layout Customization [] ---
    # Key functions: Heatmap, draw, decorate_column_dend, decorate_row_dend
    m = matrix(rnorm(100), 10)
    ht = Heatmap(m,
        name = "foo",
        row_dend_width = unit(4, "cm"),
        column_dend_height = unit(4, "cm")
    )
    draw(ht, padding = unit(c(15, 2, 2, 2), "mm"))
    decorate_column_dend("foo", {
        grid.yaxis()
    })
    decorate_row_dend("foo", {
        vp = current.viewport()
        xscale = vp$xscale
        grid.xaxis(at = xscale[2] - 0:5, label = 0:5)
    })

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
