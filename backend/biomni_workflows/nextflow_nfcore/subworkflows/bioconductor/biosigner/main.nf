#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: biosigner
// Feature selection is critical in omics data analysis to extract restricted and meaningful molecular 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/biosigner/inst/doc/biosigner-vignette.R
// Upstream  : BioMark, Biobase, MultiAssayExperiment, SummarizedExperiment, golubEsets
// Downstream: none
//
// Install: BiocManager::install("biosigner")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOSIGNER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biosigner"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biosigner:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-biosigner:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biosigner_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biosigner_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biosigner_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(biosigner)
    library(jsonlite)


    # --- Diaplasma [] ---
    # Key functions: attach, view, with, ifelse, blue, red, topleft, mzmed
    data(diaplasma)
    attach(diaplasma)
    library(ropls)
    ropls::view(dataMatrix)
    ropls::view(sampleMetadata, standardizeL = TRUE)
    ropls::view(variableMetadata, standardizeL = TRUE)
    with(sampleMetadata,
    plot(age, bmi, cex = 1.5, col = ifelse(type == "T1", "blue", "red"), pch = 16))
    legend("topleft", cex = 1.5, legend = paste0("T", 1:2),
    text.col = c("blue", "red"))
    featureSelVl <- variableMetadata[, "mzmed"] >= 450 &
    variableMetadata[, "mzmed"] < 500
    sum(featureSelVl)
    dataMatrix <- dataMatrix[, featureSelVl]
    variableMetadata <- variableMetadata[featureSelVl, ]
    diaSign <- biosign(dataMatrix, sampleMetadata[, "type"], bootI = 5)
    plot(diaSign, typeC = "boxplot")

    # --- Signature [] ---
    # Key functions: getSignatureLs, complete, biosign, type, predict, function, sweep, rowSums
    variableMetadata[getSignatureLs(diaSign)[["complete"]], ]
    trainVi <- 1:floor(0.8 * nrow(dataMatrix))
    testVi <- setdiff(1:nrow(dataMatrix), trainVi)
    diaTrain <- biosign(dataMatrix[trainVi, ], sampleMetadata[trainVi, "type"],
    bootI = 5)
    diaFitDF <- predict(diaTrain)
    lapply(diaFitDF, function(predFc) table(actual = sampleMetadata[trainVi,
    "type"], predicted = predFc))
    sapply(diaFitDF, function(predFc) {
    conf <- table(sampleMetadata[trainVi, "type"], predFc)
    conf <- sweep(conf, 1, rowSums(conf), "/")
    round(mean(diag(conf)), 3)
    })

    # --- Get Accuracy [] ---
    # Key functions: getAccuracyMN, predict, function, sweep, rowSums, diag, type, metadata
    round(getAccuracyMN(diaTrain)["S", ], 3)
    diaTestDF <- predict(diaTrain, newdata = dataMatrix[testVi, ])
    sapply(diaTestDF, function(predFc) {
    conf <- table(sampleMetadata[testVi, "type"], predFc)
    conf <- sweep(conf, 1, rowSums(conf), "/")
    round(mean(diag(conf)), 3)
    })
    # Preparing the data (matrix) and sample and variable metadata (data frames):
    data(diaplasma)
    data.mn <- diaplasma[["dataMatrix"]] # matrix: samples x variables
    samp.df <- diaplasma[["sampleMetadata"]] # data frame: samples x sample metadata
    feat.df <- diaplasma[["variableMetadata"]] # data frame: features x feature metadata

    # Creating the SummarizedExperiment (package SummarizedExperiment)
    library(SummarizedExperiment)
    # --- Get Eset [] ---
    # Key functions: metadata, SummarizedExperiment, ExpressionSet, pData, fData, stopifnot, validObject, view
    # Preparing the data (matrix) and sample and variable metadata (data frames):
    data(diaplasma)
    data.mn <- diaplasma[["dataMatrix"]] # matrix: samples x variables
    samp.df <- diaplasma[["sampleMetadata"]] # data frame: samples x sample metadata
    feat.df <- diaplasma[["variableMetadata"]] # data frame: features x feature metadata

    # Creating the SummarizedExperiment (package SummarizedExperiment)
    library(Biobase)
    dia.eset <- Biobase::ExpressionSet(assayData = t(data.mn))
    Biobase::pData(dia.eset) <- samp.df
    dia.eset <- dia.eset[1:100, ]
    dia_type.biosign <- biosign(dia.eset, "type", bootI = 5)
    plot(dia_type.biosign, typeC = "tier")
    dia.eset <- getEset(dia_type.biosign)
    feat.df <- Biobase::fData(dia.eset)
    head(feat.df[, grep("type_", colnames(feat.df))])
    detach(diaplasma)
    data("NCI60", package = "ropls")
    nci.mae <- NCI60[["mae"]]
    library(MultiAssayExperiment)

    # --- Mae Biosign [] ---
    # Key functions: biosign, cancer, rowData, agilent, getBiosign, for, cancer_plsda.forest.svm, tier
    nci.mae <- biosign(nci.mae, "cancer", bootI = 5)
    SummarizedExperiment::rowData(nci.mae[["agilent"]])
    mae_biosign.ls <- getBiosign(nci.mae)
    for (set.c in names(mae_biosign.ls))
    plot(mae_biosign.ls[[set.c]][["cancer_plsda.forest.svm"]],
         typeC = "tier",
         plotSubC = set.c)
    data("NCI60", package = "ropls")
    nci.mds <- NCI60[["mds"]]
    # Restricting to the "agilent" and "hgu95" datasets
    nci.mds <- nci.mds[, c("agilent", "hgu95")]
    # Restricting to the 'ME' and 'LE' cancer types
    library(Biobase)
    sample_names.vc <- Biobase::sampleNames(nci.mds[["agilent"]])
    cancer_type.vc <- Biobase::pData(nci.mds[["agilent"]])[, "cancer"]
    nci.mds <- nci.mds[sample_names.vc[cancer_type.vc %in% c("ME", "LE")], ]
    # Selecting the features
    nci_cancer.biosign <- biosign(nci.mds, "cancer", bootI = 5)
    nci.mds <- getMset(nci_cancer.biosign)

    # --- Sacurine [] ---
    # Key functions: biosign, dataMatrix, sampleMetadata, gender, plsda, classes, control, group1
    data(sacurine)
    sacSign <- biosign(sacurine[["dataMatrix"]],
    sacurine[["sampleMetadata"]][, "gender"],
    methodVc = "plsda")
    library(BioMark)
    data(SpikePos)
    group1Vi <- which(SpikePos[["classes"]] %in% c("control", "group1"))
    appleMN <- SpikePos[["data"]][group1Vi, ]
    spikeFc <- factor(SpikePos[["classes"]][group1Vi])
    annotDF <- SpikePos[["annotation"]]
    rownames(annotDF) <- colnames(appleMN)
    biomark.pca <- ropls::opls(appleMN, fig.pdfC = "none")
    ropls::plot(biomark.pca, parAsColFcVn = spikeFc)
    biomark.pls <- ropls::opls(appleMN, spikeFc)
    appleSign <- biosign(appleMN, spikeFc)
    annotDF <- SpikePos[["annotation"]]
    rownames(annotDF) <- colnames(appleMN)
    annotDF[getSignatureLs(appleSign)[["complete"]], c("adduct", "found.in.standards")]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biosigner_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biosigner_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biosigner_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIOSIGNER:", paste0("    biosigner: ", packageVersion("biosigner"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biosigner_results.csv
    touch ${prefix}_biosigner_output.rds
    echo "BIOC_BIOSIGNER:" > versions.yml
    echo "    biosigner: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIOSIGNER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIOSIGNER(ch_input)

    emit:
    results  = BIOC_BIOSIGNER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIOSIGNER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIOSIGNER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIOSIGNER.out.versions  // channel: path(versions.yml)
}
