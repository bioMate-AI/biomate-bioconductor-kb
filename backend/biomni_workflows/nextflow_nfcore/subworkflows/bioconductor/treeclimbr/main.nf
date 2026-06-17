#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: treeclimbR — differential_abundance_analysis
// Find entities or subtrees whose abundance is associated with a sample phenotype.
// Input: da_lse
// Container: quay.io/biocontainers/bioconductor-treeclimbr:1.6.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: TreeSummarizedExperiment, dplyr, ggplot2, ggtree, treeclimbR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Get all node IDs using showNode
//  * 2. [Core Analysis] Aggregate counts for internal nodes using aggTSE
//  * 3. [Core Analysis] Perform differential abundance analysis for leaves and nodes using runDA
//  * 4. [Core Analysis] Extract node results using nodeResult
//  * 5. [Core Analysis] Propose aggregation candidates using getCand
//  * 6. [Core Analysis] Evaluate candidates to find the optimal aggregation level using evalCand
//  * 7. [Visualization & Output] Summarize candidates using infoCand and extract significant nodes using topNodes
//  * 8. [Core Analysis] Evaluate performance using fdr and tpr

nextflow.enable.dsl = 2

process BIOC_TREECLIMBR_DIFFERENTIAL_ABUNDANCE_ANALYSIS {
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
    .bm_deps <- c("TreeSummarizedExperiment", "treeclimbR", "dplyr", "ggplot2", "ggtree", "SummarizedExperiment")
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
    suppressPackageStartupMessages({
        library(TreeSummarizedExperiment)
        library(SummarizedExperiment)
        library(treeclimbR)
        library(dplyr)
        library(ggplot2)
        library(ggtree)
    })
    
    # 1. Read input file
    input_file <- "da_lse"
    if (!file.exists(input_file) && file.exists("da_lse.rds")) {
        input_file <- "da_lse.rds"
    }
    
    if (!file.exists(input_file)) {
        stop("Error: Input file 'da_lse' or 'da_lse.rds' not found in the working directory.")
    }
    
    da_lse <- readRDS(input_file)
    
    # 2. Get all node IDs using showNode
    all_node <- showNode(tree = rowTree(da_lse), only.leaf = FALSE)
    
    # 3. Aggregate counts for internal nodes using aggTSE
    da_tse <- aggTSE(x = da_lse, rowLevel = all_node, rowFun = sum)
    saveRDS(da_tse, "da_tse.rds")
    
    # 4. Perform differential abundance analysis for leaves and nodes using runDA
    da_res <- runDA(da_tse, assay = "counts", option = "glmQL", 
                    design = model.matrix(~ group, data = colData(da_tse)), 
                    contrast = c(0, 1), filter_min_count = 0, 
                    filter_min_prop = 0, filter_min_total_count = 15)
    saveRDS(da_res, "da_res.rds")
    
    # 5. Extract node results using nodeResult
    da_tbl <- nodeResult(da_res, n = Inf, type = "DA")
    write.csv(da_tbl, "da_tbl.csv", row.names = FALSE)
    
    # 6. Propose aggregation candidates using getCand
    da_cand <- getCand(tree = rowTree(da_tse), score_data = da_tbl, 
                       node_column = "node", p_column = "PValue",
                       threshold = 0.05, sign_column = "logFC", message = FALSE)
    
    # 7. Evaluate candidates to find the optimal aggregation level using evalCand
    da_best <- evalCand(tree = rowTree(da_tse), levels = da_cand\$candidate_list, 
                        score_data = da_tbl, node_column = "node",
                        p_column = "PValue", sign_column = "logFC")
    saveRDS(da_best, "da_best.rds")
    
    # 8. Summarize candidates using infoCand and extract significant nodes using topNodes
    cand_info <- infoCand(object = da_best)
    write.csv(cand_info, "info_cand.csv", row.names = FALSE)
    
    da_out <- topNodes(object = da_best, n = Inf, p_value = 0.05)
    write.csv(da_out, "da_out.csv", row.names = FALSE)
    
    # 9. Evaluate performance using fdr and tpr
    fdr_val <- NA
    tpr_val <- NA
    
    tryCatch({
        if ("Signal" %in% colnames(rowData(da_lse))) {
            fdr_val <- fdr(rowTree(da_tse), truth = rownames(da_lse)[rowData(da_lse)\$Signal], 
                           found = da_out\$node, only.leaf = TRUE)
            tpr_val <- tpr(rowTree(da_tse), truth = rownames(da_lse)[rowData(da_lse)\$Signal], 
                           found = da_out\$node, only.leaf = TRUE)
        } else {
            warning("Signal column not found in rowData(da_lse). FDR and TPR cannot be calculated.")
        }
    }, error = function(e) {
        warning("Error calculating FDR/TPR: ", e\$message)
    })
    
    # Save FDR and TPR to a CSV
    perf_df <- data.frame(
        Metric = c("FDR", "TPR"),
        Value = c(fdr_val, tpr_val)
    )
    write.csv(perf_df, "performance_metrics.csv", row.names = FALSE)
    
    # 10. Generate PDF plot of the tree with significant nodes
    tryCatch({
        pdf("significant_nodes_tree.pdf", width = 10, height = 8)
        p <- ggtree(rowTree(da_tse)) + 
             geom_point2(aes(subset = node %in% da_out\$node), color = "red", size = 2) +
             geom_tiplab(size = 2) +
             theme_tree2() +
             labs(title = "Significant Nodes Identified by treeclimbR")
        print(p)
        dev.off()
    }, error = function(e) {
        warning("Could not generate PDF plot: ", e\$message)
    })
    
    cat("Pipeline completed successfully. Outputs written to working directory.\n")

    writeLines(c(
        '"BIOC_TREECLIMBR_DIFFERENTIAL_ABUNDANCE_ANALYSIS":',
        paste0('    treeclimbR: ', as.character(packageVersion('treeclimbR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_abundance_analysis.csv versions.yml
    """
}

workflow BIOC_TREECLIMBR_DIFFERENTIAL_ABUNDANCE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ da_lse ] ]

    main:
    BIOC_TREECLIMBR_DIFFERENTIAL_ABUNDANCE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_TREECLIMBR_DIFFERENTIAL_ABUNDANCE_ANALYSIS.out.tables
    plots    = BIOC_TREECLIMBR_DIFFERENTIAL_ABUNDANCE_ANALYSIS.out.plots
    objects  = BIOC_TREECLIMBR_DIFFERENTIAL_ABUNDANCE_ANALYSIS.out.objects
    versions = BIOC_TREECLIMBR_DIFFERENTIAL_ABUNDANCE_ANALYSIS.out.versions
}
