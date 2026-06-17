#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MLP — mlp_pathway_analysis
// Perform pathway enrichment analysis on gene expression p-values using the Mean Log P-value (MLP) method and visualize the results.
// Input: expressionSetGcrma.rda, mouse4302
// Container: quay.io/biocontainers/bioconductor-mlp:1.58.0--r45hdfd78af_0
// R packages: ann_db, annotation_pkg, AnnotationDbi, limma, MLP
// Bioconductor: 3.20 | R: 4.4
// Requires: AnnotationDbi, MLP, limma
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate gene-level p-values using limma
//  * 2. [Core Analysis] Retrieve gene sets for the target species and source using getGeneSets
//  * 3. [Core Analysis] Run the MLP pathway analysis using MLP
//  * 4. [Visualization & Output] Visualize results using plot with types "quantileCurves", "barplot", or "GOgraph"
//  * 5. [Visualization & Output] Visualize individual gene significance within a specific gene set using plotGeneSetSignificance

nextflow.enable.dsl = 2

process BIOC_MLP_MLP_PATHWAY_ANALYSIS {
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
    .bm_deps <- c("ann_db", "annotation_pkg", "AnnotationDbi", "limma", "MLP")
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
    library(MLP)
    library(limma)
    library(AnnotationDbi)
    
    # Read user input files
    # 1. Load expressionSetGcrma.rda
    if (!file.exists("expressionSetGcrma.rda")) {
      stop("Required input file 'expressionSetGcrma.rda' not found in the working directory.")
    }
    
    loaded_objs <- load("expressionSetGcrma.rda")
    # Find the ExpressionSet object among loaded objects
    eset_name <- NULL
    for (obj in loaded_objs) {
      if (inherits(get(obj), "ExpressionSet")) {
        eset_name <- obj
        break
      }
    }
    
    if (is.null(eset_name)) {
      stop("No ExpressionSet object found in 'expressionSetGcrma.rda'.")
    }
    
    expressionSetGcrma <- get(eset_name)
    
    # 2. Read annotation package name from 'mouse4302' file if it exists, otherwise default to "mouse4302"
    annotation_pkg <- "mouse4302"
    if (file.exists("mouse4302")) {
      tryCatch({
        lines <- readLines("mouse4302", warn = FALSE)
        if (length(lines) > 0 && trimws(lines[1]) != "") {
          annotation_pkg <- trimws(lines[1])
        }
      }, error = function(e) {
        warning("Could not read 'mouse4302' file, defaulting to 'mouse4302'.")
      })
    }
    
    annotation(expressionSetGcrma) <- annotation_pkg
    
    # Load the annotation package if available
    ann_db <- paste0(annotation_pkg, ".db")
    if (requireNamespace(ann_db, quietly = TRUE)) {
      library(ann_db, character.only = TRUE)
    } else if (requireNamespace(annotation_pkg, quietly = TRUE)) {
      library(annotation_pkg, character.only = TRUE)
    }
    
    # Ensure subGroup1 column exists in pData
    if (!"subGroup1" %in% colnames(pData(expressionSetGcrma))) {
      if (ncol(pData(expressionSetGcrma)) > 0) {
        pData(expressionSetGcrma)\$subGroup1 <- pData(expressionSetGcrma)[, 1]
      } else {
        pData(expressionSetGcrma)\$subGroup1 <- rep(c("WT", "KO"), length.out = ncol(expressionSetGcrma))
      }
    }
    
    # Calculate gene-level p-values using limma
    group <- as.numeric(factor(pData(expressionSetGcrma)\$subGroup1, levels = c("WT", "KO")))-1
    design <- model.matrix(~group)
    fit <- lmFit(exprs(expressionSetGcrma), design)
    fit2 <- eBayes(fit)
    results <- limma:::topTable(fit2, coef = "group", adjust.method = "fdr", number = Inf)
    pvalues <- results[,"P.Value"]
    names(pvalues) <- rownames(results)
    names(pvalues) <- sub("_at", "", names(pvalues))	
    
    # Retrieve gene sets for the target species and source using getGeneSets
    geneSet <- getGeneSets(species = "Mouse", 
    		geneSetSource = "GOCC", 
    		entrezIdentifiers = names(pvalues)
    )
    
    # Run the MLP pathway analysis using MLP
    set.seed(111)
    mlpOut <- MLP(
    		geneSet = geneSet, 
    		geneStatistic = pvalues, 
    		minGenes = 5, 
    		maxGenes = 100, 
    		rowPermutations = TRUE, 
    		nPermutations = 50, 
    		smoothPValues = TRUE, 
        probabilityVector = c(0.5, 0.9, 0.95, 0.99, 0.999, 0.9999, 0.99999), 
    		df = 9) 	
    
    # Save tabular results
    write.csv(results, "limma_results.csv", row.names = TRUE)
    write.csv(as.data.frame(mlpOut), "mlp_results.csv", row.names = TRUE)
    saveRDS(mlpOut, "mlp_results.rds")
    
    # Visualize results using plot with types "quantileCurves", "barplot", or "GOgraph"
    pdf("mlpQuantileCurves.pdf", width = 10, height = 10)
    plot(mlpOut, type = "quantileCurves")
    dev.off()
    
    pdf("mlpBarplot.pdf", width = 10, height = 10)
    op <- par(mar = c(30, 10, 6, 2))
    plot(mlpOut, type = "barplot", ylab = "-log10(gene set p-value)")
    par(op)
    dev.off()
    
    pdf("mlpGOgraph.pdf", width = 8, height = 6)
    op <- par(mar = c(0, 0, 0, 0))
    tryCatch({
      plot(mlpOut, type = "GOgraph", nRow = 10, nCutDescPath = 15)
    }, error = function(e) {
      message("Could not plot GOgraph: ", e\$message)
    })
    par(op)
    dev.off()
    
    # Visualize individual gene significance within a specific gene set using plotGeneSetSignificance
    if (nrow(mlpOut) > 0) {
      geneSetID <- rownames(mlpOut)[1]
      pdf("geneSignificance.pdf", width = 10, height = 10)
      op <- par(mar = c(25, 10, 6, 2))
      tryCatch({
        plotGeneSetSignificance(
    		    geneSet = geneSet, 
    		    geneSetIdentifier = geneSetID, 
    		    geneStatistic = pvalues, 
    		    annotationPackage = annotation(expressionSetGcrma)
        )
      }, error = function(e) {
        message("Could not plot gene set significance: ", e\$message)
      })
      par(op)
      dev.off()
    }

    writeLines(c(
        '"BIOC_MLP_MLP_PATHWAY_ANALYSIS":',
        paste0('    MLP: ', as.character(packageVersion('MLP')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mlp_pathway_analysis.csv versions.yml
    """
}

workflow BIOC_MLP_MLP_PATHWAY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expressionSetGcrma.rda, mouse4302 ] ]

    main:
    BIOC_MLP_MLP_PATHWAY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MLP_MLP_PATHWAY_ANALYSIS.out.tables
    plots    = BIOC_MLP_MLP_PATHWAY_ANALYSIS.out.plots
    objects  = BIOC_MLP_MLP_PATHWAY_ANALYSIS.out.objects
    versions = BIOC_MLP_MLP_PATHWAY_ANALYSIS.out.versions
}
