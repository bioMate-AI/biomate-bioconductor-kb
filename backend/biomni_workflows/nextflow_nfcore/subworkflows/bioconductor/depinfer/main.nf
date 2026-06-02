#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DepInfeR
// DepInfeR integrates two experimentally accessible input data matrices: the drug sensitivity profiles
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DepInfeR/inst/doc/vignette.R
// Upstream  : BiocParallel, RColorBrewer, dplyr, ggbeeswarm, ggplot2
// Downstream: none
//
// Install: BiocManager::install("DepInfeR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DEPINFER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-depinfer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-depinfer:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-depinfer:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_depinfer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_depinfer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_depinfer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DepInfeR)
    library(jsonlite)

    # --- Target Matrix Processing [Target Matrix Processing] ---
    # Key functions: processTarget
    data(targetsGDSC, package = "depinfer")
    targetsGDSC$targetName <- ifelse(
        targetsGDSC$targetName == "BCR", "BCR/ABL",
        targetsGDSC$targetName
    )
    high_conf <- targetsGDSC[
        targetsGDSC$targetClassification == "High confidence",
    ]
    targetMatrix <- reshape2::acast(
        high_conf, drugID ~ targetName, value.var = "Kd"
    )
    ProcessTargetResults <- processTarget(
        targetMatrix,
        KdAsInput = TRUE,
        removeCorrelated = TRUE
    )
    targetInput <- ProcessTargetResults$targetMatrix

    # --- Response Matrix Preparation [Response Matrix Preparation] ---
    # Key functions: processTarget
    data(drug_response_GDSC, package = "depinfer")
    resp_sub <- drug_response_GDSC[
        drug_response_GDSC$`Drug Id` %in% rownames(targetInput),
    ]
    responseMatrix <- reshape2::acast(
        resp_sub, `Drug Id` ~ `Cell line name`, value.var = "AUC"
    )
    responseMatrix <- responseMatrix[
        , colSums(is.na(responseMatrix)) <= 24
    ]
    impRes <- missForest::missForest(t(responseMatrix))
    responseMatrix_imputed <- t(impRes$ximp)
    responseInput <- t(scale(t(responseMatrix_imputed)))

    # --- Dependency Inference [Dependency Inference] ---
    # Key functions: runLASSORegression
    overlappedDrugs <- intersect(
        rownames(responseInput),
        rownames(targetInput)
    )
    targetInput <- targetInput[overlappedDrugs, ]
    responseInput <- responseInput[overlappedDrugs, ]
    param <- BiocParallel::MulticoreParam(workers = 2, RNGseed = 333)
    result <- runLASSORegression(
        TargetMatrix = targetInput,
        ResponseMatrix = responseInput,
        repeats = 3,
        BPPARAM = param
    )

    # --- Dependency Visualization [Dependency Visualization] ---
    # Key functions: runLASSORegression
    data(mutation_GDSC, package = "depinfer")
    useTar <- rowSums(result$coefMat != 0) > 0
    importanceTab <- result$coefMat[useTar, ]
    colnames(importanceTab) <- gsub("-", ".", colnames(importanceTab))
    plotTab <- scale(t(importanceTab), center = FALSE, scale = TRUE)
    mutation_GDSC$TCGA.classification[
        mutation_GDSC$TCGA.classification == "BRCA"
    ] <- "BRCAHer-"
    mutation_GDSC$TCGA.classification <- factor(
        mutation_GDSC$TCGA.classification,
        levels = c("ALL", "AML", "DLBC", "BRCAHer-", "BRCAHer+")
    )
    pheatmap::pheatmap(
        plotTab,
        clustering_method = "ward.D2",
        scale = "none",
        fontsize = 9
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_depinfer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_depinfer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_depinfer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DEPINFER:", paste0("    depinfer: ", packageVersion("DepInfeR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_depinfer_results.csv
    touch ${prefix}_depinfer_output.rds
    echo "BIOC_DEPINFER:" > versions.yml
    echo "    depinfer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DEPINFER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DEPINFER(ch_input)

    emit:
    results  = BIOC_DEPINFER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DEPINFER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DEPINFER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DEPINFER.out.versions  // channel: path(versions.yml)
}
