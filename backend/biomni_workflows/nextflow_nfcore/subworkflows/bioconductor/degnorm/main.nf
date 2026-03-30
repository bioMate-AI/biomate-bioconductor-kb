#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DegNorm
// This package performs degradation normalization in bulk RNA-seq data to improve differential express
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DegNorm/inst/doc/DegNorm.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("DegNorm")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DEGNORM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-degnorm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-degnorm:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-degnorm:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_degnorm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_degnorm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_degnorm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DegNorm)
    library(jsonlite)

    # --- Files [] ---
    # Key functions: files
    ---------------------------------------------------------------------
    ## specify bam_files from RNA-seq, you should replace it by your own bam files
    bam_file_list=list.files(path=system.file("extdata",package="DegNorm"),
                            pattern=".bam$",full.names=TRUE)
    # --- Data [] ---
    # Key functions: summary_CoverageClass
    ---------------------------------------------------------------------
    data("coverage_res_chr21")
    ## summarize the coverage results
    summary_CoverageClass(coverage_res_chr21)
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data("res_DegNorm_chr21")
    # --- Summary Degnormclass [] ---
    # Key functions: summary_DegNormClass
    ---------------------------------------------------------------------
    ## summary of the DegNorm output
    summary_DegNormClass(res_DegNorm_chr21)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_degnorm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_degnorm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_degnorm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DEGNORM:", paste0("    degnorm: ", packageVersion("DegNorm"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_degnorm_results.csv
    touch ${prefix}_degnorm_output.rds
    echo "BIOC_DEGNORM:" > versions.yml
    echo "    degnorm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DEGNORM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DEGNORM(ch_input)

    emit:
    results  = BIOC_DEGNORM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DEGNORM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DEGNORM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DEGNORM.out.versions  // channel: path(versions.yml)
}
