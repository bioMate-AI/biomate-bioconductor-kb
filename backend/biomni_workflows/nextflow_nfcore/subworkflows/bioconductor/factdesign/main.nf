#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: factDesign
// This package provides a set of tools for analyzing data from a factorial designed microarray experim
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/factDesign/inst/doc/factDesign.R
// Upstream  : Biobase, affy, multtest, stats
// Downstream: none
//
// Install: BiocManager::install("factDesign")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FACTDESIGN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-factdesign"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-factdesign:1.82.0--r44_0' :
        'quay.io/biocontainers/bioconductor-factdesign:1.82.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_factdesign_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_factdesign_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_factdesign_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(factDesign)
    library(jsonlite)

    # --- Phenodata [] ---
    # Key functions: pData
    data(estrogen)
    estrogen
    pData(estrogen)
    # --- Fcplots [] ---
    # Key functions: exprs
    par(mfrow=c(2,2))
    par(las=2)
    for (i in c("34371_at","37325_at","33744_at","39792_at")){
    	expvals <- 2^exprs(estrogen)[i,]
    	plot(expvals,axes=F,cex=1.5,
    # --- Moreplots [] ---
    # Key functions: exprs
    par(mfrow=c(2,2))
    par(las=2)
    for (i in c("32536_at","40446_at","32901_s_at","31826_at")){
    	expvals <- exprs(estrogen)[i,]
    	plot(expvals,axes=F,cex=1.5,
    # --- Outliers [] ---
    # Key functions: outlierPair, exprs, pData, madOutPair
    op1 <- outlierPair(exprs(estrogen)["728_at",],INDEX=pData(estrogen),p=.05)
    print(op1)
    madOutPair(exprs(estrogen)["728_at",],op1[[3]])
    par(mfrow=c(2,2))
    par(las=2)
    # --- Lm [] ---
    # Key functions: lm, esApply
    lm.full <- function(y) lm(y ~ ES + TIME + ES:TIME)
    lm.time <- function(y) lm(y ~ TIME)
    lm.f <- esApply(estrogen, 1, lm.full)
    lm.t <- esApply(estrogen, 1, lm.time)
    lm.f[[1]]
    # --- Comparemodels [] ---
    # Key functions: anova, rawp2adjp
    Fpvals <- rep(0,length(lm.f))
    for(i in 1:length(lm.f)){
      Fpvals[i]<-anova(lm.t[[i]],lm.f[[i]])$P[2]
    }
    library(multtest)
    # --- Maines [] ---
    # Key functions: coef, par2lambda, contrastTest
    betaNames <- names(coef(lm.f[[1]]))
    lambda <- par2lambda(betaNames,c("ESP"),c(1))
    mainES <- function(x) contrastTest(x,lambda,p=0.05)[[1]]
    mainESgenes <- sapply(lm.f.Fsub,FUN=mainES)
    sum(mainESgenes=="REJECT")
    # --- Eshm1 [] ---
    # Key functions: heatmap, exprs, colors
    heatmap(exprs(estrogen.Fsub)[mainESgenes=="REJECT",],Colv=NA,col=cm.colors(256))
    # --- Eshm2 [] ---
    # Key functions: heatmap, exprs, colors
    heatmap(exprs(estrogen.Fsub)[mainESgenes=="FAIL TO REJECT",],Colv=NA,col=cm.colors(256))
    # --- Effectsize [] ---
    # Key functions: par2lambda, findFC, unlist, heatmap
    lambdaNum <- par2lambda(betaNames,list(c("(Intercept)","ESP")),list(c(1,1)))
    lambdaDenom <-  par2lambda(betaNames,list(c("(Intercept)")),list(c(1)))
    FCval <- findFC(lm.f.Fsub[["32901_s_at"]],lambdaNum,lambdaDenom,logbase=2)
    print(FCval)
    FCvals <- lapply(lm.f.Fsub,FUN=findFC,lambdaNum,lambdaDenom,logbase=2)
    # --- Performct [] ---
    # Key functions: par2lambda, contrastTest
    lambdaEST <- par2lambda(betaNames,list(c("ESP","ESP:TIME48h")),list(c(1,1)))
    ESTcontrast <- function(x) contrastTest(x,lambdaEST,p=.10)[[1]]
    ESTgenes <- sapply(lm.f.Fsub,FUN=ESTcontrast)
    sum(ESTgenes=="REJECT")
    # --- Esthm1 [] ---
    # Key functions: heatmap, exprs, colors
    heatmap(exprs(estrogen.Fsub)[mainESgenes=="REJECT" & ESTgenes=="REJECT",],Colv=NA,col=cm.colors(256))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_factdesign_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_factdesign_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_factdesign_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FACTDESIGN:", paste0("    factdesign: ", packageVersion("factDesign"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_factdesign_results.csv
    touch ${prefix}_factdesign_output.rds
    echo "BIOC_FACTDESIGN:" > versions.yml
    echo "    factdesign: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FACTDESIGN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FACTDESIGN(ch_input)

    emit:
    results  = BIOC_FACTDESIGN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FACTDESIGN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FACTDESIGN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FACTDESIGN.out.versions  // channel: path(versions.yml)
}
