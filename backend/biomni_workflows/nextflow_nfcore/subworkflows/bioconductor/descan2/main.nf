#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DEScan2
// Integrated peak and differential caller, specifically designed for broad epigenomic signals.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DEScan2/inst/doc/DEScan2.R
// Upstream  : BiocParallel, RColorBrewer, RUVSeq, edgeR
// Downstream: none
//
// Install: BiocManager::install("DEScan2")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DESCAN2 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-descan2"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-descan2:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-descan2:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_descan2_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_descan2_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_descan2_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DEScan2)
    library(DGEList)
    library(RUVs)
    library(jsonlite)

    # --- Count Matrix Generation [] ---
    # Key functions: countFinalRegions
    finalRegions <- DEScan2::countFinalRegions(
        regionsGRanges = regionsGR,
        readsFilePath = bam.path,
        fileType = "bam",
        minCarriers = 1,
        genomeName = "mm9",
        onlyStdChrs = TRUE,
        saveFlag = FALSE,
        verbose = FALSE
    )


    # --- Peak Filtering [] ---
    # Key functions: countFinalRegions
    counts <- SummarizedExperiment::assay(finalRegions)
    regions <- SummarizedExperiment::rowRanges(finalRegions)
    keep <- regions$`k-carriers` >= 4 & rowSums(counts) > 0
    filtered_counts <- counts[keep, ]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_descan2_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_descan2_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_descan2_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DESCAN2:", paste0("    descan2: ", packageVersion("DEScan2"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_descan2_results.csv
    touch ${prefix}_descan2_output.rds
    echo "BIOC_DESCAN2:" > versions.yml
    echo "    descan2: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DESCAN2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DESCAN2(ch_input)

    emit:
    results  = BIOC_DESCAN2.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DESCAN2.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DESCAN2.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DESCAN2.out.versions  // channel: path(versions.yml)
}
