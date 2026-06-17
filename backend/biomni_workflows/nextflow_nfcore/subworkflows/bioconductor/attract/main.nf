#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: attract — microarray_attractor_analysis
// Identify core attractor pathways, synexpression groups, correlated partner genes, and functional enrichment from microarray gene expression data.
// Input: exprs.dat, samp.info
// Container: quay.io/biocontainers/bioconductor-attract:1.62.0--r45hdfd78af_0
// R packages: annot_pkg, attract
// Bioconductor: 3.20 | R: 4.4
// Requires: attract
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load data and construct ExpressionSet
//  * 2. [Core Analysis] Find core attractor pathway modules
//  * 3. [Core Analysis] Filter out flat or uninformative genes
//  * 4. [Core Analysis] Find synexpression groups for a pathway or top pathways
//  * 5. [Visualization & Output] Plot synexpression group profiles
//  * 6. [Core Analysis] Find correlated partner genes across the genome
//  * 7. [Core Analysis] Calculate functional enrichment of synexpression groups

nextflow.enable.dsl = 2

process BIOC_ATTRACT_MICROARRAY_ATTRACTOR_ANALYSIS {
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
    .bm_deps <- c("annot_pkg", "attract")
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
    
    # Parse command line arguments for the annotation package
    args <- commandArgs(trailingOnly = TRUE)
    if (length(args) == 0) {
      stop("Error: Please provide the annotation package name as a command-line argument.")
    }
    annot_pkg <- args[1]
    
    # Load required libraries
    library(attract)
    library(annot_pkg, character.only = TRUE)
    
    # 1. Load data and construct ExpressionSet from user input files
    if (!file.exists("exprs.dat")) {
      stop("Error: 'exprs.dat' not found in the working directory.")
    }
    if (!file.exists("samp.info")) {
      stop("Error: 'samp.info' not found in the working directory.")
    }
    
    # Read the expression matrix and sample info
    exprs.dat <- as.matrix(read.table("exprs.dat", header = TRUE, row.names = 1, sep = "", check.names = FALSE))
    samp.info <- read.table("samp.info", header = TRUE, row.names = 1, sep = "", check.names = FALSE)
    
    # Construct the ExpressionSet object
    loring.eset <- new("ExpressionSet")
    loring.eset@assayData <- new.env()
    assign("exprs", exprs.dat, loring.eset@assayData)
    p.eset <- new("AnnotatedDataFrame", data = samp.info)
    loring.eset@phenoData <- p.eset
    
    # 2. Find core attractor pathway modules
    message("Finding core attractor pathway modules...")
    attractor.states <- findAttractors(loring.eset, "celltype", 
                                       annotation=annot_pkg, 
                                       database="KEGG", analysis="microarray",
                                       databaseGeneFormat=NULL, expressionSetGeneFormat=NULL)
    
    # Save ranked pathways to CSV
    write.csv(attractor.states@rankedPathways, file = "ranked_pathways.csv", row.names = FALSE)
    saveRDS(attractor.states, file = "attractor_states.rds")
    
    # 3. Filter out flat or uninformative genes
    message("Removing flat or uninformative genes...")
    remove.these.genes <- removeFlatGenes(loring.eset, "celltype", 
                                          contrasts=NULL, limma.cutoff=0.05)
    
    # Save the list of flat genes to be removed
    writeLines(remove.these.genes, con = "removed_flat_genes.txt")
    
    # 4. Find synexpression groups for a pathway or top pathways
    top_pathway <- attractor.states@rankedPathways[1, 1]
    message(sprintf("Finding synexpression groups for top pathway (%s)...", top_pathway))
    top.syn <- findSynexprs(top_pathway, attractor.states, "celltype", remove.these.genes)
    saveRDS(top.syn, file = "top_synexpression.rds")
    
    message("Finding synexpression groups for top 5 pathways...")
    top5.syn <- findSynexprs(attractor.states@rankedPathways[1:5,1], 
                             attractor.states, "celltype", 
                             removeGenes=remove.these.genes)
    saveRDS(top5.syn, file = "top5_synexpression.rds")
    
    # 5. Plot synexpression group profiles
    message("Plotting synexpression group profiles...")
    pdf("synexpression_plots.pdf", width = 8, height = 8)
    num_groups <- length(top.syn@groups)
    grid_size <- ceiling(sqrt(num_groups))
    par(mfrow=c(grid_size, grid_size)) 
    pretty.col <- rainbow(num_groups) 
    for( i in 1:num_groups ){
      plotsynexprs(top.syn, index=i, 
                   main=paste("Synexpression Group ", i, sep=""),
                   col=pretty.col[i])
    }
    dev.off()
    
    # 6. Find correlated partner genes across the genome
    message("Finding correlated partner genes...")
    top.cor <- findCorrPartners(top.syn, loring.eset, remove.these.genes)
    saveRDS(top.cor, file = "top_correlated_partners.rds")
    
    # Save sizes of correlated partner groups
    cor_sizes <- data.frame(
      Group = seq_along(top.cor@groups),
      Size = sapply(top.cor@groups, length)
    )
    write.csv(cor_sizes, file = "top_cor_partner_sizes.csv", row.names = FALSE)
    
    # 7. Calculate functional enrichment of synexpression groups
    message("Calculating functional enrichment...")
    top.func <- calcFuncSynexprs(top.syn, attractor.states, "CC", 
                                  annotation=annot_pkg,
                                  analysis="microarray", expressionSetGeneFormat=NULL)
    saveRDS(top.func, file = "top_functional_enrichment.rds")
    
    message("Workflow completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_ATTRACT_MICROARRAY_ATTRACTOR_ANALYSIS":',
        paste0('    attract: ', as.character(packageVersion('attract')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_microarray_attractor_analysis.csv versions.yml
    """
}

workflow BIOC_ATTRACT_MICROARRAY_ATTRACTOR_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exprs.dat, samp.info ] ]

    main:
    BIOC_ATTRACT_MICROARRAY_ATTRACTOR_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ATTRACT_MICROARRAY_ATTRACTOR_ANALYSIS.out.tables
    plots    = BIOC_ATTRACT_MICROARRAY_ATTRACTOR_ANALYSIS.out.plots
    objects  = BIOC_ATTRACT_MICROARRAY_ATTRACTOR_ANALYSIS.out.objects
    versions = BIOC_ATTRACT_MICROARRAY_ATTRACTOR_ANALYSIS.out.versions
}
