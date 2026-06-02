#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: gtrellis
// Genome level Trellis graph visualizes genomic data conditioned by genomic categories (e.g. chromosom
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/gtrellis/inst/doc/gtrellis.R
// Upstream  : ComplexHeatmap, GetoptLong, RColorBrewer, circlize, knitr
// Downstream: none
//
// Install: BiocManager::install("gtrellis")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GTRELLIS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gtrellis"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gtrellis:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gtrellis:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gtrellis_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gtrellis_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gtrellis_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(gtrellis)
    library(jsonlite)

    # --- Genomic Track Visualization [] ---
    # Key functions: add_points_track, add_segments_track, add_lines_track, add_rect_track
    gtrellis_layout(track_ylim = c(-2, 2), nrow = 3, byrow = FALSE)
    add_points_track(bed, bed[[4]], gp = gpar(col = "red"))
    add_segments_track(bed, bed[[4]], gp = gpar(col = "blue", lwd = 2))
    add_lines_track(bed, bed[[4]], area = TRUE, gp = gpar(fill = "grey"))
    add_rect_track(bed, h1 = bed[[4]], h2 = 0, gp = gpar(fill = "green"))


    # --- Custom Panel Drawing [] ---
    # Key functions: add_track, get_cell_meta_data
    gtrellis_layout(nrow = 3, track_ylim = c(-2, 2))
    add_track(bed, panel_fun = function(bed) {
        x = (bed[[2]] + bed[[3]]) / 2
        y = bed[[4]]
        grid.points(x, y, pch = 16, size = unit(1, "mm"))
    })

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gtrellis_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gtrellis_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gtrellis_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GTRELLIS:", paste0("    gtrellis: ", packageVersion("gtrellis"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gtrellis_results.csv
    touch ${prefix}_gtrellis_output.rds
    echo "BIOC_GTRELLIS:" > versions.yml
    echo "    gtrellis: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GTRELLIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GTRELLIS(ch_input)

    emit:
    results  = BIOC_GTRELLIS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GTRELLIS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GTRELLIS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GTRELLIS.out.versions  // channel: path(versions.yml)
}
