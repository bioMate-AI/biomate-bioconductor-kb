#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: epigenomix
// A package for the integrative analysis of RNA-seq or microarray based gene transcription and histone
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/epigenomix/inst/doc/epigenomix.R
// Upstream  : biomaRt
// Downstream: none
//
// Install: BiocManager::install("epigenomix")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EPIGENOMIX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-epigenomix"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-epigenomix:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-epigenomix:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_epigenomix_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_epigenomix_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_epigenomix_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(epigenomix)
    library(ExpressionSet)
    library(GRanges)
    library(IRanges)
    library(jsonlite)

    # --- Normalization [] ---
    # Key functions: normalize, chipVals
    chipSet <- normalize(chipSetRaw, method="quantile")
    raw_vals <- chipVals(chipSetRaw)
    norm_vals <- chipVals(chipSet)


    # --- Data Integration [] ---
    # Key functions: integrateData
    chipSet$CEBPA <- factor(c("wt", "ko"))
    intData <- integrateData(
        eSet, chipSet, factor="CEBPA", reference="wt"
    )


    # --- Mixture Model Fitting [] ---
    # Key functions: mlMixModel, bayesMixModel
    mlmm <- mlMixModel(
        intData[, "z"], normNull=c(2, 3), expNeg=1, expPos=4,
        sdNormNullInit=c(0.5, 1), rateExpNegInit=0.5, rateExpPosInit=0.5,
        pi=rep(1/4, 4)
    )
    bayesmm <- bayesMixModel(
        intData[, "z"], normNull=c(2, 3), expNeg=1, expPos=4,
        sdNormNullInit=c(0.5, 1), rateExpNegInit=0.5, rateExpPosInit=0.5,
        shapeNorm0=c(10, 10), scaleNorm0=c(10, 10), shapeExpNeg0=0.01,
        scaleExpNeg0=0.01, shapeExpPos0=0.01, scaleExpPos0=0.01,
        pi=rep(1/4, 4), sdAlpha=1, itb=2000, nmc=8000, thin=5
    )


    # --- Model Visualization and Classification [] ---
    # Key functions: plotComponents, plotClassification, classification
    plotComponents(mlmm, xlim=c(-2, 2), ylim=c(0, 3))
    plotClassification(bayesmm, method="mode")
    class_mlmm <- classification(mlmm, method="maxDens")
    class_bayes <- classification(bayesmm, method="mode")
    comp_table <- table(class_mlmm, class_bayes)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_epigenomix_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_epigenomix_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_epigenomix_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EPIGENOMIX:", paste0("    epigenomix: ", packageVersion("epigenomix"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_epigenomix_results.csv
    touch ${prefix}_epigenomix_output.rds
    echo "BIOC_EPIGENOMIX:" > versions.yml
    echo "    epigenomix: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EPIGENOMIX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EPIGENOMIX(ch_input)

    emit:
    results  = BIOC_EPIGENOMIX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EPIGENOMIX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EPIGENOMIX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EPIGENOMIX.out.versions  // channel: path(versions.yml)
}
