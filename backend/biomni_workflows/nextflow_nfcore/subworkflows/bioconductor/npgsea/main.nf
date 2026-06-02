#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: npGSEA
// Current gene set enrichment methods rely upon permutations for inference.  These approaches are comp
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/npGSEA/inst/doc/npGSEA.R
// Upstream  : ALL, GSEABase, ReportingTools, genefilter, limma
// Downstream: none
//
// Install: BiocManager::install("npGSEA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NPGSEA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-npgsea"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-npgsea:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-npgsea:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_npgsea_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_npgsea_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_npgsea_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GeneSet)
    library(GeneSetCollection)
    library(HTMLReport)
    library(jsonlite)

    # --- Loadlibrariesanddata [] ---
    # Key functions: na, factor, featureFilter
    library(ALL)
    library(hgu95av2.db)
    library(genefilter)
    library(limma)
    library(GSEABase)
    # --- Adjustnames [] ---
    # Key functions: featureNames, select
    featureNames(ALL) <- select(hgu95av2.db, featureNames(ALL),
                                "ENTREZID", "PROBEID")$ENTREZID
    # --- Makesets [] ---
    # Key functions: exprs, GeneSet, sample
    xData <- exprs(ALL)
    geneEids <- rownames(xData)
    set.seed(12345)
    # --- Empirical Bayes moderation (limma) [] ---
    # Key functions: eBayes, lmFit, topTable, GeneSet
    model <- model.matrix(~mol.biol, ALL)
    fit  <-  eBayes(lmFit(ALL, model))
    tt <- topTable(fit, coef=2, n=200)
    ttUp <- tt[which(tt$logFC >0), ]
    ttDown <- tt[which(tt$logFC <0), ]
    # --- Gsc [] ---
    # Key functions: GeneSetCollection
    gsc <- GeneSetCollection( c(set1, set2, set3, set4, set5, set6, set7) )
    gsc
    # --- Runit [] ---
    # Key functions: npGSEA
    yFactor <- ALL$mol.biol
    res1 <- npGSEA(x = ALL, y = yFactor, set = set1)  ##with the eset
    res1
    res2_exprs <- npGSEA(xData, ALL$mol.biol, gsc[[2]])  ##with the expression data
    res2_exprs
    # --- Accessorfunctions [] ---
    # Key functions: npGSEA, geneSetName, stat, sigmaSq, zStat, pTwoSided, pLeft, pValues
    res3 <- npGSEA(ALL, yFactor, set3)
    res3
    geneSetName(res3)
    stat(res3)
    sigmaSq(res3)
    # --- Runitnorm [] ---
    # Key functions: npGSEA, betaHats, npGSEAPlot
    res5_norm <- npGSEA(ALL, yFactor, set5, approx= "norm")
    res5_norm
    betaHats(res5_norm)
    npGSEAPlot(res5_norm)
    # --- Runitbeta [] ---
    # Key functions: npGSEA, betaHats, npGSEAPlot
    res5_beta <- npGSEA(ALL, yFactor, set5, approx= "beta")
    res5_beta
    betaHats(res5_beta)
    npGSEAPlot(res5_beta)
    # --- Runitchisq [] ---
    # Key functions: npGSEA, betaHats, chiSqStat, stat, sigmaSq, npGSEAPlot
    res5_chiSq <- npGSEA(ALL, yFactor, set5, approx= "chiSq")
    res5_chiSq
    betaHats(res5_chiSq)
    chiSqStat(res5_chiSq)
    stat(res5_chiSq)
    # --- Runitwts [] ---
    # Key functions: npGSEA, exprs, geneIds, featureNames
    res7_nowts <- npGSEA(x = ALL, y= yFactor, set = set7)
    res7_nowts
    wts <- apply(exprs(ALL)[match(geneIds(set7), featureNames(ALL)), ],
    						1, var)
    wts <- 1/wts
    # --- Addcovariates [] ---
    # Key functions: npGSEA
    res3_age <- npGSEA(x = ALL, y = yFactor, set = set3, covars = ALL$age)
    res3_age
    res3_agesex <- npGSEA(x = ALL, y = yFactor, set = set3, covars = cbind(ALL$age, ALL$sex))
    res3_agesex
    # --- Runmultiplenpgsea [] ---
    # Key functions: npGSEA, unlist, pLeft, stat, zStat
    resgsc_norm <- npGSEA(x = ALL, y = yFactor, set = gsc)
    unlist( pLeft(resgsc_norm) )
    unlist( stat (resgsc_norm) )
    unlist( zStat (resgsc_norm) )
    # --- Publishmultiplenpgsea [] ---
    # Key functions: adjust, unlist, pTwoSided, HTMLReport, publish, zStat, finish
    ## pvals <- p.adjust( unlist(pTwoSided(resgsc_norm)), method= "BH" )
    ## library(ReportingTools)
    ## npgseaReport <- HTMLReport (shortName = "npGSEA",
    ##         title = "npGSEA Results", reportDirectory = "./reports")
    # --- Sessinfo [] ---
    # Key functions: toLatex
    toLatex(sessionInfo())

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_npgsea_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_npgsea_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_npgsea_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NPGSEA:", paste0("    npgsea: ", packageVersion("npGSEA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_npgsea_results.csv
    touch ${prefix}_npgsea_output.rds
    echo "BIOC_NPGSEA:" > versions.yml
    echo "    npgsea: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NPGSEA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NPGSEA(ch_input)

    emit:
    results  = BIOC_NPGSEA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NPGSEA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NPGSEA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NPGSEA.out.versions  // channel: path(versions.yml)
}
