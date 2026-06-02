#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: EnrichmentBrowser
// The EnrichmentBrowser package implements essential functionality for the enrichment analysis of gene
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/EnrichmentBrowser/inst/doc/EnrichmentBrowser.R
// Upstream  : ALL, airway
// Downstream: none
//
// Install: BiocManager::install("EnrichmentBrowser")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ENRICHMENTBROWSER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-enrichmentbrowser"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-enrichmentbrowser:2.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-enrichmentbrowser:2.36.0--r44_0'}"

    input:
    tuple val(meta), path(summarizedexperiment)

    output:
    tuple val(meta), path("${meta.id}_enrichmentbrowser_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_enrichmentbrowser_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_enrichmentbrowser_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(EnrichmentBrowser)
    library(jsonlite)


    # --- Include = False [] ---
    # Key functions: set, jpeg, readSE, extdata, exprs.tab, colData.tab, rowData.tab
    knitr::opts_chunk$set(
      collapse = TRUE,
      eval = TRUE,
      comment = "#>",
      dev = "jpeg"
    )
    library(EnrichmentBrowser)
    data.dir <- system.file("extdata", package = "EnrichmentBrowser")
    exprs.file <- file.path(data.dir, "exprs.tab")
    cdat.file <- file.path(data.dir, "colData.tab")
    rdat.file <- file.path(data.dir, "rowData.tab")
    se <- readSE(exprs.file, cdat.file, rdat.file)
    eset <- as(se, "ExpressionSet")

    # --- Eset2sexp [] ---
    # Key functions: exprs, probe2gene, rowData, rowSums, assay, normalize, par, ifelse
    se <- as(eset, "SummarizedExperiment")

    ## ----load-ALL-----------------------------------------------------------------
    library(ALL) 
    data(ALL)

    ## ----subset-ALL---------------------------------------------------------------
    ind.bs <- grep("^B", ALL$BT)
    ind.mut <- which(ALL$mol.biol %in% c("BCR/ABL", "NEG"))
    sset <- intersect(ind.bs, ind.mut)
    allSE <- probe2gene(all.eset)
    head(rownames(allSE))

    ## ----show-probe2gene----------------------------------------------------------
    rowData(se)

    ## ----load-airway--------------------------------------------------------------
    library(airway) 
    data(airway)


    # --- Sbea Methods [] ---
    # Key functions: sbeaMethods, sbea, gsRanking, ora, normalize, vst, gsea
    sbeaMethods()
    sbea.res <- sbea(method = "ora", se = allSE, gs = hsa.gs, perm = 0, alpha = 0.1) 
    gsRanking(sbea.res)
    airSE <- normalize(airSE, norm.method = "vst")

    ## ----gsea-rseq, eval=FALSE----------------------------------------------------
    #  air.res <- sbea(method = "gsea", se = airSE, gs = hsa.gs)
    #  gsRanking(sbea.res)

    # --- Fullrank [] ---
    # Key functions: gsRanking, eaBrowse, compileGRN, hsa, kegg, nbeaMethods
    gsRanking(sbea.res, signif.only = FALSE)
    #   eaBrowse(sbea.res)

    ## ----compile-grn--------------------------------------------------------------
    hsa.grn <- compileGRN(org="hsa", db="kegg")
    head(hsa.grn)
    nbeaMethods()

    # --- Nbea [] ---
    # Key functions: nbea, gsRanking, par, ggeaGraph, ggeaGraphLegend, ggea, hsa05217_Basal_cell_carcinoma, function
    nbea.res <- nbea(method="ggea", se=allSE, gs=hsa.gs, grn=hsa.grn) 
    gsRanking(nbea.res)

    ## ----ggea-graph, fig.width=12, fig.height=6-----------------------------------
    par(mfrow=c(1,2))
    ggeaGraph( gs=hsa.gs[["hsa05217_Basal_cell_carcinoma"]], grn=hsa.grn, se=allSE) 
    ggeaGraphLegend()
    dummySBEA <- function(se, gs) {
       sig.ps <- sample(seq(0, 0.05, length = 1000), 5) 
       insig.ps <- sample(seq(0.1, 1, length = 1000), length(gs) - 5) 
       ps <- sample(c(sig.ps, insig.ps), length(gs)) 
       names(ps) <- names(gs) 
       return(ps)
     }
    sbea.res2 <- sbea(method = dummySBEA, se = allSE, gs = hsa.gs) 
    gsRanking(sbea.res2)

    # --- Combine [] ---
    # Key functions: combResults, eaBrowse, ebrowser, configEBrowser, ora, ggea, hsa, greater
    res.list <- list(sbea.res, nbea.res) 
    comb.res <- combResults(res.list)

    ## ----browse-comb, eval=FALSE--------------------------------------------------
    #  eaBrowse(comb.res, graph.view=hsa.grn, nr.show=5)

    ## ----all-in-one, eval=FALSE---------------------------------------------------
    #  ebrowser( meth=c("ora", "ggea"), exprs=exprs.file, cdat=cdat.file, rdat=rdat.file, org="hsa", gs=hsa.gs, grn=hsa.grn, comb=TRUE, nr.show=5)

    ## ----config-set---------------------------------------------------------------
    deTable <- matrix(c(28, 142, 501, 12000), 
                      nrow = 2, 
                      dimnames = list(c("DE", "Not.DE"), c("In.gene.set", "Not.in.gene.set"))) 
    deTable
    fisher.test(deTable, alternative = "greater")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_enrichmentbrowser_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_enrichmentbrowser_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_enrichmentbrowser_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ENRICHMENTBROWSER:", paste0("    enrichmentbrowser: ", packageVersion("EnrichmentBrowser"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_enrichmentbrowser_results.csv
    touch ${prefix}_enrichmentbrowser_output.rds
    echo "BIOC_ENRICHMENTBROWSER:" > versions.yml
    echo "    enrichmentbrowser: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ENRICHMENTBROWSER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(summarizedexperiment) ]

    main:
    BIOC_ENRICHMENTBROWSER(ch_input)

    emit:
    results  = BIOC_ENRICHMENTBROWSER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ENRICHMENTBROWSER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ENRICHMENTBROWSER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ENRICHMENTBROWSER.out.versions  // channel: path(versions.yml)
}
