#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: flowSpecs
// This package is intended to fill the role of conventional cytometry pre-processing software, for spe
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/flowSpecs/inst/doc/flowSpecs_vinjette.R
// Upstream  : flowCore
// Downstream: none
//
// Install: BiocManager::install("flowSpecs")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWSPECS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-flowspecs"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-flowspecs:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-flowspecs:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_flowspecs_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_flowspecs_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_flowspecs_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(flowSpecs)
    library(jsonlite)

    # --- Spectral Unmixing [] ---
    # Key functions: specUnmix
    data("fullPanel")
    fullPanelUnmix <- specUnmix(fullPanel, specMat)


    # --- Arc-sinh Transformation [] ---
    # Key functions: arcTrans
    trans_cols <- colnames(fullPanelUnmix)[6:18]
    fullPanelTrans <- arcTrans(
        fullPanelUnmix,
        transNames = trans_cols
    )


    # --- Spillover Correction [] ---
    # Key functions: corrMatCreate, correctUnmix
    corrMat <- corrMatCreate(specMat)
    corrMat["BV650_CD56", "AF647_IgM"] <- -0.1
    fullPanelCorr <- correctUnmix(fullPanelUnmix, corrMat)


    # --- Data Conversion [] ---
    # Key functions: flowSet2LongDf
    fullPanelFs <- flowCore::flowSet(fullPanelTrans)
    flowCore::sampleNames(fullPanelFs) <- "PBMC_full_panel_d1.fcs"
    fullPanelDf <- flowSet2LongDf(
        fullPanelFs,
        idInfo = list(
            "Tissue" = "|_full_panel_..\\.fcs",
            "Donor" = "...._full_panel_|\\.fcs"
        )
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_flowspecs_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_flowspecs_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_flowspecs_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FLOWSPECS:", paste0("    flowspecs: ", packageVersion("flowSpecs"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowspecs_results.csv
    touch ${prefix}_flowspecs_output.rds
    echo "BIOC_FLOWSPECS:" > versions.yml
    echo "    flowspecs: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FLOWSPECS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FLOWSPECS(ch_input)

    emit:
    results  = BIOC_FLOWSPECS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FLOWSPECS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FLOWSPECS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FLOWSPECS.out.versions  // channel: path(versions.yml)
}
