#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: tRNA
// The tRNA package allows tRNA sequences and structures to be accessed and used for subsetting. In add
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/tRNA/inst/doc/tRNA.R
// Upstream  : Structstrings
// Downstream: tRNAdbImport, tRNAscanImport
//
// Install: BiocManager::install("tRNA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TRNA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-trna"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-trna:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-trna:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_trna_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_trna_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_trna_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(tRNA)
    library(jsonlite)

    # --- gett R N A Loop I Ds [] ---
    # Key functions: gettRNALoopIDs, getLoopIndices
    plots$length$layers <- plots$length$layers[c(-1L,-2L)]
    plots$length + ggplot2::geom_boxplot()
    head(plots$length$data)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_trna_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_trna_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_trna_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TRNA:", paste0("    trna: ", packageVersion("tRNA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_trna_results.csv
    touch ${prefix}_trna_output.rds
    echo "BIOC_TRNA:" > versions.yml
    echo "    trna: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TRNA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TRNA(ch_input)

    emit:
    results  = BIOC_TRNA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TRNA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TRNA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TRNA.out.versions  // channel: path(versions.yml)
}
