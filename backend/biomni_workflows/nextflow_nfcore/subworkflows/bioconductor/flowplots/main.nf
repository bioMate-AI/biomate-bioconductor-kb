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
    library(Group)
    library(GroupListBoxplot)
    library(jsonlite)

    # --- Profbp [] ---
    # Key functions: makeDataList
    data(profileDF)
    profileDataSubset = subset(profileDF, stim=="LPS" & concGroup==3 & cell=="mDC")
    profileDataSubset[1:3,]
    # Use data helper function, makeDataList()
    groupDataList = makeDataList(profileDataSubset ,"group", 1:16)
    # --- Grouplistboxplot [] ---
    # Key functions: GroupListBoxplot
    GroupListBoxplot(groupDataList, xlabel="",
       ylabel="Percent of All Cells", boxOutliers=FALSE,
       xAxisLabels=xTickLabels, xMtext="Marker Category",
       mainTitle="Stimulation = LPS, Concentration Group = 3, Cell = mDC",
       legendGroupNames=c("Adults","Neonates"), pointColor=c(2,4),
    # --- Margbp [] ---
    # Key functions: makeDataList
    data(marginalDF)
    marginalDataSubset = subset(marginalDF, stim=="LPS" & concGroup==3 & cell=="mDC")
    marginalDataSubset[1:3,]
    # Use data helper function, makeDataList()
    groupDataList = makeDataList(marginalDataSubset ,"group", 1:5)
    # --- Grouplistboxplot [] ---
    # Key functions: GroupListBoxplot
    GroupListBoxplot(groupDataList, xlabel="Cytokine",
       ylabel="Percent of All Cells", boxOutliers=FALSE,
       xAxisLabels=c("TNFa","IL6","IL12","IFNa","AnyMarker"),
       mainTitle="Stimulation = LPS, Concentration Group = 3, Cell = mDC",
       legendGroupNames=c("Adults","Neonates"), pointColor=c(2,4),
    # --- Pfdbp [] ---
    # Key functions: makeDataList
    data(pfdDF)
    pfdDataSubset = subset(pfdDF, stim=="LPS" & concGroup==3 & cell=="mDC")
    pfdDataSubset[1:3,]
    # Use data helper function, makeDataList()
    groupDataList = makeDataList(pfdDataSubset ,"group", 1:4)
    # --- Grouplistboxplot [] ---
    # Key functions: GroupListBoxplot
    GroupListBoxplot(groupDataList, xlabel="Cytokine",
       ylabel="Percent of Reactive Cells", boxOutliers=FALSE,
       mainTitle="Stimulation = LPS, Concentration Group = 3, Cell = mDC",
       legendGroupNames=c("Adults","Neonates"), pointColor=c(2,4),
       testTitleCEX=.8, nCEX=.8, pCEX=.8, legendColor=c(2,4), legendCEX=.7)
    # --- make Data List [] ---
    # Key functions: makeDataList
    data(pfdPartsList)
    # Look at the composition percentages for the case where PFD=1
    pfdEq1PartsDataSubset = subset(pfdPartsList[[1]], stim=="LPS" & concGroup==3 & cell=="mDC")
    pfdEq1PartsDataSubset[1:3,]
    # Use data helper function, makeDataList()
    # --- Grouplistboxplot [] ---
    # Key functions: GroupListBoxplot
    GroupListBoxplot(groupDataList, xlabel="Cytokine",
       ylabel="Percent of Cells With PFD=1", boxOutliers=FALSE,
       mainTitle="Stimulation = LPS, Concentration Group = 3, Cell = mDC",
       legendGroupNames=c("Adults","Neonates"), pointColor=c(2,4),
       testTitleCEX=.8, nCEX=.8, pCEX=.8, legendColor=c(2,4), legendCEX=.7)
    # --- make Data List [] ---
    # Key functions: makeDataList
    # Look at the composition percentages for the case where PFD=2
    pfdEq2PartsDataSubset = subset(pfdPartsList[[2]], stim=="LPS" & concGroup==3 & cell=="mDC")
    pfdEq2PartsDataSubset[1:3,]
    # Use data helper function, makeDataList()
    groupDataList = makeDataList(pfdEq2PartsDataSubset, "group", 1:6)
    # --- Grouplistboxplot [] ---
    # Key functions: GroupListBoxplot
    GroupListBoxplot(groupDataList, xlabel="Cytokine",
       ylabel="Percent of Cells With PFD=2", boxOutliers=FALSE,
       mainTitle="Stimulation = LPS, Concentration Group = 3, Cell = mDC",
       legendGroupNames=c("Adults","Neonates"), pointColor=c(2,4),
       testTitleCEX=.8, nCEX=.8, pCEX=.8, legendColor=c(2,4), legendCEX=.7)
    # --- make Data List [] ---
    # Key functions: makeDataList
    # Look at the composition percentages for the case where PFD=3
    pfdEq3PartsDataSubset = subset(pfdPartsList[[3]], stim=="LPS" & concGroup==3 & cell=="mDC")
    pfdEq3PartsDataSubset[1:3,]
    # Use data helper function, makeDataList()
    groupDataList = makeDataList(pfdEq3PartsDataSubset, "group", 1:4)
    # --- Grouplistboxplot [] ---
    # Key functions: GroupListBoxplot
    GroupListBoxplot(groupDataList, xlabel="Cytokine",
       ylabel="Percent of Cells With PFD=3", boxOutliers=FALSE,
       mainTitle="Stimulation = LPS, Concentration Group = 3, Cell = mDC",
       legendGroupNames=c("Adults","Neonates"), pointColor=c(2,4),
       testTitleCEX=.8, nCEX=.8, pCEX=.8, legendColor=c(2,4), legendCEX=.7)
    # --- Ternplot [] ---
    # Key functions: makeTernaryData, computePFDGroupStatsList, legendPFDStatsGroupNames
    data(pfdDF)
    pfdDataSubset = subset(pfdDF, stim=="LPS" & concGroup==3 & cell=="mDC")
    # Use data helper function, makeTernaryData()
    ternaryData = makeTernaryData(pfdDataSubset, 1, 2, 3:4)
    colnames(ternaryData) = c("PFD1", "PFD2", "PFD3-4")
    # --- Ternaryplot [] ---
    # Key functions: ternaryplot, grid_legend, Group, gpar
    # Load the package, vcd, for the ternaryplot() fcn
    library(vcd)
    ternaryplot(ternaryData, cex=.5, col=as.numeric(pfdDataSubset$group)*2,
       main="TERNARY PLOT OF PFD DATA,
    Stimulation = LPS, Concentration Group = 3, Cell = mDC")
    # --- Barplot [] ---
    # Key functions: makeBarplotData, gray
    data(profileDF)
    profileDataSubset = subset(profileDF, stim=="LPS" & concGroup==3 & cell=="mDC")
    profileColumns = 1:16
    # Use data helper function, makeBarplotData()
    barplotData = makeBarplotData(profileDataSubset, profileColumns, groupVariableName="group")

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
