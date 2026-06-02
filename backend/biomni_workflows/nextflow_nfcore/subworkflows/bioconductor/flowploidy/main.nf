#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: flowPloidy
// Determine sample ploidy via flow cytometry histogram analysis. Reads Flow Cytometry Standard (FCS) f
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/flowPloidy/inst/doc/flowPloidy-gettingStarted.R
// Upstream  : devtools, flowPloidyData
// Downstream: none
//
// Install: BiocManager::install("flowPloidy")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWPLOIDY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-flowploidy"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-flowploidy:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-flowploidy:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_flowploidy_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_flowploidy_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_flowploidy_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(flowPloidy)
    library(jsonlite)


    # --- View Flow Channel [] ---
    # Key functions: viewFlowChannels, flowPloidyFiles, viewFlowcChannels
    viewFlowChannels(flowPloidyFiles()[1])
    ## or viewFlowcChannels("my-flow-file.LMD")

    # --- Batch Flow Hist [] ---
    # Key functions: batchFlowHist, flowPloidyFiles
    batch1 <- batchFlowHist(flowPloidyFiles(), channel = "FL3.INT.LIN")

    # --- Tabulate Flow Hist [] ---
    # Key functions: tabulateFlowHist
    tabulateFlowHist(batch1)[1:4, ]

    # --- Vac Channel [] ---
    # Key functions: viewFlowChannels, fpVac
    viewFlowChannels(fpVac())

    # --- Read Vac [] ---
    # Key functions: batchFlowHist, fpVac
    vac <- batchFlowHist(fpVac(), channel = "FL2.A")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_flowploidy_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_flowploidy_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_flowploidy_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FLOWPLOIDY:", paste0("    flowploidy: ", packageVersion("flowPloidy"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowploidy_results.csv
    touch ${prefix}_flowploidy_output.rds
    echo "BIOC_FLOWPLOIDY:" > versions.yml
    echo "    flowploidy: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FLOWPLOIDY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FLOWPLOIDY(ch_input)

    emit:
    results  = BIOC_FLOWPLOIDY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FLOWPLOIDY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FLOWPLOIDY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FLOWPLOIDY.out.versions  // channel: path(versions.yml)
}
