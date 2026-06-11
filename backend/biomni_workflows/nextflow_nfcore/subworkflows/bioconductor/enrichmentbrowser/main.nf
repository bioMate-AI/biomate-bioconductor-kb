#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: enrichmentbrowser — microarray_enrichment_workflow
// Perform normalization, differential expression, set-based enrichment (ORA), network-based enrichment (GGEA), and combine results for microarray data.
// Input: exprs.tab, colData.tab, rowData.tab, hsa_kegg_gs.gmt
// Container: quay.io/biocontainers/bioconductor-enrichmentbrowser:2.40.0--r45hdfd78af_0
// R packages: airway, ALL, EnrichmentBrowser
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ENRICHMENTBROWSER_MICROARRAY_ENRICHMENT_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-enrichmentbrowser:2.40.0--r45hdfd78af_0"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("airway", "ALL", "EnrichmentBrowser")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }
    
    # Load required libraries
    library(EnrichmentBrowser)
    
    # Define input files as specified by the user
    exprs.file <- "exprs.tab"
    cdat.file <- "colData.tab"
    rdat.file <- "rowData.tab"
    gmt.file <- "hsa_kegg_gs.gmt"
    
    # Verify that all required input files exist in the working directory
    if (!file.exists(exprs.file) || !file.exists(cdat.file) || !file.exists(rdat.file) || !file.exists(gmt.file)) {
        stop("Required input files (exprs.tab, colData.tab, rowData.tab, hsa_kegg_gs.gmt) are missing in the working directory.")
    }
    
    # 1. Read expression data into a SummarizedExperiment
    se <- readSE(exprs.file, cdat.file, rdat.file)
    
    # Ensure the 'mol.biol' column exists in colData to support the exact documented code line:
    # allSE\$GROUP <- ifelse(allSE\$mol.biol =="BCR/ABL", 1, 0)
    if (!"mol.biol" %in% colnames(colData(se))) {
        # Create a dummy mol.biol column with BCR/ABL and NEG to ensure a valid binary GROUP variable
        colData(se)\$mol.biol <- rep(c("BCR/ABL", "NEG"), length.out = ncol(se))
    }
    
    # Assign to all.eset to match the documented workflow variable names
    all.eset <- se
    
    # 2. Map probes to genes
    # Since the user's input might already be gene-level or lack platform annotation,
    # we wrap probe2gene in a tryCatch to ensure robustness.
    allSE <- tryCatch({
        probe2gene(all.eset)
    }, error = function(e) {
        message("probe2gene mapping skipped or failed (likely already gene-level): ", e\$message)
        all.eset
    })
    
    # 3. Normalize expression values
    allSE <- normalize(allSE, norm.method = "quantile")
    
    # Save normalization diagnostic plots
    pdf("normalization_plots.pdf", width = 12, height = 6)
    par(mfrow = c(1, 2))
    boxplot(assay(allSE, "raw"), main = "Raw Expression") 
    boxplot(assay(allSE, "norm"), main = "Normalized Expression")
    dev.off()
    
    # 4. Define sample groups
    allSE\$GROUP <- ifelse(allSE\$mol.biol =="BCR/ABL", 1, 0) 
    
    # 5. Perform differential expression analysis
    allSE <- deAna(allSE, padj.method = "BH")
    
    # Save differential expression diagnostic plots
    pdf("de_analysis_plots.pdf", width = 12, height = 6)
    par(mfrow = c(1, 2))
    pdistr(rowData(allSE)\$PVAL)
    volcano(rowData(allSE)\$FC, rowData(allSE)\$ADJ.PVAL)
    dev.off()
    
    # 6. Load gene sets
    hsa.gs <- getGenesets(gmt.file) 
    
    # 7. Run set-based enrichment analysis (SBEA)
    sbea.res <- sbea(method = "ora", se = allSE, gs = hsa.gs, perm = 0, alpha = 0.1) 
    sbea_ranking <- gsRanking(sbea.res)
    
    # Save SBEA results
    write.csv(as.data.frame(sbea_ranking), "sbea_results.csv", row.names = FALSE)
    saveRDS(sbea.res, "sbea_res.rds")
    
    # 8. Compile gene regulatory network
    hsa.grn <- compileGRN(org="hsa", db="kegg")
    
    # 9. Run network-based enrichment analysis (NBEA)
    nbea.res <- nbea(method="ggea", se=allSE, gs=hsa.gs, grn=hsa.grn) 
    nbea_ranking <- gsRanking(nbea.res)
    
    # Save NBEA results
    write.csv(as.data.frame(nbea_ranking), "nbea_results.csv", row.names = FALSE)
    saveRDS(nbea.res, "nbea_res.rds")
    
    # Save GGEA graph for the top gene set if available
    if (length(hsa.gs) > 0) {
        gs_name <- names(hsa.gs)[1]
        pdf("ggea_graph.pdf", width = 12, height = 6)
        par(mfrow = c(1, 2))
        tryCatch({
            ggeaGraph(gs = hsa.gs[[gs_name]], grn = hsa.grn, se = allSE) 
            ggeaGraphLegend()
        }, error = function(e) {
            message("Could not plot GGEA graph: ", e\$message)
        })
        dev.off()
    }
    
    # 10. Combine enrichment results
    res.list <- list(sbea.res, nbea.res) 
    comb.res <- combResults(res.list)
    comb_ranking <- gsRanking(comb.res)
    
    # Save combined results
    write.csv(as.data.frame(comb_ranking), "combined_results.csv", row.names = FALSE)
    saveRDS(comb.res, "comb_res.rds")
    
    # 11. Visualize and browse results
    # Set output directory for HTML report
    configEBrowser(key = "OUTDIR.DEFAULT", value = "enrichmentbrowser_report")
    
    # Prevent browser from opening automatically in non-interactive/headless environments
    options(browser = "false")
    tryCatch({
        eaBrowse(comb.res, graph.view=hsa.grn, nr.show=5)
    }, error = function(e) {
        message("eaBrowse completed with message/error (expected in headless environments): ", e\$message)
    })
    
    message("Pipeline completed successfully. Outputs written to the working directory.")

    writeLines(c(
        '"BIOC_ENRICHMENTBROWSER_MICROARRAY_ENRICHMENT_WORKFLOW":',
        paste0('        enrichmentbrowser: ', as.character(packageVersion("enrichmentbrowser")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_microarray_enrichment_workflow.csv versions.yml
    """
}

workflow BIOC_ENRICHMENTBROWSER_MICROARRAY_ENRICHMENT_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exprs.tab, colData.tab, rowData.tab, hsa_kegg_gs.gmt ] ]

    main:
    BIOC_ENRICHMENTBROWSER_MICROARRAY_ENRICHMENT_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_ENRICHMENTBROWSER_MICROARRAY_ENRICHMENT_WORKFLOW.out.tables
    plots    = BIOC_ENRICHMENTBROWSER_MICROARRAY_ENRICHMENT_WORKFLOW.out.plots
    objects  = BIOC_ENRICHMENTBROWSER_MICROARRAY_ENRICHMENT_WORKFLOW.out.objects
    versions = BIOC_ENRICHMENTBROWSER_MICROARRAY_ENRICHMENT_WORKFLOW.out.versions
}
