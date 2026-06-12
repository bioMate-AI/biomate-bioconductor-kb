#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: geneRecommender — targeted_gene_recommendation
// Identify and rank genes coexpressed with a query set of genes in microarray data, with options for cross-validation and custom scoring.
// Input: geneData, my.query
// Container: quay.io/biocontainers/bioconductor-generecommender:1.82.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: geneRecommender
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Normalize the expression matrix using gr.normalize (and optionally transform with qnorm)
//  * 2. [Core Analysis] Perform targeted clustering and ranking using gr.main
//  * 3. [Core Analysis] Validate the query genes using leave-one-out cross-validation with gr.cv

nextflow.enable.dsl = 2

process BIOC_GENERECOMMENDER_TARGETED_GENE_RECOMMENDATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("geneRecommender")
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
        
        # -----------------------------------------------------------------------------
        # Pipeline: targeted_gene_recommendation using geneRecommender
        # Description: Identify and rank genes coexpressed with a query set of genes
        #              in microarray data, with cross-validation and custom scoring.
        # -----------------------------------------------------------------------------
        
        # Load required library
        library(geneRecommender)
        
        # -----------------------------------------------------------------------------
        # Stage 0: Read User Input Files
        # -----------------------------------------------------------------------------
        
        # 1. Read geneData (microarray expression matrix: genes as rows, experiments as columns)
        if (file.exists("geneData.rds")) {
          geneData <- readRDS("geneData.rds")
        } else if (file.exists("geneData.csv")) {
          geneData <- as.matrix(read.csv("geneData.csv", row.names = 1, check.names = FALSE))
        } else if (file.exists("geneData.tsv")) {
          geneData <- as.matrix(read.delim("geneData.tsv", row.names = 1, check.names = FALSE))
        } else if (file.exists("geneData.txt")) {
          geneData <- as.matrix(read.table("geneData.txt", header = TRUE, row.names = 1, check.names = FALSE))
        } else {
          stop("Error: geneData file not found in the working directory (expected geneData.rds, geneData.csv, geneData.tsv, or geneData.txt)")
        }
        
        # Ensure geneData is a numeric matrix
        if (!is.matrix(geneData) || !is.numeric(geneData)) {
          geneData <- as.matrix(geneData)
          mode(geneData) <- "numeric"
        }
        
        # 2. Read my.query (character vector of query gene/probeset IDs)
        if (file.exists("my.query.rds")) {
          my.query <- readRDS("my.query.rds")
        } else if (file.exists("my.query.txt")) {
          my.query <- readLines("my.query.txt")
        } else if (file.exists("my.query.csv")) {
          my.query <- read.csv("my.query.csv", header = FALSE)[, 1]
        } else {
          stop("Error: my.query file not found in the working directory (expected my.query.rds, my.query.txt, or my.query.csv)")
        }
        
        my.query <- as.character(my.query)
        
        # Validate that query genes exist in the dataset
        missing_queries <- setdiff(my.query, rownames(geneData))
        if (length(missing_queries) > 0) {
          warning(paste("The following query genes are not present in geneData:", paste(missing_queries, collapse = ", ")))
          my.query <- intersect(my.query, rownames(geneData))
        }
        
        if (length(my.query) == 0) {
          stop("Error: None of the query genes are present in geneData.")
        }
        
        # -----------------------------------------------------------------------------
        # Stage 1: Normalize the Expression Matrix
        # -----------------------------------------------------------------------------
        
        # Normalize dataset so that expression values are distributed uniformly between -1 and 1
        normalized.data <- gr.normalize(geneData)
        
        # -----------------------------------------------------------------------------
        # Stage 2: Perform Targeted Clustering and Ranking (Default)
        # -----------------------------------------------------------------------------
        
        # Run main recommendation algorithm with default parameters
        res_default <- gr.main(normalized.data, my.query, ngenes = 10)
        
        # Save default results
        write.csv(res_default\$main.result, "main_result_default.csv", row.names = FALSE)
        
        # -----------------------------------------------------------------------------
        # Stage 3: Validate Query Genes using Leave-One-Out Cross-Validation
        # -----------------------------------------------------------------------------
        
        # Perform cross-validation to evaluate query performance and identify outliers
        cv_res <- gr.cv(normalized.data, my.query)
        
        # Save cross-validation results
        cv_df <- data.frame(Query_Gene = my.query, CV_Rank = cv_res)
        write.csv(cv_df, "cv_results.csv", row.names = FALSE)
        
        # -----------------------------------------------------------------------------
        # Stage 4: Alternative Normalization (Standard Normal Distribution)
        # -----------------------------------------------------------------------------
        
        # Transform normalized data to standard normal distribution using qnorm
        normal.normalized.data <- qnorm((normalized.data + 1)/2)
        
        # Run recommendation algorithm on standard normal normalized data
        res_qnorm <- gr.main(normal.normalized.data, my.query, ngenes = 10)
        
        # Save alternative normalization results
        write.csv(res_qnorm\$main.result, "main_result_qnorm.csv", row.names = FALSE)
        
        # -----------------------------------------------------------------------------
        # Stage 5: Custom Scoring Function
        # -----------------------------------------------------------------------------
        
        # Define custom scoring function
        my.fun.1 <- function(input.vector){
          sum(input.vector^(1/2), na.rm = T)
        }
        
        # Run recommendation algorithm with custom scoring function
        res_custom_fun <- gr.main(normalized.data, my.query, ngenes = 10, fun = my.fun.1)
        
        # Save custom scoring results
        write.csv(res_custom_fun\$main.result, "main_result_custom_fun.csv", row.names = FALSE)
        
        # -----------------------------------------------------------------------------
        # Stage 6: Detailed Output with Extra Metrics
        # -----------------------------------------------------------------------------
        
        # Run recommendation algorithm requesting extra metrics
        options(digits = 2)
        res_extra <- gr.main(normalized.data, my.query, ngenes = 10, extra = T)
        
        # Save complete extra results list as RDS
        saveRDS(res_extra, "main_result_extra.rds")
        
        # Export individual components of the extra results to CSV files
        write.csv(res_extra\$main.result, "main_result_extra_table.csv", row.names = FALSE)
        
        if (!is.null(res_extra\$fifty.percent.recall)) {
          write.csv(data.frame(fifty_percent_recall = res_extra\$fifty.percent.recall), 
                    "fifty_percent_recall.csv", row.names = FALSE)
        }
        
        if (!is.null(res_extra\$experiments.included)) {
          write.csv(data.frame(Experiment = res_extra\$experiments.included), 
                    "experiments_included.csv", row.names = FALSE)
        }
        
        if (!is.null(res_extra\$experiments.excluded)) {
          write.csv(data.frame(Experiment = res_extra\$experiments.excluded), 
                    "experiments_excluded.csv", row.names = FALSE)
        }
        
        if (!is.null(res_extra\$s.g.i)) {
          write.csv(data.frame(Gene = names(res_extra\$s.g.i), S_g_i = res_extra\$s.g.i), 
                    "biological_significance_sgi.csv", row.names = FALSE)
        }
        
        if (!is.null(res_extra\$z.g.i)) {
          write.csv(data.frame(Gene = names(res_extra\$z.g.i), Z_g_i = res_extra\$z.g.i), 
                    "statistical_significance_zgi.csv", row.names = FALSE)
        }
        
        if (!is.null(res_extra\$contribution)) {
          write.csv(as.data.frame(res_extra\$contribution), 
                    "experiment_contribution.csv", row.names = TRUE)
        }
        
        message("geneRecommender pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_GENERECOMMENDER_TARGETED_GENE_RECOMMENDATION":',
        paste0('    geneRecommender: ', as.character(packageVersion('geneRecommender')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_targeted_gene_recommendation.csv versions.yml
    """
}

workflow BIOC_GENERECOMMENDER_TARGETED_GENE_RECOMMENDATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ geneData, my.query ] ]

    main:
    BIOC_GENERECOMMENDER_TARGETED_GENE_RECOMMENDATION(ch_input)

    emit:
    tables   = BIOC_GENERECOMMENDER_TARGETED_GENE_RECOMMENDATION.out.tables
    plots    = BIOC_GENERECOMMENDER_TARGETED_GENE_RECOMMENDATION.out.plots
    objects  = BIOC_GENERECOMMENDER_TARGETED_GENE_RECOMMENDATION.out.objects
    versions = BIOC_GENERECOMMENDER_TARGETED_GENE_RECOMMENDATION.out.versions
}
