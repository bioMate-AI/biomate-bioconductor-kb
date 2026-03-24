#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BioNERO
// BioNERO aims to integrate all aspects of biological network inference in a single package, including
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BioNERO/inst/doc/vignette_01_GCN_inference.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("BioNERO")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIONERO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bionero"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bionero:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bionero:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_bionero_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bionero_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bionero_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PC_correction)
    library(SFT_fit)
    library(ZKfiltering)
    library(jsonlite)

    # --- Sample metadata inspection [] ---
    # Key functions: colData, replace_na, remove_nonexp, filter_by_variance, ZKfiltering, PC_correction, exp_preprocess, plot_heatmap
    p <- plot_heatmap(final_exp, type = "samplecor", show_rownames = FALSE)
    Heatmap of gene expression (here, only the first 50 genes)
    p <- plot_heatmap(

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bionero_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bionero_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bionero_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIONERO:", paste0("    bionero: ", packageVersion("BioNERO"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bionero_results.csv
    touch ${prefix}_bionero_output.rds
    echo "BIOC_BIONERO:" > versions.yml
    echo "    bionero: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIONERO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_BIONERO(ch_input)

    emit:
    results  = BIOC_BIONERO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIONERO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIONERO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIONERO.out.versions  // channel: path(versions.yml)
}
