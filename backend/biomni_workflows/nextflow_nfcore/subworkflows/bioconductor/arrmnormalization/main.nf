#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ARRmNormalization
// Perform the Adaptive Robust Regression method (ARRm) for the normalization of methylation data from 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ARRmNormalization/inst/doc/ARRmNormalization.R
// Upstream  : ARRmData
// Downstream: none
//
// Install: BiocManager::install("ARRmNormalization")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ARRMNORMALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-arrmnormalization"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-arrmnormalization:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-arrmnormalization:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_arrmnormalization_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_arrmnormalization_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_arrmnormalization_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ARRmNormalization)
    library(jsonlite)

    # --- Dataloading [] ---
    # Key functions: data
    library(ARRmData)
    data(greenControlMatrix)
    data(redControlMatrix)
    data(betaMatrix)
    data(sampleNames)
    # --- Probesloading [] ---
    # Key functions: data
    library(ARRmNormalization)
    data(ProbesType)
    head(ProbesType)
    # --- Dataloading2 [] ---
    # Key functions: data
    data(betaMatrix)
    data(greenControlMatrix)
    data(redControlMatrix)
    data(sampleNames)
    # --- Getbackground [] ---
    # Key functions: getBackground
    backgroundInfo <- getBackground(greenControlMatrix, redControlMatrix)
    # --- Getdesigninfo [] ---
    # Key functions: getDesignInfo
    designInfo <- getDesignInfo(sampleNames)
    head(designInfo)
    # --- Getexplicitdesign [] ---
    # Key functions: getDesignInfo
    designInfo <- getDesignInfo(sampleNames=NULL,
                      positionVector=myPositionVector, chipVector=myChipVector)
    head(designInfo)
    # --- Firstnorm [] ---
    # Key functions: normalizeARRm
    ## normMatrix <-
    ##     normalizeARRm(betaMatrix=betaMatrix, designInfo=designInfo,
    ##         backgroundInfo=backgroundInfo, outliers.perc=0.1)
    # --- Goodprobes [] ---
    # Key functions: unlist
    data(ProbesType)
    goodProbes <- as.character(unlist(ProbesType$Probe_Name))[seq(1,485577,2)]
    # --- Normgoodprobes [] ---
    # Key functions: normalizeARRm
    ## normMatrix <-
    ##     normalizeARRm(betaMatrix=betaMatrix, designInfo=designInfo,
    ##         backgroundInfo=backgroundInfo, outliers.perc=0, goodProbes=goodProbes)
    # --- Normwochip [] ---
    # Key functions: normalizeARRm
    ## normMatrix <-
    ##     normalizeARRm(betaMatrix=betaMatrix, designInfo=designInfo,
    ##         backgroundInfo=backgroundInfo, outliers.perc=0, chipCorrection=F)
    # --- Getquantiles [] ---
    # Key functions: getQuantiles, attributes
    quantiles=getQuantiles(betaMatrix)
    attributes(quantiles)
    # --- Printquantiles [] ---
    # Key functions: getQuantiles, attributes
    quantiles=getQuantiles(betaMatrix, goodProbes=goodProbes)
    attributes(quantiles)
    # --- Quantilesplots [] ---
    # Key functions: quantilePlots
    quantilePlots(quantiles, backgroundInfo, designInfo)
    # --- Linear regression model [] ---
    # Key functions: unlist, lm
    plot(x,y,type="n",xlab="Log Background intensity",ylab="Beta value",main=titles[j])
    # --- Fig1 [] ---
    # Key functions: unlist, lm
    plot(x,y,type="n",xlab="Log Background intensity",ylab="Beta value",main=titles[j])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_arrmnormalization_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_arrmnormalization_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_arrmnormalization_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ARRMNORMALIZATION:", paste0("    arrmnormalization: ", packageVersion("ARRmNormalization"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_arrmnormalization_results.csv
    touch ${prefix}_arrmnormalization_output.rds
    echo "BIOC_ARRMNORMALIZATION:" > versions.yml
    echo "    arrmnormalization: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ARRMNORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ARRMNORMALIZATION(ch_input)

    emit:
    results  = BIOC_ARRMNORMALIZATION.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ARRMNORMALIZATION.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ARRMNORMALIZATION.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ARRMNORMALIZATION.out.versions  // channel: path(versions.yml)
}
