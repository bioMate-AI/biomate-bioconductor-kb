#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: FGNet — topgo_gene_list_to_network
// Perform GO enrichment analysis on a gene list offline and build a functional network.
// Input: genesYeast, genesYeastExpr
// Container: quay.io/biocontainers/bioconductor-fgnet:3.44.0--r45hdfd78af_0
// R packages: FGNet, knitr, org.Sc.sgd.db, topGO
// Bioconductor: 3.20 | R: 4.4
// Requires: FGNet, org.Sc.sgd.db, topGO
// Visualizations: network plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Perform FEA using fea_topGO()
//  * 2. [Visualization & Output] Generate an HTML report using FGNet_report()
//  * 3. [Core Analysis] Convert results to incidence matrices using fea2incidMat()
//  * 4. [Visualization & Output] Plot the network using functionalNetwork()

nextflow.enable.dsl = 2

process BIOC_FGNET_TOPGO_GENE_LIST_TO_NETWORK {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("FGNet", "knitr", "org.Sc.sgd.db", "topGO")
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
    library(FGNet)
    library(org.Sc.sgd.db)
    library(topGO)
    
    # Read user input files from the working directory
    if (file.exists("genesYeast.txt")) {
      genesYeast <- readLines("genesYeast.txt")
    } else if (file.exists("genesYeast.csv")) {
      genesYeast <- read.csv("genesYeast.csv", header=FALSE, stringsAsFactors=FALSE)[[1]]
    } else {
      stop("Required input file 'genesYeast.txt' or 'genesYeast.csv' not found in the working directory.")
    }
    
    # Clean genesYeast (remove empty lines/spaces)
    genesYeast <- trimws(genesYeast)
    genesYeast <- genesYeast[genesYeast != ""]
    
    # Read optional gene expression values
    genesYeastExpr <- NULL
    if (file.exists("genesYeastExpr.txt")) {
      expr_df <- read.table("genesYeastExpr.txt", header=TRUE, sep="\t", stringsAsFactors=FALSE)
      genesYeastExpr <- setNames(as.numeric(expr_df[[2]]), expr_df[[1]])
    } else if (file.exists("genesYeastExpr.csv")) {
      expr_df <- read.csv("genesYeastExpr.csv", header=TRUE, stringsAsFactors=FALSE)
      genesYeastExpr <- setNames(as.numeric(expr_df[[2]]), expr_df[[1]])
    }
    
    # 1. Perform FEA using fea_topGO()
    feaResults_topGO <- fea_topGO(genesYeast, geneIdType="GENENAME", organism="Sc")
    
    # Save FEA results object
    saveRDS(feaResults_topGO, "feaResults_topGO.rds")
    
    # 2. Generate an HTML report using FGNet_report()
    # Note: This function writes HTML and image files directly to the working directory
    FGNet_report(feaResults_topGO, geneExpr=genesYeastExpr)
    
    # 3. Convert results to incidence matrices using fea2incidMat()
    incidMat <- fea2incidMat(feaResults_topGO)
    
    # Save incidence matrix object and export matrices to CSV
    saveRDS(incidMat, "incidMat.rds")
    if (!is.null(incidMat\$clustersMatrix)) {
      write.csv(as.matrix(incidMat\$clustersMatrix), "clustersMatrix.csv", row.names=TRUE)
    }
    if (!is.null(incidMat\$metagroupsMatrix)) {
      write.csv(as.matrix(incidMat\$metagroupsMatrix), "metagroupsMatrix.csv", row.names=TRUE)
    }
    
    # 4. Plot the network using functionalNetwork()
    # Save the static network plot to a PDF file
    pdf("functional_network.pdf", width=10, height=8)
    functionalNetwork(incidMat, geneExpr=genesYeastExpr, plotTitleSub="Default gene view")
    dev.off()

    writeLines(c(
        '"BIOC_FGNET_TOPGO_GENE_LIST_TO_NETWORK":',
        paste0('    FGNet: ', as.character(packageVersion('FGNet')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_topgo_gene_list_to_network.csv versions.yml
    """
}

workflow BIOC_FGNET_TOPGO_GENE_LIST_TO_NETWORK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genesYeast, genesYeastExpr ] ]

    main:
    BIOC_FGNET_TOPGO_GENE_LIST_TO_NETWORK(ch_input)

    emit:
    tables   = BIOC_FGNET_TOPGO_GENE_LIST_TO_NETWORK.out.tables
    plots    = BIOC_FGNET_TOPGO_GENE_LIST_TO_NETWORK.out.plots
    objects  = BIOC_FGNET_TOPGO_GENE_LIST_TO_NETWORK.out.objects
    versions = BIOC_FGNET_TOPGO_GENE_LIST_TO_NETWORK.out.versions
}
