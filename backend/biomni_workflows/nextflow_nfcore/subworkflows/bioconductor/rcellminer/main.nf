#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rcellminer
// The NCI-60 cancer cell line panel has been used over the course of several decades as an anti-cancer
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rcellminer/inst/doc/rcellminerUsage.R
// Upstream  : knitr, rcellminerData
// Downstream: none
//
// Install: BiocManager::install("rcellminer")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RCELLMINER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rcellminer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rcellminer:2.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rcellminer:2.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rcellminer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rcellminer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rcellminer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(rcellminer)
    library(jsonlite)


    # --- Search For Nscs [] ---
    # Key functions: searchForNscs, exprs, getAct, getMolDataMatrices, plotCellMiner, drug, mut, cop
    searchForNscs("nib$")
    # Get Cellminer data
    drugAct <- exprs(getAct(rcellminerData::drugData))
    molData <- getMolDataMatrices()

    # One drug
    nsc <- "94600"
    plots <- c("drug") 
    plotCellMiner(drugAct, molData, plots, nsc, NULL)

    # One expression

    # --- Plot Drug Sets [] ---
    # Key functions: exprs, getAct, searchForNscs, plotDrugSets, camptothecin, getFeatureAnnot, drug
    # Get CellMiner data
    drugAct <- exprs(getAct(rcellminerData::drugData))

    drugs <- as.character(searchForNscs("camptothecin"))
    drugAct <- drugAct[drugs,]
    mainLabel <- paste("Drug Set: Camptothecin Derivatives, Drugs:", length(drugs), sep=" ")

    plotDrugSets(drugAct, drugs, mainLabel)
    drugAnnot <- getFeatureAnnot(rcellminerData::drugData)[["drug"]]
    drugAnnot[1:5, "SMILES"]

    # --- Make Drug Info Table [] ---
    # Key functions: getFeatureAnnot, drugs, experiments, getMoaToCompounds, drug, drugRepeat, getDrugActivityData
    # getFeatureAnnot() returns a named list of data frames with annotation data 
    # for drugs ("drug") and drug activity repeat experiments ("drugRepeat").
    drugAnnot <- getFeatureAnnot(rcellminerData::drugData)[["drug"]]

    # Get the names and MOA for compounds with MOA entries
    knownMoaDrugs <- unique(c(getMoaToCompounds(), recursive = TRUE))
    knownMoaDrugInfo <- data.frame(NSC=knownMoaDrugs, stringsAsFactors = FALSE)
    knownMoaDrugInfo$Name <- drugAnnot[knownMoaDrugInfo$NSC, "NAME"]

    # Process all NSCs 
    negLogGI50Data <- getDrugActivityData(nscSet = knownMoaDrugInfo$NSC)

    gi50Data <- 10^(-negLogGI50Data)

    # --- Make Integrated Table [] ---
    # Key functions: write.table, knownMoaDrugAct.txt, exprs, getAct, getMolDataMatrices, rep, Reduce, Composite
    knownMoaDrugAct <- as.data.frame(cbind(knownMoaDrugInfo, gi50Data), stringsAsFactors = FALSE)

    # This table can be written out to a file
    #write.table(knownMoaDrugAct, file="knownMoaDrugAct.txt", quote=FALSE, sep="\t", row.names=FALSE, col.names=TRUE, na="NA")
    # Gene of interest
    gene <- "PTEN"

    # Get Data
    drugAct <- exprs(getAct(rcellminerData::drugData))
    molData <- getMolDataMatrices()

    # Get the cell lines names for cell lines meeting particular thresholds
    copKnockdown <- names(which(molData[["cop"]][paste0("cop", gene), ] < -1))
    expKnockdown <- names(which(molData[["exp"]][paste0("exp", gene), ] < -1.5))

    # --- Varma2014 [] ---
    # Key functions: getMolDataMatrices, removeMolDataType, rowCors, segments, text, rug, cop, lightgray
    molData <- getMolDataMatrices()

    # Get Data
    copGenes <- removeMolDataType(rownames(molData[["cop"]]))
    expGenes <- removeMolDataType(rownames(molData[["exp"]]))
    genes <- intersect(copGenes, expGenes)

    # Generate the appropriate rownames 
    expGeneLabels <- paste0("exp", genes)
    copGeneLabels <- paste0("cop", genes)
    # Get normalized (Z-score) NCI-60 gene expression and drug activity data.
    nci60DrugActZ <- exprs(getAct(rcellminerData::drugData))
    nci60GeneExpZ <- getAllFeatureData(rcellminerData::molData)[["exp"]]

    # --- Plot Cpt Activity Vs Gene Exp [] ---
    # Key functions: loadNciColorSet, Activity, Expression, abline, formula, tissues, colors, red
    colorTab <- loadNciColorSet(returnDf = TRUE)
    tissueColorTab <- unique(colorTab[, c("tissues", "colors")])

    plotData <- as.data.frame(t(rbind(nci60DrugActZ[camptothecinNsc, , drop=FALSE], 
    																	nci60GeneExpZ[c("TMBIM1", "BCL2L2"), ])))
    colnames(plotData) <- c("Camptothecin", "TMBIM1", "BCL2L2")


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rcellminer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rcellminer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rcellminer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RCELLMINER:", paste0("    rcellminer: ", packageVersion("rcellminer"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rcellminer_results.csv
    touch ${prefix}_rcellminer_output.rds
    echo "BIOC_RCELLMINER:" > versions.yml
    echo "    rcellminer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RCELLMINER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RCELLMINER(ch_input)

    emit:
    results  = BIOC_RCELLMINER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RCELLMINER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RCELLMINER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RCELLMINER.out.versions  // channel: path(versions.yml)
}
