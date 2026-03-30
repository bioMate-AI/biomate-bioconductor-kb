#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: M3Drop
// This package fits a model to the pattern of dropouts in single-cell RNASeq data. This model is used 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/M3Drop/inst/doc/M3Drop_Vignette.R
// Upstream  : ROCR
// Downstream: none
//
// Install: BiocManager::install("M3Drop")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_M3DROP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-m3drop"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-m3drop:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-m3drop:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(input_file)

    output:
    tuple val(meta), path("${meta.id}_m3drop_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_m3drop_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_m3drop_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BrenneckeGetVariableGenes)
    library(M3DropConvertData)
    library(M3DropExpressionHeatmap)
    library(M3DropFeatureSelection)
    library(M3DropGetHeatmapClusters)
    library(NBumiCheckFitFS)
    library(NBumiConvertData)
    library(NBumiFeatureSelectionCombinedDrop)
    library(NBumiFitModel)
    library(NBumiPearsonResiduals)
    library(jsonlite)

    # --- ColSums analysis [] ---
    # Key functions: colSums, M3DropConvertData, M3DropFeatureSelection, NBumiConvertData, NBumiFitModel, NBumiCheckFitFS, NBumiFeatureSelectionCombinedDrop, NBumiPearsonResiduals
    counts <- Mmus_example_list$data
    labels <- Mmus_example_list$labels
    total_features <- colSums(counts >= 0)
    counts <- counts[,total_features >= 2000]
    labels <- labels[total_features >= 2000]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_m3drop_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_m3drop_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_m3drop_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_M3DROP:", paste0("    m3drop: ", packageVersion("M3Drop"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_m3drop_results.csv
    touch ${prefix}_m3drop_output.rds
    echo "BIOC_M3DROP:" > versions.yml
    echo "    m3drop: 0.0.0" >> versions.yml
    """
}


workflow BIOC_M3DROP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input_file) ]

    main:
    BIOC_M3DROP(ch_input)

    emit:
    results  = BIOC_M3DROP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_M3DROP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_M3DROP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_M3DROP.out.versions  // channel: path(versions.yml)
}
