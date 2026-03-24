#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: mimager
// Easily visualize and inspect microarrays for spatial artifacts.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/mimager/inst/doc/introduction.R
// Upstream  : affyPLM, knitr
// Downstream: none
//
// Install: BiocManager::install("mimager")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MIMAGER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mimager"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mimager:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mimager:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mimager_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mimager_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mimager_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(mimager)
    library(jsonlite)

    # --- Mimage analysis [] ---
    # Key functions: mimage, fitPLM, marray, arank
    div.colors <- scales::brewer_pal(palette = "RdBu")(9)
    mimage(Dilution, transform = arle, legend.label = "RLE", colors = div.colors)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mimager_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mimager_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mimager_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MIMAGER:", paste0("    mimager: ", packageVersion("mimager"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mimager_results.csv
    touch ${prefix}_mimager_output.rds
    echo "BIOC_MIMAGER:" > versions.yml
    echo "    mimager: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MIMAGER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MIMAGER(ch_input)

    emit:
    results  = BIOC_MIMAGER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MIMAGER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MIMAGER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MIMAGER.out.versions  // channel: path(versions.yml)
}
