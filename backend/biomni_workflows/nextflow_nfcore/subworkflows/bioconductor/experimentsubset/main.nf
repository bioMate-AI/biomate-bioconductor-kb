#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ExperimentSubset
// Experiment objects such as the SummarizedExperiment or SingleCellExperiment are data containers for 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ExperimentSubset/inst/doc/ExperimentSubset.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("ExperimentSubset")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EXPERIMENTSUBSET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-experimentsubset"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-experimentsubset:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-experimentsubset:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_experimentsubset_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_experimentsubset_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_experimentsubset_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ExperimentSubset)
    library(SingleCellExperiment)
    library(jsonlite)

    # --- Subset Creation [] ---
    # Key functions: createSubset, subsetSummary
    es <- createSubset(
        es,
        subsetName = "subset1",
        rows = 1:5,
        cols = 1:5,
        parentAssay = "counts"
    )
    es <- createSubset(
        es,
        subsetName = "subset2",
        rows = 1:2,
        cols = 1:5,
        parentAssay = "subset1"
    )
    summary_info <- subsetSummary(es)


    # --- Subset Assay Manipulation [] ---
    # Key functions: setSubsetAssay, getSubsetAssay
    subset1Assay <- SummarizedExperiment::assay(es, "subset1")
    subset1Assay[,] <- subset1Assay[,] + 1
    es <- setSubsetAssay(
        es,
        subsetName = "subset1",
        inputMatrix = subset1Assay,
        subsetAssayName = "subset1Assay"
    )
    res_assay <- getSubsetAssay(es, "subset1Assay")


    # --- Metadata Management [] ---
    # Key functions: subsetColData, subsetDim
    subsetColData(es, "subset1") <- cbind(
        subsetColData(es, "subset1"),
        subsetSampleID = seq_len(subsetDim(es, "subset1")[2])
    )
    sub_col_data <- subsetColData(es, "subset1", parentColData = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_experimentsubset_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_experimentsubset_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_experimentsubset_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EXPERIMENTSUBSET:", paste0("    experimentsubset: ", packageVersion("ExperimentSubset"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_experimentsubset_results.csv
    touch ${prefix}_experimentsubset_output.rds
    echo "BIOC_EXPERIMENTSUBSET:" > versions.yml
    echo "    experimentsubset: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EXPERIMENTSUBSET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EXPERIMENTSUBSET(ch_input)

    emit:
    results  = BIOC_EXPERIMENTSUBSET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EXPERIMENTSUBSET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EXPERIMENTSUBSET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EXPERIMENTSUBSET.out.versions  // channel: path(versions.yml)
}
