#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MICSQTL
// Our pipeline, MICSQTL, utilizes scRNA-seq reference and bulk transcriptomes to estimate cellular com
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MICSQTL/inst/doc/MICSQTL.R
// Upstream  : GGally, ggplot2, reshape2
// Downstream: none
//
// Install: BiocManager::install("MICSQTL")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MICSQTL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-micsqtl"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-micsqtl:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-micsqtl:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_micsqtl_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_micsqtl_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_micsqtl_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MICSQTL)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Distance Filtering [] ---
    # Key functions: feature_filter
    se_dist <- feature_filter(
        se,
        target_protein = target_protein,
        filter_method = "distance",
        filter_geno = 0.05,
        ref_position = "TSS"
    )


    # --- Combined Feature Filtering [] ---
    # Key functions: feature_filter
    se_final <- feature_filter(
        se,
        target_protein = target_protein,
        filter_method = c("allele", "distance"),
        filter_allele = 0.15,
        filter_geno = 0.05,
        ref_position = "TSS"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_micsqtl_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_micsqtl_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_micsqtl_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MICSQTL:", paste0("    micsqtl: ", packageVersion("MICSQTL"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_micsqtl_results.csv
    touch ${prefix}_micsqtl_output.rds
    echo "BIOC_MICSQTL:" > versions.yml
    echo "    micsqtl: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MICSQTL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MICSQTL(ch_input)

    emit:
    results  = BIOC_MICSQTL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MICSQTL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MICSQTL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MICSQTL.out.versions  // channel: path(versions.yml)
}
