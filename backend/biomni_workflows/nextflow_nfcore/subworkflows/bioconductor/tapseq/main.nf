#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TAPseq
// Design primers for targeted single-cell RNA-seq used by TAP-seq. Create sequence templates for targe
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TAPseq/inst/doc/tapseq_primer_design.R
// Upstream  : BSgenome, BiocParallel, GenomicRanges, Seurat, dplyr
// Downstream: none
//
// Install: BiocManager::install("TAPseq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TAPSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tapseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tapseq:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tapseq:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tapseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tapseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tapseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TAPseq)
    library(jsonlite)


    # --- Include=false [] ---
    # Key functions: set
    knitr::opts_chunk$set(
      collapse = TRUE,
      comment = "#>"
    )

    # --- Include=false [] ---
    # Key functions: tapseq
    # Primer3 and BLAST are not run in this vignette, because they might be missing on the build system.
    # already designed primers are loaded from internal data
    outer_primers <- TAPseq:::vignette_data$outer_primers

    # --- Results="hide" [] ---
    # Key functions: tapseq_primers, pcr_products
    # get primers and pcr products for specific genes
    tapseq_primers(outer_primers$HBE1)
    pcr_products(outer_primers$HBE1)

    # these can also be accessed for all genes
    tapseq_primers(outer_primers)
    pcr_products(outer_primers)

    # --- Results="hide" [] ---
    # Key functions: pickPrimers, tapseq_primers, off_targets
    # select best primer per target gene based on the number of potential off-targets
    best_outer_primers <- pickPrimers(outer_primers, n = 1, by = "off_targets")

    # each object now only contains the best primer
    tapseq_primers(best_outer_primers$IFITM1)

    # --- Include=false [] ---
    # Key functions: tapseq
    best_inner_primers <- TAPseq:::vignette_data$best_inner_primers

    # --- Include=false [] ---
    # Key functions: tapseq
    outer_comp <- TAPseq:::vignette_data$outer_comp
    inner_comp <- TAPseq:::vignette_data$inner_comp

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tapseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tapseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tapseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TAPSEQ:", paste0("    tapseq: ", packageVersion("TAPseq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tapseq_results.csv
    touch ${prefix}_tapseq_output.rds
    echo "BIOC_TAPSEQ:" > versions.yml
    echo "    tapseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TAPSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TAPSEQ(ch_input)

    emit:
    results  = BIOC_TAPSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TAPSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TAPSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TAPSEQ.out.versions  // channel: path(versions.yml)
}
