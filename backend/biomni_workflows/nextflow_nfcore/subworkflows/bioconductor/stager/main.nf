#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: stageR
// The stageR package allows automated stage-wise analysis of high-throughput gene expression data. The
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/stageR/inst/doc/stageRVignette.R
// Upstream  : Biobase, DEXSeq, edgeR, limma, utils
// Downstream: rnaseqDTU
//
// Install: BiocManager::install("stageR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_STAGER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-stager"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-stager:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-stager:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_stager_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_stager_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_stager_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DEXSeqDataSet)
    library(DGEList)
    library(TestResults)
    library(jsonlite)

    # --- Pdata [] ---
    # Key functions: pData, factor
    ---------------------------------------------------------------------
    pData(eset)$Time #typo. Will do it ourself
    time <- factor(rep(c("mo2","w2"),each=4),levels=c("w2","mo2"))
    pData(eset)$protocol
    treat <- factor(c("control","control","SNL","SNL","control","control","SNL","SNL"),levels=c("control","SNL"))
    # --- Rowsums [] ---
    # Key functions: rowSums, cpm, exprs, DGEList, calcNormFactors
    ---------------------------------------------------------------------
    cpmOffset <- 2
    keep <- rowSums(cpm(exprs(eset))>cpmOffset)>=2 #2cpm in 2 samples
    dge <- DGEList(exprs(eset)[keep,])
    colnames(dge) = rownames(design)
    # --- Voom [] ---
    # Key functions: voom, lmFit, makeContrasts, fit, eBayes, decideTests, TestResults, colSums
    ---------------------------------------------------------------------
    ## regular analysis
    voomObj <- voom(dge,design,plot=TRUE)
    fit <- lmFit(voomObj,design)
    contrast.matrix <- makeContrasts(treatSNL, treatSNL+timeMo2xTreatSNL, timeMo2xTreatSNL, levels=design)
    # --- Nrow [] ---
    # Key functions: topTableF
    ---------------------------------------------------------------------
    alpha <- 0.05
    nGenes <- nrow(dge)
    tableF <- topTableF(fit2, number=nGenes, sort.by="none") #screening hypothesis
    pScreen <- tableF$P.Value
    # --- Sapply [] ---
    # Key functions: topTable, dimnames, stageR
    ---------------------------------------------------------------------
    pConfirmation <- sapply(1:3,function(i) topTable(fit2, coef=i, number=nGenes, sort.by="none")$P.Value)
    dimnames(pConfirmation) <- list(rownames(fit2),c("t1","t2","t1t2"))
    stageRObj <- stageR(pScreen=pScreen, pConfirmation=pConfirmation, pScreenAdjusted=FALSE)
    # --- Stagewiseadjustment [] ---
    # Key functions: stageWiseAdjustment
    ---------------------------------------------------------------------
    stageRObj <- stageWiseAdjustment(object=stageRObj, method="none", alpha=0.05)
    # --- Head [] ---
    # Key functions: getAdjustedPValues
    ---------------------------------------------------------------------
    head(getAdjustedPValues(stageRObj, onlySignificantGenes=FALSE, order=FALSE))
    head(getAdjustedPValues(stageRObj, onlySignificantGenes=TRUE, order=TRUE))
    # --- Getresults [] ---
    # Key functions: getResults, colSums
    ---------------------------------------------------------------------
    res <- getResults(stageRObj)
    head(res)
    colSums(res) #stage-wise analysis results
    # --- Stager [] ---
    # Key functions: stageR, stageWiseAdjustment, getResults, colSums
    ---------------------------------------------------------------------
    stageRObj <- stageR(pScreen=pScreen, pConfirmation=pConfirmation, pScreenAdjusted=FALSE)
    adjustedPSW <- stageWiseAdjustment(object=stageRObj, method="user", alpha=0.05, adjustment=c(1,1,1))
    res <- getResults(adjustedPSW)
    colSums(res)
    # --- Data [] ---
    # Key functions: pData, fData
    ---------------------------------------------------------------------
    data("esetProstate", package="stageR") #from stageR package
    head(pData(esetProstate))
    head(fData(esetProstate))
    # --- Fdata [] ---
    # Key functions: fData
    ---------------------------------------------------------------------
    tx2gene <- fData(esetProstate)
    colnames(tx2gene) <- c("transcript","gene")
    barplot(table(table(tx2gene$gene)), main="Distribution of number of tx per gene")
    #the dataset contains
    # --- Pdata [] ---
    # Key functions: pData, exprs, DEXSeqDataSet, estimateSizeFactors, estimateDispersions
    ---------------------------------------------------------------------
    ### regular DEXSeq analysis
    sampleData <- pData(esetProstate)
    geneForEachTx <- tx2gene[match(rownames(exprs(esetProstate)),tx2gene[,1]),2]
    dxd <- DEXSeqDataSet(countData = exprs(esetProstate),
    # --- Matrix [] ---
    # Key functions: dimnames, fData
    ---------------------------------------------------------------------
    pConfirmation <- matrix(dxr$pvalue,ncol=1)
    dimnames(pConfirmation) <- list(c(dxr$featureID),c("transcript"))
    pScreen <- qvalDxr
    tx2gene <- fData(esetProstate)
    # --- Stagertx [] ---
    # Key functions: stageRTx, stageWiseAdjustment
    ---------------------------------------------------------------------
    stageRObj <- stageRTx(pScreen=pScreen, pConfirmation=pConfirmation, pScreenAdjusted=TRUE, tx2gene=tx2gene)
    stageRObj <- stageWiseAdjustment(object=stageRObj, method="dtu", alpha=0.05)
    # --- Head [] ---
    # Key functions: getSignificantGenes
    ---------------------------------------------------------------------
    head(getSignificantGenes(stageRObj))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_stager_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_stager_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_stager_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_STAGER:", paste0("    stager: ", packageVersion("stageR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_stager_results.csv
    touch ${prefix}_stager_output.rds
    echo "BIOC_STAGER:" > versions.yml
    echo "    stager: 0.0.0" >> versions.yml
    """
}


workflow BIOC_STAGER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_STAGER(ch_input)

    emit:
    results  = BIOC_STAGER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_STAGER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_STAGER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_STAGER.out.versions  // channel: path(versions.yml)
}
