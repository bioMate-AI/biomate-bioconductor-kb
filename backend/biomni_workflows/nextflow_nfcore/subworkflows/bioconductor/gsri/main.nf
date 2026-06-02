#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GSRI
// The GSRI package estimates the number of differentially expressed genes in gene sets, utilizing the 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GSRI/inst/doc/gsri.R
// Upstream  : Biobase, GSEABase, limma
// Downstream: none
//
// Install: BiocManager::install("GSRI")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GSRI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gsri"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gsri:2.54.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gsri:2.54.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gsri_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gsri_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gsri_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(F)
    library(GeneSet)
    library(Lkeys)
    library(jsonlite)

    # --- Preparepdfcdffig [] ---
    # Key functions: dunif, dexp, punif, pexp
    x <- seq(0, 1, len=50)
    r <- 0.2
    rate <- 10
    d0 <- dunif(x)
    d1 <- dexp(x, rate)
    # --- Pdffig [] ---
    # Key functions: getOption, expression, italic, rho
    getOption("SweaveHooks")[["fig"]]()
    plot(x, d, type="n", xaxt="n", yaxt="n", ylim=c(0, max(d)), xlab=expression(paste("p-value ", italic(p))), ylab=expression(paste("probability density ", rho(p))), cex.lab=cex)
    lines(c(0, 1), rep(1-r, 2), lwd=2, col="darkgray")
    lines(x, d, lwd=2)
    axis(1, at=seq(0, 1, len=5), labels=c(0, NA, 0.5, NA, 1), cex.axis=cex)
    # --- Cdffig [] ---
    # Key functions: getOption, expression, italic, F
    getOption("SweaveHooks")[["fig"]]()
    plot(x, c, type="n", xaxt="n", yaxt="n", xlim=c(0, 1), ylim=c(0, 1), xlab=expression(paste("p-value ", italic(p))), ylab=expression(paste("cumulative density ", F(p))), cex.lab=cex)
    lines(c(0, 1), c(r, 1), lwd=2, col="darkgray")
    lines(x, c, lwd=2)
    axis(1, at=seq(0, 1, len=5), labels=c(0, NA, 0.5, NA, 1), cex.axis=cex)
    # --- Extractdata [] ---
    # Key functions: exprs, pData, phenoData
    library(Biobase)
    data(sample.ExpressionSet)
    eset <- sample.ExpressionSet
    eset
    exprs <- exprs(eset)
    # --- Gsriallprobes [] ---
    # Key functions: gsri
    library(GSRI)
    gAllProbes <- gsri(eset, phenotypes$type)
    gAllProbes
    # --- Gsriallgenesset [] ---
    # Key functions: GeneSet, geneIds
    library(GSEABase)
    gs <- GeneSet(eset, setName="allGenes")
    ind <- grep("^AFFX", geneIds(gs), invert=TRUE)
    gsAllGenes <- gs[ind]
    gsAllGenes
    # --- Gsriallgenes [] ---
    # Key functions: gsri
    gAllGenesType <- gsri(eset, phenotypes$type, gsAllGenes, name="allGenesType")
    gAllGenesSex <- gsri(exprs, phenotypes$sex, gsAllGenes, name="allGenesSex")
    gAllGenesType
    gAllGenesSex
    # --- Gsrichr17 [] ---
    # Key functions: getBroadSets, gsri
    gsChr17 <- getBroadSets(system.file("extdata", "c1chr17.xml", package="GSRI"))
    gsChr17
    gChr17 <- gsri(eset, phenotypes$type, gsChr17)
    gChr17
    # --- Gsricol5 [] ---
    # Key functions: getGmt, gsri, sortGsri, tempfile, export
    gmt <- getGmt(system.file("extdata", "c1c10.gmt", package="GSRI"))
    gCol5 <- gsri(eset, phenotypes$type, gmt)
    gCol5
    gCol5Sort <- sortGsri(gCol5, c("nRegGenes", "pRegGenes"))
    summary(gCol5Sort)
    # --- Gsriscoreftest [] ---
    # Key functions: cut, gsri
    phenotypes$class <- cut(phenotypes$score, seq(0, 1, length.out=4), label=c("low", "medium", "high"))
    summary(phenotypes$class)
    g3 <- gsri(eset, phenotypes$class, gsChr17, test=rowF)
    g3
    # --- Gsriallgenesargs [] ---
    # Key functions: gsri
    g3arg2 <- gsri(eset, phenotypes$class, gsChr17, test=rowF, name="chr17_2", nBoot=50, alpha=0.1, grenander=FALSE)
    g3arg2
    # --- Limmatest [] ---
    # Key functions: lmFit, eBayes, gsri
    library(limma)
    # --- Plot1 [] ---
    # Key functions: getOption
    getOption("SweaveHooks")[["fig"]]()
    plot(g3)
    # --- Plot2 [] ---
    # Key functions: getOption
    getOption("SweaveHooks")[["fig"]]()
    plot(gCol5, 5, ecdf=list(type="o"), plot=list(xlab="p", main="GSRI results: chr9"), reg=list(col="lightblue", lty=1, lwd=1.5), gsri=list(col="darkblue"))
    # --- Weights [] ---
    # Key functions: exprs, Lkeys, factor, toTable
    library(hgu95av2.db)
    gNames <- rownames(exprs(eset))
    ind <- Lkeys(hgu95av2GO) %in% gNames
    evidence <- factor(toTable(hgu95av2GO)[ind,"Evidence"])
    summary(evidence)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gsri_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gsri_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gsri_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GSRI:", paste0("    gsri: ", packageVersion("GSRI"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gsri_results.csv
    touch ${prefix}_gsri_output.rds
    echo "BIOC_GSRI:" > versions.yml
    echo "    gsri: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GSRI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GSRI(ch_input)

    emit:
    results  = BIOC_GSRI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GSRI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GSRI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GSRI.out.versions  // channel: path(versions.yml)
}
