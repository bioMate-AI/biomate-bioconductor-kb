#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: recount3
// The recount3 package enables access to a large amount of uniformly processed RNA-seq data from human
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/recount3/inst/doc/recount3-quickstart.R
// Upstream  : knitcitations, knitr, rmarkdown, sessioninfo
// Downstream: none
//
// Install: BiocManager::install("recount3")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RECOUNT3 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-recount3"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-recount3:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-recount3:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_recount3_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_recount3_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_recount3_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(recount3)
    library(jsonlite)

    # --- Data Retrieval [] ---
    # Key functions: create_rse, annotation_options
    ann_opts <- annotation_options(organism = "human")
    rse_gene_SRP009615 <- create_rse(
        project_info,
        type = "gene",
        annotation = ann_opts[1]
    )


    # --- Metadata Expansion [] ---
    # Key functions: expand_sra_attributes
    rse_expanded <- expand_sra_attributes(rse_gene_SRP009615)
    sra_cols <- colnames(colData(rse_expanded))
    meta_info <- metadata(rse_expanded)
    row_ranges <- rowRanges(rse_expanded)


    # --- Count Transformation [] ---
    # Key functions: transform_counts
    counts_transformed <- transform_counts(
        rse_gene_SRP009615,
        round = TRUE
    )
    assay(rse_gene_SRP009615, "counts") <- counts_transformed

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_recount3_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_recount3_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_recount3_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RECOUNT3:", paste0("    recount3: ", packageVersion("recount3"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_recount3_results.csv
    touch ${prefix}_recount3_output.rds
    echo "BIOC_RECOUNT3:" > versions.yml
    echo "    recount3: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RECOUNT3_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RECOUNT3(ch_input)

    emit:
    results  = BIOC_RECOUNT3.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RECOUNT3.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RECOUNT3.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RECOUNT3.out.versions  // channel: path(versions.yml)
}
