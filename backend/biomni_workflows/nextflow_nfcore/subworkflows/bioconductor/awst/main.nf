#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: awst
// We propose an Asymmetric Within-Sample Transformation (AWST) to regularize RNA-seq read counts and r
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/awst/inst/doc/awst_intro.R
// Upstream  : EDASeq, RefManageR, SummarizedExperiment, airway, ggplot2
// Downstream: none
//
// Install: BiocManager::install("awst")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_AWST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-awst"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-awst:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-awst:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(summarizedexperiment)

    output:
    tuple val(meta), path("${meta.id}_awst_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_awst_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_awst_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(awst)
    library(PrintBibliography)
    library(jsonlite)

    # --- Gene Filtering [] ---
    # Key functions: gene_filter
    # Filter out low-intensity genes after AWST transformation
    filtered_se <- gene_filter(
        se_transformed,
        pos_thr = 0,
        min_val = 0
    )
    filtered_matrix <- assay(filtered_se, "awst")


    # --- Transformation with Custom Normalization [] ---
    # Key functions: awst
    # Apply AWST using a pre-calculated normalized assay slot
    se_custom <- awst(
        se,
        expr_values = "fq",
        p_min = 0.025,
        p_max = 0.975
    )
    custom_matrix <- assay(se_custom, "awst")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_awst_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_awst_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_awst_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_AWST:", paste0("    awst: ", packageVersion("awst"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_awst_results.csv
    touch ${prefix}_awst_output.rds
    echo "BIOC_AWST:" > versions.yml
    echo "    awst: 0.0.0" >> versions.yml
    """
}


workflow BIOC_AWST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(summarizedexperiment) ]

    main:
    BIOC_AWST(ch_input)

    emit:
    results  = BIOC_AWST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_AWST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_AWST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_AWST.out.versions  // channel: path(versions.yml)
}
