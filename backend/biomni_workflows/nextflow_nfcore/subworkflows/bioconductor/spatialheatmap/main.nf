#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: spatialHeatmap
// The spatialHeatmap package offers the primary functionality for visualizing cell-, tissue- and organ
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/spatialHeatmap/inst/doc/covisualize.R
// Upstream  : BiocParallel, ExpressionAtlas, GEOquery, Seurat, SingleCellExperiment
// Downstream: none
//
// Install: BiocManager::install("spatialHeatmap")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPATIALHEATMAP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-spatialheatmap"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-spatialheatmap:2.12.1--r44_0' :
        'quay.io/biocontainers/bioconductor-spatialheatmap:2.12.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_spatialheatmap_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_spatialheatmap_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_spatialheatmap_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(spatialHeatmap)
    library(jsonlite)

    # --- Table formatting and display [] ---
    # Key functions: markdown, include_graphics, covis, kable
    dat.auto.tocell.tailor <- SPHM(svg=svg.mus.brain, bulk=coclus.blk, cell=coclus.sc.tailor)
    covis(data=dat.auto.tocell.tailor, ID=c('Atp2b1'), dimred='PCA', tar.bulk=c('hippocampus'), assay.na='logcounts', legend.nrow=4, dim.lgd.text.size=10, dim.lgd.nrow=2, bar.width=0.08, legend.r=1.5)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_spatialheatmap_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_spatialheatmap_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_spatialheatmap_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPATIALHEATMAP:", paste0("    spatialheatmap: ", packageVersion("spatialHeatmap"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatialheatmap_results.csv
    touch ${prefix}_spatialheatmap_output.rds
    echo "BIOC_SPATIALHEATMAP:" > versions.yml
    echo "    spatialheatmap: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPATIALHEATMAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPATIALHEATMAP(ch_input)

    emit:
    results  = BIOC_SPATIALHEATMAP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPATIALHEATMAP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPATIALHEATMAP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPATIALHEATMAP.out.versions  // channel: path(versions.yml)
}
