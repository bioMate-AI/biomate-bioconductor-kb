#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: treeclimbR — differential_state_analysis
// Find genes that are differentially expressed between conditions in either a single cell subpopulation or a group of similar subpopulations.
// Input: ds_tse
// Container: quay.io/biocontainers/bioconductor-treeclimbr:1.6.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: TreeSummarizedExperiment, dplyr, ggplot2, ggtree, treeclimbR
// Visualizations: phylogenetic tree
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Aggregate counts to generate pseudobulk samples for each node and sample using aggDS
//  * 2. [Core Analysis] Perform differential state analysis for leaves and nodes using runDS
//  * 3. [Core Analysis] Extract node results using nodeResult
//  * 4. [Core Analysis] Split results by feature and find candidates for each gene separately using getCand
//  * 5. [Core Analysis] Evaluate candidates across multiple features using evalCand with type = "multiple"
//  * 6. [Core Analysis] Extract top significant nodes per feature using topNodes

nextflow.enable.dsl = 2

process BIOC_TREECLIMBR_DIFFERENTIAL_STATE_ANALYSIS {
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
    .bm_deps <- c("TreeSummarizedExperiment", "treeclimbR", "ggtree", "dplyr", "ggplot2", "SummarizedExperiment")
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
    suppressPackageStartupMessages({
        library(TreeSummarizedExperiment)
        library(SummarizedExperiment)
        library(treeclimbR)
        library(ggtree)
        library(dplyr)
        library(ggplot2)
    })
    
    # 1. Read the user input file from the working directory
    if (file.exists("ds_tse")) {
        ds_tse <- readRDS("ds_tse")
    } else if (file.exists("ds_tse.rds")) {
        ds_tse <- readRDS("ds_tse.rds")
    } else {
        stop("Input file 'ds_tse' or 'ds_tse.rds' not found in the working directory.")
    }
    
    # 2. Aggregate counts to generate pseudobulk samples for each node and sample
    ds_se <- aggDS(TSE = ds_tse, assay = "counts", sample_id = "sample_id", 
                   group_id = "group", cluster_id = "cluster_id", FUN = sum)
    
    # Save aggregated SummarizedExperiment object
    saveRDS(ds_se, file = "ds_se.rds")
    
    # 3. Perform differential state analysis for leaves and nodes
    ds_res <- runDS(SE = ds_se, tree = colTree(ds_tse), option = "glmQL", 
                    design = model.matrix(~ group, data = colData(ds_se)), 
                    contrast = c(0, 1), filter_min_count = 0, 
                    filter_min_total_count = 1, filter_min_prop = 0, min_cells = 5, 
                    group_column = "group", message = FALSE)
    
    # Save differential state analysis results object
    saveRDS(ds_res, file = "ds_res.rds")
    
    # 4. Extract node results
    ds_tbl <- nodeResult(ds_res, type = "DS", n = Inf)
    
    # Save full node results table
    write.csv(ds_tbl, file = "ds_node_results.csv", row.names = FALSE)
    
    # 5. Split results by feature and find candidates for each gene separately
    ds_tbl_list <- split(ds_tbl, f = ds_tbl\$feature)
    ds_cand_list <- lapply(seq_along(ds_tbl_list), 
                           FUN = function(x) {
                               getCand(
                                   tree = colTree(ds_tse),
                                   t = seq(from = 0.05, to = 1, by = 0.05),
                                   score_data = ds_tbl_list[[x]], 
                                   node_column = "node", 
                                   p_column = "PValue", 
                                   sign_column = "logFC",
                                   message = FALSE)\$candidate_list
                           })
    names(ds_cand_list) <- names(ds_tbl_list)
    
    # 6. Evaluate candidates across multiple features
    ds_best <- evalCand(tree = colTree(ds_tse), type = "multiple", 
                        levels = ds_cand_list, score_data = ds_tbl_list, 
                        node_column = "node", 
                        p_column = "PValue", 
                        sign_column = "logFC", 
                        feature_column = "feature",
                        limit_rej = 0.05,
                        message = FALSE,
                        use_pseudo_leaf = FALSE)
    
    # Save evaluated candidates object
    saveRDS(ds_best, file = "ds_best.rds")
    
    # 7. Extract top significant nodes per feature
    ds_out <- topNodes(object = ds_best, n = Inf, p_value = 0.05)
    
    # Save top significant nodes table
    write.csv(ds_out, file = "ds_top_nodes.csv", row.names = FALSE)
    
    # 8. Generate and save visualization of the tree with significant nodes
    tryCatch({
        pdf("ds_significant_nodes_tree.pdf", width = 8, height = 6)
        p <- ggtree(colTree(ds_tse)) + 
             geom_text2(aes(label = node), color = "darkblue", hjust = -0.5, vjust = 0.7) +
             geom_point2(aes(subset = node %in% ds_out\$node), color = "red", size = 3) +
             labs(title = "Differential State Analysis: Significant Nodes")
        print(p)
        dev.off()
    }, error = function(e) {
        warning("Could not generate tree plot: ", e\$message)
    })

    writeLines(c(
        '"BIOC_TREECLIMBR_DIFFERENTIAL_STATE_ANALYSIS":',
        paste0('    treeclimbR: ', as.character(packageVersion('treeclimbR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_state_analysis.csv versions.yml
    """
}

workflow BIOC_TREECLIMBR_DIFFERENTIAL_STATE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ds_tse ] ]

    main:
    BIOC_TREECLIMBR_DIFFERENTIAL_STATE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_TREECLIMBR_DIFFERENTIAL_STATE_ANALYSIS.out.tables
    plots    = BIOC_TREECLIMBR_DIFFERENTIAL_STATE_ANALYSIS.out.plots
    objects  = BIOC_TREECLIMBR_DIFFERENTIAL_STATE_ANALYSIS.out.objects
    versions = BIOC_TREECLIMBR_DIFFERENTIAL_STATE_ANALYSIS.out.versions
}
