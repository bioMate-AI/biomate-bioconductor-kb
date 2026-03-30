#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GSEAlm
// Models and methods for fitting linear models to gene expression data, together with tools for comput
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GSEAlm/inst/doc/GSEAlm.R
// Upstream  : ALL, GOstats, RColorBrewer, Rgraphviz, annotate
// Downstream: none
//
// Install: BiocManager::install("GSEAlm")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GSEALM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gsealm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gsealm:1.66.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gsealm:1.66.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gsealm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gsealm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gsealm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CooksDPerGene)
    library(D)
    library(GSNormalize)
    library(jsonlite)

    # --- Load Libs [] ---
    # Key functions: pal
    library("annotate")
    library("GOstats")
    library("graph")
    #require("Rgraphviz", quietly=TRUE)
    #library("Rgraphviz")
    # --- Dataset Load And Initial Filtering [] ---
    # Key functions: intersect, factor, nsFilter
    data(ALL)
    ### Some filtering;
    ### see explanation below code
    bcellIdx <- grep("^B", as.character(ALL$BT))
    bcrOrNegIdx <- which(as.character(ALL$mol.biol)
    # --- Chromosomemapping [] ---
    # Key functions: mget, featureNames, all, na, unlist, makeChrBandGraph
    minBandSize = 5
    haveMAP = sapply(mget(featureNames(esetASub), hgu95av2MAP),
                     function(x) !all(is.na(x)))
    workingEset = esetASub[haveMAP, ]
    entrezUniv = unlist(mget(featureNames(workingEset), hgu95av2ENTREZID))
    # --- Lmphen [] ---
    # Key functions: lmPerGene, rowttests, relevel
    lmPhen <- lmPerGene(workingEset,~mol.biol)
    ##fit the t-tests model
    tobsChr <- rowttests(workingEset,"mol.biol")
    ## fit it via the linear-model interface
    lmEsts = lmPhen$tstat[2,]
    # --- Simpleresboxplot [] ---
    # Key functions: getResidPerGene, resplot, exprs
    lmPhenRes <- getResidPerGene(lmPhen)
    resplot(resmat=exprs(lmPhenRes),fac=workingEset$mol,cex.main=.7,cex.axis=.6,
    horiz=TRUE,lims=c(-5,5),xname="",col=5,cex=.3)
    # --- Gsea Resids [] ---
    # Key functions: GSNormalize, exprs, rowSums, sweep
    ## now we are going to aggregate residuals over chromosome bands
    stdrAchr=GSNormalize(exprs(lmPhenRes),AmatChr3)
    #rAchr =  AmatChr3 %*% exprs(lmPhenRes)
    #rAsqrSums = sqrt(rowSums(AmatChr3))
    #stdrAchr = sweep(rAchr, 1, rAsqrSums, FUN="/")
    # --- Raexchrhmap [] ---
    # Key functions: ifelse, dist, leaves
    # brColors <- ifelse(colnames(stdrAchr) %in% branch1,"brown", "grey")
    # molColors <- ifelse(workingEset$mol=="BCR/ABL","brown", "grey")
    kinetColors <- ifelse(workingEset$kinet=="hyperd.","brown", "grey")
     onecor=function(x) as.dist(1-cor(t(x))) # To get correlation-based heatmap
    ### In the heatmap we only use the lowest-level bands, or "leaves" of the graph
    # --- Fakehmap [] ---
    # Key functions: rexp, sample, sweep, rnorm, heatmap
    colbase=rexp(79,rate=3)*sample(c(-1,1),size=79,replace=T)
    randres=sweep(matrix(rnorm(length(ChrLeaves)*79),ncol=79),2,colbase)
    heatmap(randres, scale="row",col = HMcols,
              ColSideColors=kinetColors,keep.dendro=TRUE,distfun=onecor,
              ,labRow=FALSE,xlab="Sample",ylab="Chromosome band")
    # --- p Data [] ---
    # Key functions: pData, na
    sampleIDs=rownames(pData(workingEset))
    imputeEset=workingEset
    imputeEset$sex[is.na(workingEset$sex)] <- 'M'
    imputeEset$kinet[is.na(workingEset$kinet)] <- 'dyploid'
    ### This is the questionable sample; try once as diploid
    # --- lm Per Gene [] ---
    # Key functions: lmPerGene, getResidPerGene, GSNormalize, exprs
    lmExpand <- lmPerGene(workingEset,~mol.biol+sex+kinet)
    lmExpandRes <- getResidPerGene(lmExpand,type="extStudent")
    lmExpandTees <- t(lmExpand$tstat[2:4,])
    lmExpandBandTees<-GSNormalize(lmExpandTees,AmatChr3)
    GSresidExpand=GSNormalize(exprs(lmExpandRes),AmatChr3)
    # --- ifelse [] ---
    # Key functions: ifelse, heatmap
    kinetColors2 <- ifelse(lmExpandRes$kinet=="hyperd.","brown", "grey")
    bandHeatmapExp=heatmap(GSresidExpand[ChrLeaves,], scale="row",col = HMcols,
              ColSideColors=kinetColors2,keep.dendro=TRUE,distfun=onecor,
              labRow=FALSE,xlab="Sample",ylab="Chromosome band")
    # --- gsealm Perm [] ---
    # Key functions: gsealmPerm
    pvalsExpand=gsealmPerm(workingEset[LeafGenes,],~mol.biol+sex+kinet,AmatChr3[ChrLeaves,LeafGenes],nperm=nperm,removeShift=TRUE)
    pvalsExpand[pvalsExpand[,1]<flagp,1]
    pvalsExpand[pvalsExpand[,2]<flagp,2]
    # --- gsealm Perm [] ---
    # Key functions: gsealmPerm, browser
    chrNames=c(as.character(1:22),"X")
    pvalsHyper=gsealmPerm(workingEset,~kinet+mol.biol+sex,AmatChr3[chrNames,],nperm=nperm)
    pvalsHyper[pvalsHyper[,2]<flagp,2] ### over-expressed list for hyperdiploids
    # browser()
    # oldflags=c(table(pvals[,1]<flagp)[2],table(pvals[,2]<flagp)[2])
    # --- Hyperdiploidheatmap [] ---
    # Key functions: heatmap
    GSChromeResid=GSresidExpand[chrNames,]
    hyperHmap=heatmap(GSChromeResid[pvalsHyper[,2]<0.1,lmExpandRes$kinet=="hyperd."],
    scale="row",col = HMcols,keep.dendro=TRUE,distfun=onecor,xlab="Sample ID",ylab="Chromosome")
    # --- Cooksdplot [] ---
    # Key functions: CooksDPerGene, GSNormalize, col, D, na
    cookie1=CooksDPerGene(lmPhen)
    cookie3=CooksDPerGene(lmExpand)
    BandCooks1=GSNormalize(cookie1,AmatChr3,fun2=identity)
    BandCooks3=GSNormalize(cookie3,AmatChr3,fun2=identity)
    BandCooks1Base=BandCooks1[ChrLeaves,]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gsealm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gsealm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gsealm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GSEALM:", paste0("    gsealm: ", packageVersion("GSEAlm"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gsealm_results.csv
    touch ${prefix}_gsealm_output.rds
    echo "BIOC_GSEALM:" > versions.yml
    echo "    gsealm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GSEALM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GSEALM(ch_input)

    emit:
    results  = BIOC_GSEALM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GSEALM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GSEALM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GSEALM.out.versions  // channel: path(versions.yml)
}
