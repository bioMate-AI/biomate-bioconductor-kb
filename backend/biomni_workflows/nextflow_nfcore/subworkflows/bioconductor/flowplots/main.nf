#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: flowPlots
// Graphical displays with embedded statistical tests for gated ICS flow cytometry data, and a data cla
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/flowPlots/inst/doc/flowPlots.R
// Upstream  : vcd
// Downstream: none
//
// Install: BiocManager::install("flowPlots")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWPLOTS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-flowplots"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-flowplots:1.54.0--r44_0' :
        'quay.io/biocontainers/bioconductor-flowplots:1.54.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_flowplots_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_flowplots_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_flowplots_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(flowPlots)
    library(Group)
    library(GroupListBoxplot)
    library(jsonlite)

    # --- Profile and Marginal Data Computation [] ---
    # Key functions: computeProfileData, profileData<-, computeMarginalData, marginalData<-
    byVarNames = c("stim", "concGroup", "cell")
    profileData = computeProfileData(
        stackedDataObject, byVarNames, "id", "percentAll", "group"
    )
    profileData(stackedDataObject) = profileData
    marginalData = computeMarginalData(
        stackedDataObject, byVarNames, "id", "percentAll", "group"
    )
    marginalData(stackedDataObject) = marginalData


    # --- Polyfunctional Degree Data Computation [] ---
    # Key functions: computePFDData, pfdData<-, computePFDPartsData, pfdPartsData<-
    byVarNames = c("stim", "concGroup", "cell")
    pfdData = computePFDData(
        stackedDataObject, byVarNames, "id", "percentAll", "group"
    )
    pfdData(stackedDataObject) = pfdData
    pfdPartsData = computePFDPartsData(
        stackedDataObject, byVarNames, "id", "percentAll", "group"
    )
    pfdPartsData(stackedDataObject) = pfdPartsData


    # --- Data Preparation for Visualization [] ---
    # Key functions: makeDataList, makeTernaryData, makeBarplotData
    data(profileDF)
    profileDataSubset = subset(
        profileDF, stim == "LPS" & concGroup == 3 & cell == "mDC"
    )
    groupDataList = makeDataList(profileDataSubset, "group", 1:16)
    ternaryData = makeTernaryData(profileDataSubset, 1, 2, 3:4)
    barplotData = makeBarplotData(
        profileDataSubset, 1:16, groupVariableName = "group"
    )


    # --- PFD Group Statistics and Legend Generation [] ---
    # Key functions: computePFDGroupStatsList, legendPFDStatsGroupNames
    data(pfdDF)
    pfdDataSubset = subset(
        pfdDF, stim == "LPS" & concGroup == 3 & cell == "mDC"
    )
    adultPFDData = subset(pfdDataSubset, group == "adult", select = PFD1:PFD4)
    neoPFDData = subset(pfdDataSubset, group == "neonate", select = PFD1:PFD4)
    groupPFDDataList = list(adultPFDData, neoPFDData)
    pfdGroupStatsList = computePFDGroupStatsList(
        groupPFDDataList, pfdValues = 1:4, numDigitsMean = 3, numDigitsSD = 2
    )
    groupNames = c("Adults", "Neonates")
    legendNames = legendPFDStatsGroupNames(pfdGroupStatsList, groupNames)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_flowplots_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_flowplots_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_flowplots_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FLOWPLOTS:", paste0("    flowplots: ", packageVersion("flowPlots"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowplots_results.csv
    touch ${prefix}_flowplots_output.rds
    echo "BIOC_FLOWPLOTS:" > versions.yml
    echo "    flowplots: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FLOWPLOTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FLOWPLOTS(ch_input)

    emit:
    results  = BIOC_FLOWPLOTS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FLOWPLOTS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FLOWPLOTS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FLOWPLOTS.out.versions  // channel: path(versions.yml)
}
