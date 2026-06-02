#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TCC
// This package provides a series of functions for performing differential expression analysis from RNA
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TCC/inst/doc/TCC.R
// Upstream  : ROC
// Downstream: none
//
// Install: BiocManager::install("TCC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TCC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tcc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tcc:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tcc:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(model_object)

    output:
    tuple val(meta), path("${meta.id}_tcc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tcc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tcc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TCC)
    library(AUC)
    library(DESeqDataSetFromMatrix)
    library(DGEList)
    library(jsonlite)

    # --- Robust Normalization [] ---
    # Key functions: calcNormFactors
    tcc <- calcNormFactors(
        tcc,
        norm.method = "tmm",
        test.method = "edger",
        iteration = 3,
        FDR = 0.1,
        floorPDEG = 0.05
    )


    # --- Differential Expression Analysis [] ---
    # Key functions: estimateDE
    tcc <- estimateDE(
        tcc,
        test.method = "edger",
        FDR = 0.1
    )


    # --- Result Extraction and Sorting [] ---
    # Key functions: getResult
    result <- getResult(
        tcc,
        sort = TRUE
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tcc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tcc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tcc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TCC:", paste0("    tcc: ", packageVersion("TCC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tcc_results.csv
    touch ${prefix}_tcc_output.rds
    echo "BIOC_TCC:" > versions.yml
    echo "    tcc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TCC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(model_object) ]

    main:
    BIOC_TCC(ch_input)

    emit:
    results  = BIOC_TCC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TCC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TCC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TCC.out.versions  // channel: path(versions.yml)
}
