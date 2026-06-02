#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MSstatsTMT
// The package provides statistical tools for detecting differentially abundant proteins in shotgun mas
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MSstatsTMT/inst/doc/MSstatsTMT.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MSstatsTMT")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSSTATSTMT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-msstatstmt"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-msstatstmt:2.14.2--r44_0' :
        'quay.io/biocontainers/bioconductor-msstatstmt:2.14.2--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_msstatstmt_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_msstatstmt_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_msstatstmt_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MaxQtoMSstatsTMTFormat)
    library(OpenMStoMSstatsTMTFormat)
    library(PDtoMSstatsTMTFormat)
    library(SpectroMinetoMSstatsTMTFormat)
    library(jsonlite)

    # --- Delim [] ---
    # Key functions: delim, csv, PDtoMSstatsTMTFormat
    ---------------------------------------------------------------------
    # read in PD PSM sheet
    # raw.pd <- read.delim("161117_SILAC_HeLa_UPS1_TMT10_5Mixtures_3TechRep_UPSdB_Multiconsensus_PD22_Intensity_PSMs.txt")
    head(raw.pd)
    # Read in annotation including condition and biological replicates per run and channel.
    # --- Table [] ---
    # Key functions: csv, MaxQtoMSstatsTMTFormat
    ---------------------------------------------------------------------
    # Read in MaxQuant files
    # proteinGroups <- read.table("proteinGroups.txt", sep="\t", header=TRUE)
    # evidence <- read.table("evidence.txt", sep="\t", header=TRUE)
    # Users should make this annotation file. It is not the output from MaxQuant.
    # --- Csv [] ---
    # Key functions: csv, SpectroMinetoMSstatsTMTFormat
    ---------------------------------------------------------------------
    # Read in SpectroMine PSM report
    # raw.mine <- read.csv('20180831_095547_CID-OT-MS3-Short_PSM Report_20180831_103118.xls', sep="\t")
    # Users should make this annotation file. It is not the output from SpectroMine
    # annotation.mine <- read.csv(file="Mine_Annotation.csv", header=TRUE)
    # --- Csv [] ---
    # Key functions: csv, OpenMStoMSstatsTMTFormat
    ---------------------------------------------------------------------
    # read in MSstatsTMT report from OpenMS
    # raw.om <- read.csv("OpenMS_20200222/20200225_MSstatsTMT_OpenMS_Export.csv")
    head(raw.om)
    # the function only requries one input file
    # --- Dataprocessplotstmt [] ---
    # Key functions: dataProcessPlotsTMT
    ---------------------------------------------------------------------
    ## Quality control plot
    # dataProcessPlotsTMT(data=quant.msstats,
                         # type='QCPlot',
                         # width = 21, # adjust the figure width since there are 15 TMT runs.
    # --- Conditions [] ---
    # Key functions: conditions
    ---------------------------------------------------------------------
    # Show test result
    # Label : which comparison is used
    # log2FC : estimated log2 fold change between two conditions (the contrast)
    # adj.pvalue : adjusted p value
    # --- Levels [] ---
    # Key functions: levels
    ---------------------------------------------------------------------
    # Check the conditions in the protein level data
    levels(quant.msstats$ProteinLevelData$Condition)
    # Only compare condition 0.125 and 1
    comparison<-matrix(c(-1,0,0,1),nrow=1)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_msstatstmt_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_msstatstmt_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_msstatstmt_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSSTATSTMT:", paste0("    msstatstmt: ", packageVersion("MSstatsTMT"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msstatstmt_results.csv
    touch ${prefix}_msstatstmt_output.rds
    echo "BIOC_MSSTATSTMT:" > versions.yml
    echo "    msstatstmt: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSSTATSTMT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_MSSTATSTMT(ch_input)

    emit:
    results  = BIOC_MSSTATSTMT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSSTATSTMT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSSTATSTMT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSSTATSTMT.out.versions  // channel: path(versions.yml)
}
