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

    # --- Lapply [] ---
    # Key functions: frame
    -----------------------------------------------------------------------------------------
    tp_family$TP53 = lapply(tp_family$TP53, function(df) {
            data.frame(start = abs(df[[2]] - 7590856),
                       end = abs(df[[1]] - 7590856))
        })
    # --- Generaterandombed [] ---
    # Key functions: generateRandomBed, gtrellis_layout, add_track, unit
    -----------------------------------------------------------------------------------------
    bed = generateRandomBed()
    gtrellis_layout(category = "chr1", n_track = 4, track_ylim = range(bed[[4]]))
    add_track(bed, panel_fun = function(bed) {
        grid.points((bed[[2]] + bed[[3]]) / 2, bed[[4]], pch = 16, size = unit(2, "mm"))

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
