#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tRanslatome — translatome_analysis_workflow
// Identify differentially expressed genes (DEGs) at two expression levels (transcriptome and translatome), perform GO enrichment on the DEGs, and compare the enri
// Input: expressionMatrix
// Container: quay.io/biocontainers/bioconductor-translatome:1.48.0--r45hdfd78af_0
// R packages: tRanslatome
// Bioconductor: 3.20 | R: 4.4
// Requires: tRanslatome
// Visualizations: heatmap (ComplexHeatmap), scatter plot, MA plot, heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize the TranslatomeDataset object using newTranslatomeDataset()
//  * 2. [Core Analysis] Identify differentially expressed genes (DEGs) at both expression levels using computeDEGs()
//  * 3. [Core Analysis] Perform Gene Ontology (GO) enrichment analysis on the identified DEGs using GOEnrichment()
//  * 4. [Core Analysis] Compare the enriched biological themes between the two expression levels using GOComparison()

nextflow.enable.dsl = 2

process BIOC_TRANSLATOME_TRANSLATOME_ANALYSIS_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("tRanslatome")
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
        
        # Load the required library
        library(tRanslatome)
        
        # 1. Read the user input file 'expressionMatrix' from the working directory
        # We support RDS, CSV, or TSV formats for the expressionMatrix file.
        expressionMatrix <- NULL
        
        if (file.exists("expressionMatrix")) {
          expressionMatrix <- tryCatch({
            readRDS("expressionMatrix")
          }, error = function(e) {
            tryCatch({
              as.matrix(read.csv("expressionMatrix", row.names = 1, check.names = FALSE))
            }, error = function(e2) {
              as.matrix(read.delim("expressionMatrix", row.names = 1, check.names = FALSE))
            })
          })
        } else if (file.exists("expressionMatrix.csv")) {
          expressionMatrix <- as.matrix(read.csv("expressionMatrix.csv", row.names = 1, check.names = FALSE))
        } else if (file.exists("expressionMatrix.tsv")) {
          expressionMatrix <- as.matrix(read.delim("expressionMatrix.tsv", row.names = 1, check.names = FALSE))
        } else if (file.exists("expressionMatrix.rds")) {
          expressionMatrix <- readRDS("expressionMatrix.rds")
        } else {
          stop("Required input file 'expressionMatrix' (or with .csv/.tsv/.rds extension) not found in the working directory.")
        }
        
        # Ensure expressionMatrix is indeed a matrix
        if (!is.matrix(expressionMatrix)) {
          expressionMatrix <- as.matrix(expressionMatrix)
        }
        
        # 2. Initialize the TranslatomeDataset object
        # Dynamically assign columns to the 4 required conditions assuming an even split
        cols <- colnames(expressionMatrix)
        n_cols <- length(cols)
        chunk_size <- n_cols %/% 4
        
        cond.a <- cols[1:chunk_size]
        cond.b <- cols[(chunk_size + 1):(2 * chunk_size)]
        cond.c <- cols[(2 * chunk_size + 1):(3 * chunk_size)]
        cond.d <- cols[(3 * chunk_size + 1):n_cols]
        
        translatome.analysis <- newTranslatomeDataset(expressionMatrix, 
        			cond.a, 
        			cond.b, 
        			cond.c, 
        			cond.d, 
        			label.level= c("transcriptome", "translatome"), 
        			label.condition=c("undifferentiated", "differentiated"))
        
        # 3. Identify differentially expressed genes (DEGs)
        limma.DEGs <- computeDEGs(translatome.analysis, 
        													 method= "limma", mult.cor=TRUE) 
        
        # 4. Perform Gene Ontology (GO) enrichment analysis
        CCEnrichment <- GOEnrichment(limma.DEGs,ontology="CC", classOfDEGs="up",
        															test.method="elim", test.threshold = 0.05)
        
        # 5. Compare the enriched biological themes
        CCComparison <- GOComparison(CCEnrichment)
        
        # 6. Save meaningful results and generate output files
        # Save R objects
        saveRDS(translatome.analysis, "translatome_analysis.rds")
        saveRDS(limma.DEGs, "limma_DEGs.rds")
        saveRDS(CCEnrichment, "CCEnrichment.rds")
        saveRDS(CCComparison, "CCComparison.rds")
        
        # Export DEGs table to CSV if accessible
        tryCatch({
          if (is(limma.DEGs, "DEGs")) {
            degs_table <- NULL
            if (.hasSlot(limma.DEGs, "DEGs.table")) {
              degs_table <- limma.DEGs@DEGs.table
            } else if (exists("getDEGs")) {
              degs_table <- getDEGs(limma.DEGs)
            }
            if (!is.null(degs_table)) {
              write.csv(degs_table, "limma_DEGs_table.csv", row.names = TRUE)
            }
          }
        }, error = function(e) {
          warning("Could not export DEGs table to CSV: ", e\$message)
        })
        
        # Generate diagnostic and comparison plots
        tryCatch({
          Scatterplot(limma.DEGs, outputformat="pdf")
        }, error = function(e) {
          pdf("Scatterplot.pdf")
          try(Scatterplot(limma.DEGs))
          dev.off()
        })
        
        tryCatch({
          Histogram(limma.DEGs, outputformat="pdf")
        }, error = function(e) {
          pdf("Histogram.pdf")
          try(Histogram(limma.DEGs))
          dev.off()
        })
        
        tryCatch({
          MAplot(limma.DEGs, outputformat="pdf")
        }, error = function(e) {
          pdf("MAplot.pdf")
          try(MAplot(limma.DEGs))
          dev.off()
        })
        
        tryCatch({
          SDplot(limma.DEGs, outputformat="pdf")
        }, error = function(e) {
          pdf("SDplot.pdf")
          try(SDplot(limma.DEGs))
          dev.off()
        })
        
        tryCatch({
          CVplot(limma.DEGs, outputformat="pdf")
        }, error = function(e) {
          pdf("CVplot.pdf")
          try(CVplot(limma.DEGs))
          dev.off()
        })
        
        tryCatch({
          Radar(CCEnrichment, ontology="CC", outputformat="pdf")
        }, error = function(e) {
          pdf("Radar_CC.pdf")
          try(Radar(CCEnrichment, ontology="CC"))
          dev.off()
        })
        
        tryCatch({
          Heatmap(CCEnrichment, ontology="CC", outputformat="pdf")
        }, error = function(e) {
          pdf("Heatmap_CC.pdf")
          try(Heatmap(CCEnrichment, ontology="CC"))
          dev.off()
        })
        
        # Identity and Similarity comparison plots
        pdf("IdentityPlot.pdf")
        try(IdentityPlot(CCComparison))
        dev.off()
        
        pdf("SimilarityPlot.pdf")
        try(SimilarityPlot(CCComparison))
        dev.off()

    writeLines(c(
        '"BIOC_TRANSLATOME_TRANSLATOME_ANALYSIS_WORKFLOW":',
        paste0('    tRanslatome: ', as.character(packageVersion('tRanslatome')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_translatome_analysis_workflow.csv versions.yml
    """
}

workflow BIOC_TRANSLATOME_TRANSLATOME_ANALYSIS_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expressionMatrix ] ]

    main:
    BIOC_TRANSLATOME_TRANSLATOME_ANALYSIS_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_TRANSLATOME_TRANSLATOME_ANALYSIS_WORKFLOW.out.tables
    plots    = BIOC_TRANSLATOME_TRANSLATOME_ANALYSIS_WORKFLOW.out.plots
    objects  = BIOC_TRANSLATOME_TRANSLATOME_ANALYSIS_WORKFLOW.out.objects
    versions = BIOC_TRANSLATOME_TRANSLATOME_ANALYSIS_WORKFLOW.out.versions
}
