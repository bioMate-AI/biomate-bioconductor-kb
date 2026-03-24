#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: arrayMvout
// This package supports the application of diverse quality metrics to AffyBatch instances, summarizing
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/arrayMvout/inst/doc/arrayMvout.R
// Upstream  : MAQCsubset, affyPLM, mdqc, mvoutData
// Downstream: none
//
// Install: BiocManager::install("arrayMvout")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ARRAYMVOUT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-arraymvout"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-arraymvout:1.64.0--r44_0' :
        'quay.io/biocontainers/bioconductor-arraymvout:1.64.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_arraymvout_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_arraymvout_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_arraymvout_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AffyRNAdeg)
    library(ArrayOutliers)
    library(NUSE)
    library(RLE)
    library(jsonlite)

    # --- Dddd [] ---
    # Key functions: ArrayOutliers
    library(arrayMvout)
    data(maqcQA)
    mm = ArrayOutliers(maqcQA[, 3:11], alpha=.01)
    mm
    # --- Dde [] ---
    # Key functions: ArrayOutliers
    data(itnQA)
    ii = ArrayOutliers(itnQA, alpha=.01)
    ii
    # --- Doapan [] ---
    # Key functions: sampleNames
    ## library(arrayMvout)
    ## library(MAQCsubset)
    ## if (!exists("afxsub")) data(afxsub)
    ## sn = sampleNames(afxsub)
    ## if (nchar(sn)[1] > 6) {
    # --- Lkadas [] ---
    # Key functions: AffyRNAdeg, plotAffyRNAdeg
    ## #afxsubDEG = AffyRNAdeg(afxsub)
    ## #save(afxsubDEG, file="afxsubDEG.rda")
    ## library(arrayMvout)
    ## data(afxsubDEG)
    ## plotAffyRNAdeg(afxsubDEG,
    # --- Asdad [] ---
    # Key functions: qc
    ## #afxsubQC = qc(afxsub)
    ## #save(afxsubQC, file="afxsubQC.rda")
    ## data(afxsubQC)
    ## plot(afxsubQC)
    # --- Splm [] ---
    # Key functions: fitPLM
    ## library(affyPLM)
    ## #if (file.exists("splm.rda")) load("splm.rda")
    ## #if (!exists("splm")) splm = fitPLM(afxsub)
    ## splm = fitPLM(afxsub)
    ## #save(splm, file="splm.rda")
    # --- Don [] ---
    # Key functions: NUSE, RLE, image
    ## png(file="doim.png")
    ## par(mar=c(7,5,5,5),mfrow=c(2,2),las=2)
    ## NUSE(splm, ylim=c(.85,1.3))
    ## RLE(splm)
    ## image(splm, which=2, type="sign.resid")
    # --- Doao [] ---
    # Key functions: ArrayOutliers
    ## AO = ArrayOutliers(afxsub, alpha=0.05, qcOut=afxsubQC,
    ##   plmOut=splm, degOut=afxsubDEG)
    ## nrow(AO[["outl"]])
    # --- Doz [] ---
    # Key functions: mdqc
    ## library(mdqc)
    ## mdq = mdqc( AO[[3]], robust="MVE" )
    ## mdq
    # --- Doada [] ---
    # Key functions: data
    ## require(mvoutData)
    ## data(s12c)
    # --- Doaaaasdas [] ---
    # Key functions: ArrayOutliers
    ## aos12c = ArrayOutliers(s12c, alpha=0.05)
    # --- Doma [] ---
    # Key functions: mdqc
    ## mdqc(aos12c[[3]], robust="MVE")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_arraymvout_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_arraymvout_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_arraymvout_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ARRAYMVOUT:", paste0("    arraymvout: ", packageVersion("arrayMvout"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_arraymvout_results.csv
    touch ${prefix}_arraymvout_output.rds
    echo "BIOC_ARRAYMVOUT:" > versions.yml
    echo "    arraymvout: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ARRAYMVOUT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ARRAYMVOUT(ch_input)

    emit:
    results  = BIOC_ARRAYMVOUT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ARRAYMVOUT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ARRAYMVOUT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ARRAYMVOUT.out.versions  // channel: path(versions.yml)
}
