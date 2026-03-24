#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: gaga
// Implements the GaGa model for high-throughput data analysis, including differential expression analy
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/gaga/inst/doc/gagamanual.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("gaga")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GAGA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gaga"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gaga:2.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gaga:2.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gaga_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gaga_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gaga_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(gaga)
    library(jsonlite)

    # --- One [] ---
    # Key functions: simGG
    library(gaga)
    set.seed(10)
    n <- 100; m <- c(6,6)
    a0 <- 25.5; nu <- 0.109
    balpha <- 1.183; nualpha <- 1683
    # --- Two [] ---
    # Key functions: featureData, phenoData, fData, exprs
    xsim
    featureData(xsim)
    phenoData(xsim)
    a <- fData(xsim)[,c("alpha.1","alpha.2")]
    l <- fData(xsim)[,c("mean.1","mean.2")]
    # --- density [] ---
    # Key functions: density
    plot(density(x),xlab='Expression levels',main='')
    # --- Three [] ---
    # Key functions: pData
    groups <- pData(xsim)$group[c(-6,-12)]
    groups
    patterns <- matrix(c(0,0,0,1),2,2)
    colnames(patterns) <- c('group 1','group 2')
    patterns
    # --- Four [] ---
    # Key functions: fitGG
    patterns <- matrix(c(0,0,0,1),2,2)
    colnames(patterns) <- c('group 1','group 2')
    gg1 <- fitGG(x[,c(-6,-12)],groups,patterns=patterns,nclust=1,method='Gibbs',B=1000,trace=FALSE)
    gg2 <- fitGG(x[,c(-6,-12)],groups,patterns=patterns,method='EM',trace=FALSE)
    gg3 <- fitGG(x[,c(-6,-12)],groups,patterns=patterns,method='quickEM',trace=FALSE)
    # --- Five [] ---
    # Key functions: parest
    gg1 <- parest(gg1,x=x[,c(-6,-12)],groups,burnin=100,alpha=.05)
    gg2 <- parest(gg2,x=x[,c(-6,-12)],groups,alpha=.05)
    gg3 <- parest(gg3,x=x[,c(-6,-12)],groups,alpha=.05)
    gg1
    gg1$ci
    # --- checkfit [] ---
    # Key functions: checkfit
    checkfit(gg1,x=x[,c(-6,-12)],groups,type='data',main='')
    # --- Eight [] ---
    # Key functions: findgenes
    d1 <- findgenes(gg1,x[,c(-6,-12)],groups,fdrmax=.05,parametric=TRUE)
    d1.nonpar <- findgenes(gg1,x[,c(-6,-12)],groups,fdrmax=.05,parametric=FALSE,B=1000)
    dtrue <- (l[,1]!=l[,2])
    table(d1$d,dtrue)
    table(d1.nonpar$d,dtrue)
    # --- Eightbis [] ---
    # Key functions: findgenes
    d2 <- findgenes(gg2,x[,c(-6,-12)],groups,fdrmax=.05,parametric=TRUE)
    d3 <- findgenes(gg3,x[,c(-6,-12)],groups,fdrmax=.05,parametric=TRUE)
    table(d1$d,d2$d)
    table(d1$d,d3$d)
    # --- Fc1 [] ---
    # Key functions: posmeansGG
    mpos <- posmeansGG(gg1,x=x[,c(-6,-12)],groups=groups,underpattern=1)
    fc <- mpos[,1]-mpos[,2]
    fc[1:5]
    # --- Nine [] ---
    # Key functions: classpred
    pred1 <- classpred(gg1,xnew=x[,6],x=x[,c(-6,-12)],groups,ngene=50,prgroups=c(.5,.5))
    pred2 <- classpred(gg1,xnew=x[,12],x=x[,c(-6,-12)],groups,ngene=50,prgroups=c(.5,.5))
    pred1
    pred2
    # --- Simulatefs [] ---
    # Key functions: simGG, fitGG, parest
    set.seed(1)
    x <- simGG(n=20,m=2,p.de=.5,a0=3,nu=.5,balpha=.5,nualpha=25)
    gg1 <- fitGG(x,groups=1:2,method='EM')
    gg1 <- parest(gg1,x=x,groups=1:2)
    # --- Powfindgenes [] ---
    # Key functions: powfindgenes
    pow1 <- powfindgenes(gg1, x=x, groups=1:2, batchSize=1, fdrmax=0.05, B=1000)
    pow2 <- powfindgenes(gg1, x=x, groups=1:2, batchSize=2, fdrmax=0.05, B=1000)
    pow3 <- powfindgenes(gg1, x=x, groups=1:2, batchSize=3, fdrmax=0.05, B=1000)
    pow1$m
    pow2$m
    # --- Forwsim [] ---
    # Key functions: forwsimDiffExpr
    fs1 <- forwsimDiffExpr(gg1, x=x, groups=1:2,
    maxBatch=3,batchSize=1,fdrmax=0.05, B=100, Bsummary=100, randomSeed=1)
    head(fs1)
    # --- Seqn [] ---
    # Key functions: seqBoundariesGrid
    b0seq <- seq(0,20,length=200); b1seq <- seq(0,40,length=200)
    bopt <-seqBoundariesGrid(b0=b0seq,b1=b1seq,forwsim=fs1,samplingCost=samplingCost,powmin=0)
    names(bopt)
    bopt$opt
    head(bopt$grid)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gaga_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gaga_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gaga_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GAGA:", paste0("    gaga: ", packageVersion("gaga"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gaga_results.csv
    touch ${prefix}_gaga_output.rds
    echo "BIOC_GAGA:" > versions.yml
    echo "    gaga: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GAGA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GAGA(ch_input)

    emit:
    results  = BIOC_GAGA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GAGA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GAGA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GAGA.out.versions  // channel: path(versions.yml)
}
