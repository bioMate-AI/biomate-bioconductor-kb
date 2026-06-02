#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: compcodeR
// This package provides extensive functionality for comparing results obtained by different methods fo
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/compcodeR/inst/doc/compcodeR.R
// Upstream  : ape
// Downstream: none
//
// Install: BiocManager::install("compcodeR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_COMPCODER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-compcoder"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-compcoder:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-compcoder:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_compcoder_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_compcoder_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_compcoder_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(compcodeR)
    library(jsonlite)

    # --- summarize Synthetic Data Set [] ---
    # Key functions: summarizeSyntheticDataSet

    # --- run Diff Exp [] ---
    # Key functions: runDiffExp

    # --- run Comparison G U I [] ---
    # Key functions: runComparisonGUI

    # --- generate Code H T M Ls [] ---
    # Key functions: generateCodeHTMLs
    generateCodeHTMLs("B_625_625_5spc_repl1_ttest.rds", ".")
    # --- run Comparison [] ---
    # Key functions: runComparison

    # --- comp Data [] ---
    # Key functions: compData, check_compData
    count.matrix <- matrix(round(1000*runif(4000)), 1000, 4)
    sample.annot <- data.frame(condition = c(1, 1, 2, 2))
    info.parameters <- list(dataset = "mytestdata", uID = "123456")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_compcoder_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_compcoder_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_compcoder_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_COMPCODER:", paste0("    compcoder: ", packageVersion("compcodeR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_compcoder_results.csv
    touch ${prefix}_compcoder_output.rds
    echo "BIOC_COMPCODER:" > versions.yml
    echo "    compcoder: 0.0.0" >> versions.yml
    """
}


workflow BIOC_COMPCODER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_COMPCODER(ch_input)

    emit:
    results  = BIOC_COMPCODER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_COMPCODER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_COMPCODER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_COMPCODER.out.versions  // channel: path(versions.yml)
}
