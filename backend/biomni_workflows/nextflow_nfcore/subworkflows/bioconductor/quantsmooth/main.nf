#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: quantsmooth
// Implements quantile smoothing as introduced in: Quantile smoothing of array CGH data; Eilers PH, de 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/quantsmooth/inst/doc/quantsmooth.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("quantsmooth")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QUANTSMOOTH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-quantsmooth"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-quantsmooth:1.72.0--r44_0' :
        'quay.io/biocontainers/bioconductor-quantsmooth:1.72.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_quantsmooth_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_quantsmooth_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_quantsmooth_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(quantsmooth)
    library(jsonlite)

    # --- Simpleplot [] ---
    # Key functions: quantsmooth
    library(quantsmooth)
    data(chr14)
    plot(affy.cn[,1],pch=".")
    lines(quantsmooth(affy.cn[,1]),lwd=2)
    # --- Firstcomparison [] ---
    # Key functions: quantsmooth
    plot(affy.pos,affy.cn[,1],ylab="copy number",xlab="position",pch=".")
    lines(affy.pos,quantsmooth(affy.cn[,1]),lwd=2)
    points(bac.pos,bac.cn[,1],col="red",pch=".")
    lines(bac.pos,quantsmooth(bac.cn[,1]),col="red",lwd=2)
    points(ill.pos,ill.cn[,1],col="blue",pch=".")
    # --- Lambdalengthdependent [] ---
    # Key functions: quantsmooth
    lambda.divisor<-50
    plot(affy.pos,affy.cn[,1],ylab="copy number",xlab="position",pch=".")
    lines(affy.pos,quantsmooth(affy.cn[,1],smooth.lambda=length(affy.pos)/lambda.divisor),lwd=2)
    points(bac.pos,bac.cn[,1],col="red",pch=".")
    lines(bac.pos,quantsmooth(bac.cn[,1],smooth.lambda=length(bac.pos)/lambda.divisor),col="red",lwd=2)
    # --- Crossvalidation [] ---
    # Key functions: cv
    lambdas<-2^seq(from=-2,to=5,by=0.25)
    lambda.res <- rep(NA, length(lambdas))
    for (lambda in 1:length(lambdas)) lambda.res[lambda] <- quantsmooth.cv(bac.cn[,1], lambdas[lambda])
    plot(lambdas,lambda.res,type="l")
    abline(v=lambdas[which.min(lambda.res)])
    # --- Percentilesmoothing [] ---
    # Key functions: quantsmooth
    plot(bac.pos,quantsmooth(bac.cn[,1],smooth.lambda=length(bac.pos)/lambda.divisor),col="red",type="l",lwd=2)
    lines(bac.pos,quantsmooth(bac.cn[,1],smooth.lambda=length(bac.pos)/lambda.divisor,tau=0.25),col="red",lty=2)
    lines(bac.pos,quantsmooth(bac.cn[,1],smooth.lambda=length(bac.pos)/lambda.divisor,tau=0.75),col="red",lty=2)
    # --- Plotsmoothed [] ---
    # Key functions: plotSmoothed
    plotSmoothed(bac.cn,bac.pos,ylim=c(1,2.5),normalized.to=2,smooth.lambda=length(bac.pos)/lambda.divisor)
    # --- Changedregions [] ---
    # Key functions: plotSmoothed, getChangedRegions, segments
    plotSmoothed(ill.cn[,1],ill.pos,ylim=c(1,2.5),normalized.to=2,smooth.lambda=length(ill.pos)/lambda.divisor)
    res<-getChangedRegions(ill.cn[,1],ill.pos,normalized.to=2,interval=0.5)
    segments(res[,"start"],1.0,res[,"end"],1.0,col=2,lwd=2)
    # --- Tolatex [] ---
    # Key functions: toLatex
    toLatex(sessionInfo())

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_quantsmooth_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_quantsmooth_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_quantsmooth_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_QUANTSMOOTH:", paste0("    quantsmooth: ", packageVersion("quantsmooth"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_quantsmooth_results.csv
    touch ${prefix}_quantsmooth_output.rds
    echo "BIOC_QUANTSMOOTH:" > versions.yml
    echo "    quantsmooth: 0.0.0" >> versions.yml
    """
}


workflow BIOC_QUANTSMOOTH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_QUANTSMOOTH(ch_input)

    emit:
    results  = BIOC_QUANTSMOOTH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_QUANTSMOOTH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_QUANTSMOOTH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_QUANTSMOOTH.out.versions  // channel: path(versions.yml)
}
