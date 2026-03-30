#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GeneMeta
// A collection of meta-analysis tools for analysing high throughput experimental data
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GeneMeta/inst/doc/GeneMeta.R
// Upstream  : RColorBrewer
// Downstream: none
//
// Install: BiocManager::install("GeneMeta")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENEMETA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genemeta"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genemeta:1.78.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genemeta:1.78.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genemeta_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genemeta_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genemeta_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CountPlot)
    library(DL)
    library(IDRplot)
    library(jsonlite)

    # --- Splitting [] ---
    # Key functions: pData, sample
    set.seed(1609)
    thestatus  <- pData(Nevins)[,"ER.status"]
    group1     <- which(thestatus=="pos")
    group2     <- which(thestatus=="neg")
    rrr        <- c(sample(group1, floor(length(group1)/2)),
    # --- Phenodata [] ---
    # Key functions: pData, levels
    #obtain classes
    Split1.ER<-pData(Split1)[,"ER.status"]
    levels(Split1.ER) <- c(0,1)
    Split1.ER<- as.numeric(as.character(Split1.ER))
    Split2.ER<-pData(Split2)[,"ER.status"]
    # --- Calcd [] ---
    # Key functions: getdF, dstar, sigmad
    #calculate d for Split1
    d.Split1     <- getdF(Split1, Split1.ER)
    #adjust d value
    d.adj.Split1    <- dstar(d.Split1, length(Split1.ER))
    var.d.adj.Spli1 <- sigmad(d.adj.Split1, sum(Split1.ER==0), sum(Split1.ER==1))
    # --- Grapics [] ---
    # Key functions: qchisq, qqplot
    ########### graphics ################
    num.studies<-2
    #quantiles of the chisq distribution
    chisqq <- qchisq(seq(0, .9999, .001), df=num.studies-1)
    tmp<-quantile(my.Q, seq(0, .9999, .001))
    # --- Femmodel [] ---
    # Key functions: tau2
    muFEM = mu.tau2(mymns, myvars)
     sdFEM = var.tau2(myvars)
     ZFEM = muFEM/sqrt(sdFEM)
    # --- Qnormplotfem [] ---
    # Key functions: qqnorm, qqline
    qqnorm(ZFEM,pch="*")
     qqline(ZFEM,col="red")
    # --- Estimatedeffects [] ---
    # Key functions: DL, tau2, mu
    my.tau2.DL<-tau2.DL(my.Q, num.studies, my.weights=1/myvars)
    #obtain new variances s^2+tau^2
    myvarsDL <- myvars + my.tau2.DL
    #compute
    muREM <- mu.tau2(mymns, myvarsDL)
    # --- Claculationallinone [] ---
    # Key functions: pData, levels, zScores
    esets     <- list(Split1,Split2,Nevins)
    data.ER   <-pData(Nevins)[,"ER.status"]
    levels(data.ER) <- c(0,1)
    data.ER<- as.numeric(as.character(data.ER))
    classes   <- list(Split1.ER,Split2.ER,data.ER)
    # --- Idrplot [] ---
    # Key functions: IDRplot
    IDRplot(theScores,Combine=1:2,colPos="blue", colNeg="red")
    # --- Calculationallinone [] ---
    # Key functions: zScoreFDR
    ScoresFDR <- zScoreFDR(esets, classes, useREM=FALSE, nperm=50,CombineExp=1:2)
    # --- Bb2 [] ---
    # Key functions: pal
    theNewC <- brewer.pal(3,"Set2")
    # --- Thefdrplots [] ---
    # Key functions: CountPlot
    #par(mfrow=c(2,2))
    #CountPlot(ScoresFDR,Score="FDR",kindof="neg",cols=c("red",theNewC),
    #	main="Negative FDR", xlab="FDR threshold", ylab="Number of genes",CombineExp=1:2)
    #CountPlot(ScoresFDR,Score="FDR",cols=c("red",theNewC),kindof="pos",
    #main="Positive FDR", xlab="FDR threshold", ylab="Number of genes",Combine=1:2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genemeta_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genemeta_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genemeta_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENEMETA:", paste0("    genemeta: ", packageVersion("GeneMeta"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genemeta_results.csv
    touch ${prefix}_genemeta_output.rds
    echo "BIOC_GENEMETA:" > versions.yml
    echo "    genemeta: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENEMETA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENEMETA(ch_input)

    emit:
    results  = BIOC_GENEMETA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENEMETA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENEMETA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENEMETA.out.versions  // channel: path(versions.yml)
}
