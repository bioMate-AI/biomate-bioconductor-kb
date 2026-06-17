#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: topGO — score_based_expression_enrichment
// Perform GO enrichment analysis using continuous gene-wise scores (such as differential expression p-values) and a chip annotation database.
// Input: ALL, y
// Container: quay.io/biocontainers/bioconductor-topgo:2.62.0--r45hdfd78af_0
// R packages: Biobase, genefilter, topGO, package
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, genefilter, package, topGO
// Visualizations: density plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read User Input Files
//  * 2. [Visualization & Output] Filter low-expression and low-variance probes
//  * 3. [Visualization & Output] Compute gene-wise p-values for differential expression
//  * 4. [Visualization & Output] Define a selection function to identify significant genes
//  * 5. [Visualization & Output] Initialize the topGOdata object using a Bioconductor chip
//  * 6. [Visualization & Output] Run multiple enrichment tests (classic Fisher, classic
//  * 7. [Visualization & Output] Generate a comparative summary table of the results
//  * 8. [Visualization & Output] Visualize gene score distributions and the significant GO

nextflow.enable.dsl = 2

process BIOC_TOPGO_SCORE_BASED_EXPRESSION_ENRICHMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("Biobase", "genefilter", "topGO", "package")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(topGO)
    library(genefilter)
    library(Biobase)
    
    # -----------------------------------------------------------------------------
    # --- Read User Input Files ---
    # -----------------------------------------------------------------------------
    # Read ALL (ExpressionSet)
    if (file.exists("ALL.rds")) {
      ALL <- readRDS("ALL.rds")
    } else if (file.exists("ALL.RData")) {
      env <- new.env()
      load("ALL.RData", envir = env)
      if ("ALL" %in% names(env)) {
        ALL <- env\$ALL
      } else {
        stop("ALL object not found in ALL.RData")
      }
    } else {
      stop("Required input file 'ALL.rds' or 'ALL.RData' not found in the working directory.")
    }
    
    # Read y (integer vector of binary class labels)
    if (file.exists("y.rds")) {
      y <- readRDS("y.rds")
    } else if (file.exists("y.RData")) {
      env <- new.env()
      load("y.RData", envir = env)
      if ("y" %in% names(env)) {
        y <- env\$y
      } else {
        stop("y object not found in y.RData")
      }
    } else {
      stop("Required input file 'y.rds' or 'y.RData' not found in the working directory.")
    }
    
    # -----------------------------------------------------------------------------
    # --- Filter low-expression and low-variance probes ---
    # -----------------------------------------------------------------------------
    selProbes <- genefilter(ALL, filterfun(pOverA(0.20, log2(100)), function(x) (IQR(x) > 0.25)))
    eset <- ALL[selProbes, ]
    
    # -----------------------------------------------------------------------------
    # --- Compute gene-wise p-values for differential expression ---
    # -----------------------------------------------------------------------------
    geneList <- getPvalues(exprs(eset), classlabel = y, alternative = "greater")
    
    # -----------------------------------------------------------------------------
    # --- Define a selection function to identify significant genes ---
    # -----------------------------------------------------------------------------
    topDiffGenes <- function(allScore) {
      return(allScore < 0.01)
    }
    
    # -----------------------------------------------------------------------------
    # --- Initialize the topGOdata object using a Bioconductor chip ---
    # -----------------------------------------------------------------------------
    affyLib <- paste(annotation(ALL), "db", sep = ".")
    library(package = affyLib, character.only = TRUE)
    
    GOdata <- new("topGOdata", 
                  description = "GO analysis of ALL data; B-cell vs T-cell",
                  ontology = "BP",
                  allGenes = geneList,
                  geneSel = topDiffGenes,
                  annot = annFUN.db,
                  nodeSize = 5,
                  affyLib = affyLib)
    
    # -----------------------------------------------------------------------------
    # --- Run multiple enrichment tests (classic Fisher, classic ---
    # -----------------------------------------------------------------------------
    resultFis <- runTest(GOdata, algorithm = "classic", statistic = "fisher")
    resultKS <- runTest(GOdata, algorithm = "classic", statistic = "ks")
    resultKS.elim <- runTest(GOdata, algorithm = "elim", statistic = "ks")
    
    # -----------------------------------------------------------------------------
    # --- Generate a comparative summary table of the results ---
    # -----------------------------------------------------------------------------
    allRes <- GenTable(GOdata, classic = resultFis, KS = resultKS, elim = resultKS.elim, orderBy = "elim", topNodes = 20)
    write.csv(allRes, file = "GO_enrichment_results.csv", row.names = FALSE)
    
    # -----------------------------------------------------------------------------
    # --- Visualize gene score distributions and the significant GO ---
    # -----------------------------------------------------------------------------
    goID <- allRes[1, "GO.ID"]
    
    # Save group density plot
    pdf("GO_group_density.pdf")
    tryCatch({
      print(showGroupDensity(GOdata, goID, ranks = TRUE))
    }, error = function(e) {
      warning("Could not generate group density plot: ", e\$message)
    })
    dev.off()
    
    # Print genes annotated to the top GO term
    gt <- printGenes(GOdata, whichTerms = goID, chip = affyLib, numChar = 40)
    write.csv(gt, file = "top_GO_genes.csv", row.names = FALSE)
    
    # Save significant nodes subgraph plot
    pdf("GO_sig_nodes.pdf")
    tryCatch({
      showSigOfNodes(GOdata, score(resultKS.elim), firstSigNodes = 5, useInfo = 'all')
    }, error = function(e) {
      warning("Could not generate significant nodes plot: ", e\$message)
    })
    dev.off()
    
    # Save R objects for downstream analysis
    saveRDS(GOdata, file = "GOdata.rds")
    saveRDS(resultFis, file = "resultFis.rds")
    saveRDS(resultKS, file = "resultKS.rds")
    saveRDS(resultKS.elim, file = "resultKS_elim.rds")

    writeLines(c(
        '"BIOC_TOPGO_SCORE_BASED_EXPRESSION_ENRICHMENT":',
        paste0('    topGO: ', as.character(packageVersion('topGO')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_score_based_expression_enrichment.csv versions.yml
    """
}

workflow BIOC_TOPGO_SCORE_BASED_EXPRESSION_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ALL, y ] ]

    main:
    BIOC_TOPGO_SCORE_BASED_EXPRESSION_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_TOPGO_SCORE_BASED_EXPRESSION_ENRICHMENT.out.tables
    plots    = BIOC_TOPGO_SCORE_BASED_EXPRESSION_ENRICHMENT.out.plots
    objects  = BIOC_TOPGO_SCORE_BASED_EXPRESSION_ENRICHMENT.out.objects
    versions = BIOC_TOPGO_SCORE_BASED_EXPRESSION_ENRICHMENT.out.versions
}
