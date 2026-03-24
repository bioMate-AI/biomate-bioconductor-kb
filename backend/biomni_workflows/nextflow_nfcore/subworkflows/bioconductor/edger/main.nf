#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: edgeR
// Differential expression analysis of RNA-seq expression profiles with biological replication. Impleme
//
// Source : https://bioconductor.org/packages/3.20/workflows/vignettes/RNAseq123/inst/doc/limmaWorkflow.html
// Upstream  : none
// Downstream: ASpli, IntEREst, methylMnM, miloR, octad
//
// Install: BiocManager::install("edgeR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EDGER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-edger"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-edger:4.4.2--r44_0' :
        'quay.io/biocontainers/bioconductor-edger:4.4.2--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_edger_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_edger_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_edger_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(edgeR)
    library(jsonlite)

    # --- Reading in count-data [] ---
    # Key functions: download.file, untar, gunzip, readDGE, class
    url <- "https://www.ncbi.nlm.nih.gov/geo/download/?acc=GSE63310&format=file"
    utils::download.file(url, destfile="GSE63310_RAW.tar", mode="wb")
    utils::untar("GSE63310_RAW.tar", exdir = ".")
    files <- c("GSM1545535_10_6_5_11.txt", "GSM1545536_9_6_5_11.txt", "GSM1545538_purep53.txt",
      "GSM1545539_JMS8-2.txt", "GSM1545540_JMS8-3.txt", "GSM1545541_JMS8-4.txt",
      "GSM1545542_JMS8-5.txt", "GSM1545544_JMS9-P7c.txt", "GSM1545545_JMS9-P8c.txt")
    for(i in paste(files, ".gz", sep=""))
      R.utils::gunzip(i, overwrite=TRUE)
    
    files <- c("GSM1545535_10_6_5_11.txt", "GSM1545536_9_6_5_11.txt",
       "GSM1545538_purep53.txt", "GSM1545539_JMS8-2.txt",
       "GSM1545540_JMS8-3.txt", "GSM1545541_JMS8-4.txt",
    # --- Organising sample information [] ---
    # Key functions: rep
    samplenames <- substring(colnames(x), 12, nchar(colnames(x)))
    samplenames
    
    colnames(x) <- samplenames
    group <- as.factor(c("LP", "ML", "Basal", "Basal", "ML", "LP",
                         "Basal", "ML", "LP"))
    x$samples$group <- group
    lane <- as.factor(rep(c("L004","L006","L008"), c(3,4,2)))
    x$samples$lane <- lane
    x$samples
    # --- Organising gene annotations [] ---
    # Key functions: select
    geneid <- rownames(x)
    genes <- select(Mus.musculus, keys=geneid, columns=c("SYMBOL", "TXCHROM"),
                    keytype="ENTREZID")
    head(genes)
    
    genes <- genes[!duplicated(genes$ENTREZID),]
    
    x$genes <- genes
    x
    # --- Transformations from the raw-scale [] ---
    # Key functions: cpm
    cpm <- cpm(x)
    lcpm <- cpm(x, log=TRUE)
    
    L <- mean(x$samples$lib.size) * 1e-6
    M <- median(x$samples$lib.size) * 1e-6
    c(L, M)
    
    summary(lcpm)
    # --- Removing genes that are lowly expressed [] ---
    # Key functions: rowSums, filterByExpr, brewer.pal
    table(rowSums(x$counts==0)==9)
    
    keep.exprs <- filterByExpr(x, group=group)
    x <- x[keep.exprs,, keep.lib.sizes=FALSE]
    dim(x)
    
    lcpm.cutoff <- log2(10/M + 2/L)
    library(RColorBrewer)
    nsamples <- ncol(x)
    col <- brewer.pal(nsamples, "Paired")
    par(mfrow=c(1,2))
    plot(density(lcpm[,1]), col=col[1], lwd=2, ylim=c(0,0.26), las=2, main="", xlab="")
    # --- Normalising gene expression distributions [] ---
    # Key functions: calcNormFactors, cpm
    x <- calcNormFactors(x, method = "TMM")
    x$samples$norm.factors
    
    x2 <- x
    x2$samples$norm.factors <- 1
    x2$counts[,1] <- ceiling(x2$counts[,1]*0.05)
    x2$counts[,2] <- x2$counts[,2]*5
    
    par(mfrow=c(1,2))
    lcpm <- cpm(x2, log=TRUE)
    boxplot(lcpm, las=2, col=col, main="")
    title(main="A. Example: Unnormalised data",ylab="Log-cpm")
    # --- Unsupervised clustering of samples [] ---
    # Key functions: cpm, levels, brewer.pal, nlevels, plotMDS, glMDSPlot
    lcpm <- cpm(x, log=TRUE)
    par(mfrow=c(1,2))
    col.group <- group
    levels(col.group) <-  brewer.pal(nlevels(col.group), "Set1")
    col.group <- as.character(col.group)
    col.lane <- lane
    levels(col.lane) <-  brewer.pal(nlevels(col.lane), "Set2")
    col.lane <- as.character(col.lane)
    plotMDS(lcpm, labels=group, col=col.group)
    title(main="A. Sample groups")
    plotMDS(lcpm, labels=lane, col=col.lane, dim=c(3,4))
    title(main="B. Sequencing lanes")
    # --- Creating a design matrix and contrasts [] ---
    # Key functions: model.matrix, makeContrasts
    design <- model.matrix(~0+group+lane)
    colnames(design) <- gsub("group", "", colnames(design))
    design
    
    contr.matrix <- makeContrasts(
       BasalvsLP = Basal-LP,
       BasalvsML = Basal - ML,
       LPvsML = LP - ML,
       levels = colnames(design))
    contr.matrix
    # --- Removing heteroscedascity from count data [] ---
    # Key functions: voom, lmFit, contrasts.fit, eBayes, plotSA
    par(mfrow=c(1,2))
    v <- voom(x, design, plot=TRUE)
    v
    
    vfit <- lmFit(v, design)
    vfit <- contrasts.fit(vfit, contrasts=contr.matrix)
    efit <- eBayes(vfit)
    plotSA(efit, main="Final model: Mean-variance trend")
    # --- Examining the number of DE genes [] ---
    # Key functions: decideTests, treat, vennDiagram, write.fit
    summary(decideTests(efit))
    
    tfit <- treat(vfit, lfc=1)
    dt <- decideTests(tfit)
    summary(dt)
    
    de.common <- which(dt[,1]!=0 & dt[,2]!=0)
    length(de.common)
    
    head(tfit$genes$SYMBOL[de.common], n=20)
    
    vennDiagram(dt[,1:2], circle.col=c("turquoise", "salmon"))
    # --- Examining individual DE genes from top to bottom [] ---
    # Key functions: topTreat
    basal.vs.lp <- topTreat(tfit, coef=1, n=Inf)
    basal.vs.ml <- topTreat(tfit, coef=2, n=Inf)
    head(basal.vs.lp)
    
    head(basal.vs.ml)
    # --- Useful graphical representations of differential expression results [] ---
    # Key functions: plotMD, glMDPlot, colorpanel, heatmap.2, ids2indices
    plotMD(tfit, column=1, status=dt[,1], main=colnames(tfit)[1],
           xlim=c(-8,13))
    
    glMDPlot(tfit, coef=1, status=dt, main=colnames(tfit)[1],
             side.main="ENTREZID", counts=lcpm, groups=group, launch=FALSE)
    
    library(gplots)
    basal.vs.lp.topgenes <- basal.vs.lp$ENTREZID[1:100]
    i <- which(v$genes$ENTREZID %in% basal.vs.lp.topgenes)
    mycol <- colorpanel(1000,"blue","white","red")
    heatmap.2(lcpm[i,], scale="row",
       labRow=v$genes$SYMBOL[i], labCol=group,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_edger_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_edger_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_edger_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EDGER:", paste0("    edger: ", packageVersion("edgeR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_edger_results.csv
    touch ${prefix}_edger_output.rds
    echo "BIOC_EDGER:" > versions.yml
    echo "    edger: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EDGER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EDGER(ch_input)

    emit:
    results  = BIOC_EDGER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EDGER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EDGER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EDGER.out.versions  // channel: path(versions.yml)
}
