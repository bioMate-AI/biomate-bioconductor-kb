#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: miQC
// Single-cell RNA-sequencing (scRNA-seq) has made it possible to profile gene expression in tissues at
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/miQC/inst/doc/miQC.R
// Upstream  : SingleCellExperiment, flexmix, scRNAseq, scater, splines
// Downstream: none
//
// Install: BiocManager::install("miQC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MIQC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-miqc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-miqc:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-miqc:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_miqc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_miqc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_miqc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(miQC)
    library(BuettnerESCData)
    library(SingleCellExperiment)
    library(ZeiselBrainData)
    library(jsonlite)

    # --- Mixture Model Fitting [] ---
    # Key functions: mixtureModel, parameters
    model <- mixtureModel(sce, model_type = "spline")
    model_params <- parameters(model)
    model_poly <- mixtureModel(sce, model_type = "polynomial")


    # --- Filtering Visualization and Cell Filtering [] ---
    # Key functions: plotModel, plotFiltering, filterCells
    model_plot <- plotModel(sce, model)
    filter_plot <- plotFiltering(sce, model, posterior_cutoff = 0.9)
    sce_filtered <- filterCells(sce, model)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_miqc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_miqc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_miqc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MIQC:", paste0("    miqc: ", packageVersion("miQC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_miqc_results.csv
    touch ${prefix}_miqc_output.rds
    echo "BIOC_MIQC:" > versions.yml
    echo "    miqc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MIQC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MIQC(ch_input)

    emit:
    results  = BIOC_MIQC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MIQC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MIQC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MIQC.out.versions  // channel: path(versions.yml)
}
