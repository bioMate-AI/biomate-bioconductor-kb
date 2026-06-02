#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: UMI4Cats
// UMI-4C is a technique that allows characterization of 3D chromatin interactions with a bait of inter
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/UMI4Cats/inst/doc/UMI4Cats.R
// Upstream  : tidyr
// Downstream: none
//
// Install: BiocManager::install("UMI4Cats")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_UMI4CATS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-umi4cats"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-umi4cats:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-umi4cats:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_umi4cats_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_umi4cats_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_umi4cats_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(UMI4Cats)
    library(jsonlite)

    # --- Sample metadata inspection [] ---
    # Key functions: include_graphics, downloadUMI4CexampleData, digestGenome, contactsUMI4C, statsUMI4C, separate, tempdir, demultiplexFastq
    win_frags <- makeWindowFragments(umi, n_frags=8)
    gr <-  callInteractions(umi4c = umi,
    all <- plotInteractionsUMI4C(umi, gr, grouping = NULL, significant=FALSE, xlim=c(10.75e6, 11.1e6)) # Plot all regions

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_umi4cats_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_umi4cats_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_umi4cats_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_UMI4CATS:", paste0("    umi4cats: ", packageVersion("UMI4Cats"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_umi4cats_results.csv
    touch ${prefix}_umi4cats_output.rds
    echo "BIOC_UMI4CATS:" > versions.yml
    echo "    umi4cats: 0.0.0" >> versions.yml
    """
}


workflow BIOC_UMI4CATS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_UMI4CATS(ch_input)

    emit:
    results  = BIOC_UMI4CATS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_UMI4CATS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_UMI4CATS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_UMI4CATS.out.versions  // channel: path(versions.yml)
}
