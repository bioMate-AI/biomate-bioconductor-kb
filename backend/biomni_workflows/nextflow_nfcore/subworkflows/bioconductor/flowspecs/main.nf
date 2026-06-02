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

    # --- Samplenames [] ---
    # Key functions: sampleNames
    ---------------------------------------------------------------------
    sampleNames(unmixCtrls)
    # --- Specmatcalc [] ---
    # Key functions: specMatCalc
    ---------------------------------------------------------------------
    specMat <- specMatCalc(unmixCtrls, groupNames = c("Beads_", "Dead_"),
                            autoFluoName = "PBMC_unstained.fcs")
    str(specMat)
    # --- Specunmix [] ---
    # Key functions: specUnmix
    ---------------------------------------------------------------------
    fullPanelUnmix <- specUnmix(fullPanel, specMat)
    fullPanelUnmix
    # --- Arctrans [] ---
    # Key functions: arcTrans, exprs
    ---------------------------------------------------------------------
    fullPanelTrans <- arcTrans(fullPanelUnmix, transNames =
                                colnames(fullPanelUnmix)[6:18])
    par(mfrow=c(1,2))
    # --- Onevsallplot [] ---
    # Key functions: oneVsAllPlot
    ---------------------------------------------------------------------
    oneVsAllPlot(fullPanelTrans, "AF647_IgM", saveResult = FALSE)
    # --- Corrmatcreate [] ---
    # Key functions: corrMatCreate
    ---------------------------------------------------------------------
    corrMat <- corrMatCreate(specMat)
    # --- Correctunmix [] ---
    # Key functions: correctUnmix, oneVsAllPlot
    ---------------------------------------------------------------------
    corrMat["BV650_CD56", "AF647_IgM"] <- -0.1
    fullPanelCorr <- correctUnmix(fullPanelUnmix, corrMat)
    oneVsAllPlot(fullPanelCorr, "AF647_IgM", saveResult = FALSE)
    # --- Flowset [] ---
    # Key functions: flowSet, sampleNames
    ---------------------------------------------------------------------
    fullPanelFs <- flowSet(fullPanelTrans)
    sampleNames(fullPanelFs) <- "PBMC_full_panel_d1.fcs"
    # --- flow Set2 Long Df [] ---
    # Key functions: flowSet2LongDf
    ---------------------------------------------------------------------
    fullPanelDf <- flowSet2LongDf(fullPanelFs, idInfo =
            list("Tissue" = "|_full_panel_..\\.fcs",
                 "Donor" = "...._full_panel_|\\.fcs"))
    str(fullPanelDf)

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
