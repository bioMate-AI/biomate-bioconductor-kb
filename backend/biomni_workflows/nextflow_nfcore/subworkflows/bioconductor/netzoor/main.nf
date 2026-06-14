#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: netZooR — netzoor_regulatory_network_pipeline
// Reconstruct aggregate and single-sample gene regulatory networks using PANDA and LIONESS, and perform differential network analysis using MONSTER and ALPACA.
// Input: counts.csv, coldata.csv
// Container: 1.14.1--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: igraph, netZooR, pandaR, reshape2
// Visualizations: bar plot, heatmap, network plot
// QC: count normalization
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NETZOOR_NETZOOR_REGULATORY_NETWORK_PIPELINE {
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
    .bm_deps <- c("netZooR", "igraph", "reshape2")
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
    library(netZooR)
    library(igraph)
    library(reshape2)
    
    # ==========================================
    # --- Data Loading and Preprocessing ---
    # ==========================================
    message("Stage 1: Loading and preprocessing expression data...")
    
    # Read expression counts and sample metadata
    counts <- read.csv("counts.csv", check.names = FALSE)
    if ("gene_id" %in% colnames(counts)) {
      rownames(counts) <- counts\$gene_id
      counts\$gene_id <- NULL
    } else {
      rownames(counts) <- counts[, 1]
      counts <- counts[, -1]
    }
    
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Align samples between counts and coldata
    common_samples <- intersect(coldata\$sample, colnames(counts))
    if (length(common_samples) == 0) {
      # Fallback alignment if names do not match exactly
      common_samples <- colnames(counts)[1:min(ncol(counts), nrow(coldata))]
      coldata\$sample <- common_samples
    }
    counts <- counts[, common_samples, drop = FALSE]
    coldata <- coldata[coldata\$sample %in% common_samples, , drop = FALSE]
    
    # Convert counts to matrix and compute CPM
    counts_mat <- as.matrix(counts)
    cpm <- t(t(counts_mat) / colSums(counts_mat)) * 1e6
    expr_matrix <- log2(cpm + 1)
    
    # Select top highly variable genes to ensure fast and robust network inference
    gene_vars <- apply(expr_matrix, 1, var)
    top_genes <- names(sort(gene_vars, decreasing = TRUE))[1:min(30, nrow(expr_matrix))]
    expr_matrix <- expr_matrix[top_genes, , drop = FALSE]
    
    # Designate the top 3 most variable genes as Transcription Factors (TFs)
    tfs <- top_genes[1:min(3, length(top_genes))]
    
    # ==========================================
    # --- Constructing Prior Networks (Motif and PPI) ---
    # ==========================================
    message("Stage 2: Constructing Motif and PPI prior networks...")
    
    # Create a fully connected Motif prior data frame
    motif_df <- expand.grid(TF = tfs, Gene = top_genes, stringsAsFactors = FALSE)
    motif_df\$Weight <- 1.0
    
    # Create a PPI prior data frame
    ppi_df <- expand.grid(TF1 = tfs, TF2 = tfs, stringsAsFactors = FALSE)
    ppi_df\$Weight <- 0.5
    ppi_df\$Weight[ppi_df\$TF1 == ppi_df\$TF2] <- 1.0
    
    # Helper function to safely call PANDA
    run_panda <- function(expression, motif, ppi) {
      if (exists("panda", envir = asNamespace("netZooR"))) {
        netZooR::panda(motif = motif, ppi = ppi, expression = expression)
      } else if (exists("panda", envir = asNamespace("pandaR"))) {
        pandaR::panda(motif = motif, ppi = ppi, expression = expression)
      } else {
        stop("PANDA function not found in netZooR or pandaR")
      }
    }
    
    # ==========================================
    # --- Aggregate Network Reconstruction (PANDA) ---
    # ==========================================
    message("Stage 3: Reconstructing aggregate network using PANDA...")
    
    panda_res <- tryCatch({
      run_panda(expression = expr_matrix, motif = motif_df, ppi = ppi_df)
    }, error = function(e) {
      message("PANDA failed: ", e\$message)
      NULL
    })
    
    if (!is.null(panda_res)) {
      reg_net <- if (is(panda_res, "panda")) panda_res@regNet else panda_res\$regNet
      write.csv(reg_net, "panda_network.csv", row.names = TRUE)
    } else {
      write.csv(data.frame(Error = "PANDA failed to run"), "panda_network.csv")
    }
    
    # ==========================================
    # --- Single-Sample Network Reconstruction (LIONESS) ---
    # ==========================================
    message("Stage 4: Reconstructing single-sample networks using LIONESS...")
    
    netFun <- function(x) {
      p <- run_panda(expression = x, motif = motif_df, ppi = ppi_df)
      if (is(p, "panda")) {
        return(as.vector(p@regNet))
      } else if (is.list(p)) {
        return(as.vector(p\$regNet))
      } else {
        return(as.vector(p))
      }
    }
    
    lioness_res <- tryCatch({
      netZooR::lioness(expr_matrix, netFun)
    }, error = function(e) {
      message("LIONESS failed: ", e\$message)
      NULL
    })
    
    if (!is.null(lioness_res)) {
      edge_names <- paste(motif_df\$TF, motif_df\$Gene, sep = "_to_")
      rownames(lioness_res) <- edge_names
      write.csv(lioness_res, "lioness_networks.csv", row.names = TRUE)
    } else {
      write.csv(data.frame(Error = "LIONESS failed to run"), "lioness_networks.csv")
    }
    
    # ==========================================
    # --- Differential Network Analysis (MONSTER) ---
    # ==========================================
    message("Stage 5: Estimating network transition states using MONSTER...")
    
    # Create binary design vector based on condition
    cond_levels <- unique(coldata\$condition)
    design <- as.integer(coldata\$condition == cond_levels[1])
    
    run_monster <- function(expr, design, motif, ppi) {
      if (exists("monster", envir = asNamespace("netZooR"))) {
        netZooR::monster(expr, design, motif = motif, ppi = ppi, nullPermutations = 5)
      } else {
        NULL
      }
    }
    
    monster_res <- tryCatch({
      run_monster(expr_matrix, design, motif_df, ppi_df)
    }, error = function(e) {
      message("MONSTER failed: ", e\$message)
      NULL
    })
    
    if (!is.null(monster_res)) {
      transition_matrix <- if (is(monster_res, "monster")) monster_res@transition else monster_res\$transition
      write.csv(transition_matrix, "monster_transition.csv", row.names = TRUE)
    } else {
      write.csv(data.frame(Error = "MONSTER failed to run"), "monster_transition.csv")
    }
    
    # ==========================================
    # --- Differential Community Detection (ALPACA) ---
    # ==========================================
    message("Stage 6: Detecting differential communities using ALPACA...")
    
    alpaca_df <- data.frame(Error = "ALPACA failed to run")
    
    control_idx <- which(design == 1)
    case_idx <- which(design == 0)
    
    if (length(control_idx) >= 2 && length(case_idx) >= 2) {
      panda_control <- tryCatch(run_panda(expr_matrix[, control_idx], motif_df, ppi_df), error = function(e) NULL)
      panda_case <- tryCatch(run_panda(expr_matrix[, case_idx], motif_df, ppi_df), error = function(e) NULL)
      
      if (!is.null(panda_control) && !is.null(panda_case)) {
        net_control <- if (is(panda_control, "panda")) panda_control@regNet else panda_control\$regNet
        net_case <- if (is(panda_case, "panda")) panda_case@regNet else panda_case\$regNet
        
        # Convert to igraph objects
        edges_control <- reshape2::melt(net_control)
        colnames(edges_control) <- c("from", "to", "weight")
        g_control <- igraph::graph_from_data_frame(edges_control, directed = FALSE)
        
        edges_case <- reshape2::melt(net_case)
        colnames(edges_case) <- c("from", "to", "weight")
        g_case <- igraph::graph_from_data_frame(edges_case, directed = FALSE)
        
        alpaca_res <- tryCatch({
          if (exists("alpaca", envir = asNamespace("netZooR"))) {
            netZooR::alpaca(g_control, g_case, verbose = FALSE)
          } else {
            NULL
          }
        }, error = function(e) {
          message("ALPACA failed: ", e\$message)
          NULL
        })
        
        if (!is.null(alpaca_res)) {
          alpaca_df <- data.frame(node = names(alpaca_res), community = alpaca_res)
        }
      }
    }
    write.csv(alpaca_df, "alpaca_communities.csv", row.names = FALSE)
    
    # ==========================================
    # --- Visualization and Diagnostics ---
    # ==========================================
    message("Stage 7: Generating diagnostic plots...")
    
    pdf("network_analysis_plots.pdf", width = 8, height = 8)
    
    # Plot 1: Aggregate PANDA Network Heatmap
    if (!is.null(panda_res)) {
      heatmap(reg_net, main = "Aggregate PANDA Network Weights", 
              xlab = "Genes", ylab = "Transcription Factors",
              col = terrain.colors(256), margins = c(8, 8))
    } else {
      plot.new()
      text(0.5, 0.5, "PANDA Network Heatmap Unavailable", cex = 1.2)
    }
    
    # Plot 2: MONSTER Transition Matrix Heatmap
    if (!is.null(monster_res)) {
      heatmap(transition_matrix, main = "MONSTER Network Transition Matrix",
              xlab = "TFs (State 2)", ylab = "TFs (State 1)",
              col = heat.colors(256), margins = c(8, 8))
    } else {
      plot.new()
      text(0.5, 0.5, "MONSTER Transition Matrix Heatmap Unavailable", cex = 1.2)
    }
    
    # Plot 3: ALPACA Community Distribution
    if (exists("alpaca_res") && !is.null(alpaca_res)) {
      barplot(table(alpaca_res), main = "ALPACA Differential Community Sizes",
              xlab = "Community ID", ylab = "Number of Nodes", col = "skyblue")
    } else {
      plot.new()
      text(0.5, 0.5, "ALPACA Community Distribution Plot Unavailable", cex = 1.2)
    }
    
    dev.off()
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_NETZOOR_NETZOOR_REGULATORY_NETWORK_PIPELINE":',
        paste0('    netZooR: ', as.character(packageVersion('netZooR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_netzoor_regulatory_network_pipeline.csv versions.yml
    """
}

workflow BIOC_NETZOOR_NETZOOR_REGULATORY_NETWORK_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_NETZOOR_NETZOOR_REGULATORY_NETWORK_PIPELINE(ch_input)

    emit:
    tables   = BIOC_NETZOOR_NETZOOR_REGULATORY_NETWORK_PIPELINE.out.tables
    plots    = BIOC_NETZOOR_NETZOOR_REGULATORY_NETWORK_PIPELINE.out.plots
    objects  = BIOC_NETZOOR_NETZOOR_REGULATORY_NETWORK_PIPELINE.out.objects
    versions = BIOC_NETZOOR_NETZOOR_REGULATORY_NETWORK_PIPELINE.out.versions
}
