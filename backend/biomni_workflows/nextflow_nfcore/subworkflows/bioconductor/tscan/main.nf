#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TSCAN — single_cell_trajectory_analysis
// Reconstruct single-cell differentiation trajectories, order cells along pseudotime, and identify differentially expressed genes along the path.
// Input: lpsdata.ext
// Container: quay.io/biocontainers/bioconductor-tscan:1.48.0--r45hdfd78af_0
// R packages: TSCAN
// Bioconductor: 3.20 | R: 4.4
// Requires: TSCAN
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Preprocess raw expression data to filter out low-expressed and low-variance genes using preprocess
//  * 2. [Core Analysis] Perform dimension reduction and model-based clustering using exprmclust
//  * 3. [Visualization & Output] Visualize the clustering results using plotmclust
//  * 4. [Input & Preparation] Construct the pseudotemporal cell ordering using TSCANorder
//  * 5. [Core Analysis] Test for differentially expressed genes along the pseudotime trajectory using difftest
//  * 6. [Visualization & Output] Plot expression of individual genes against pseudotime using singlegeneplot
//  * 7. [Core Analysis] Evaluate and compare different pseudotemporal orderings using orderscore

nextflow.enable.dsl = 2

process BIOC_TSCAN_SINGLE_CELL_TRAJECTORY_ANALYSIS {
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
    .bm_deps <- c("TSCAN")
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
        
        # Load required library
        library(TSCAN)
        
        # 1. Read User Input File
        if (!file.exists("lpsdata.ext")) {
          stop("Error: Required input file 'lpsdata.ext' not found in the working directory.")
        }
        
        # Robustly read the expression matrix
        lpsdata <- tryCatch({
          readRDS("lpsdata.ext")
        }, error = function(e) {
          tryCatch({
            as.matrix(read.table("lpsdata.ext", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE))
          }, error = function(e2) {
            as.matrix(read.csv("lpsdata.ext", header = TRUE, row.names = 1, check.names = FALSE))
          })
        })
        
        lpsdata <- as.matrix(lpsdata)
        
        # Ensure column names (cells) and row names (genes) exist
        if (is.null(colnames(lpsdata))) {
          colnames(lpsdata) <- paste0("Cell_", seq_len(ncol(lpsdata)))
        }
        if (is.null(rownames(lpsdata))) {
          rownames(lpsdata) <- paste0("Gene_", seq_len(nrow(lpsdata)))
        }
        
        # 2. Preprocess raw expression data
        procdata <- preprocess(lpsdata)
        
        # 3. Perform dimension reduction and model-based clustering
        lpsmclust <- exprmclust(procdata)
        
        # 4. Visualize the clustering results
        pdf("mclust_plot.pdf", width = 8, height = 6)
        print(plotmclust(lpsmclust))
        dev.off()
        
        # 5. Construct the pseudotemporal cell ordering
        lpsorder <- TSCANorder(lpsmclust)
        write.table(lpsorder, "lpsorder.txt", row.names = FALSE, col.names = FALSE, quote = FALSE)
        
        # 6. Test for differentially expressed genes along the pseudotime trajectory
        diffval <- difftest(procdata, lpsorder)
        write.csv(diffval, "differentially_expressed_genes.csv", row.names = TRUE)
        
        # Selected differentially expressed genes under qvalue cutoff of 0.05
        de_genes <- row.names(diffval)[diffval\$qval < 0.05]
        write.table(de_genes, "de_genes_q0.05.txt", row.names = FALSE, col.names = FALSE, quote = FALSE)
        
        # 7. Plot expression of individual genes against pseudotime
        selected_gene <- rownames(procdata)[1]
        gene_expr <- log2(lpsdata[selected_gene, ] + 1)
        pdf("singlegene_plot.pdf", width = 8, height = 6)
        print(singlegeneplot(gene_expr, TSCANorder(lpsmclust, flip = TRUE, orderonly = FALSE)))
        dev.off()
        
        # 8. Evaluate and compare different pseudotemporal orderings
        subpopulation <- data.frame(
          cell = colnames(procdata), 
          sub = as.numeric(lpsmclust\$clusterid), 
          stringsAsFactors = FALSE
        )
        
        # Comparing ordering with or without marker gene/cluster path information
        # Wrap in tryCatch to handle cases where the dataset has fewer than 3 clusters
        tryCatch({
          order1 <- TSCANorder(lpsmclust)
          order2 <- TSCANorder(lpsmclust, c(1, 2, 3))
          orders <- list(order1, order2)
        
          scores <- orderscore(subpopulation, orders)
          write.csv(data.frame(Order = c("order1", "order2"), Score = scores), "orderscore_results.csv", row.names = FALSE)
        }, error = function(e) {
          message("Warning: orderscore comparison with path c(1,2,3) skipped or failed: ", e\$message)
          # Fallback using available clusters
          try({
            order1 <- TSCANorder(lpsmclust)
            unique_clusters <- as.numeric(unique(lpsmclust\$clusterid))
            order2 <- TSCANorder(lpsmclust, unique_clusters)
            orders <- list(order1, order2)
            scores <- orderscore(subpopulation, orders)
            write.csv(data.frame(Order = c("order1", "order2_dynamic"), Score = scores), "orderscore_results.csv", row.names = FALSE)
          }, silent = TRUE)
        })

    writeLines(c(
        '"BIOC_TSCAN_SINGLE_CELL_TRAJECTORY_ANALYSIS":',
        paste0('    TSCAN: ', as.character(packageVersion('TSCAN')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_cell_trajectory_analysis.csv versions.yml
    """
}

workflow BIOC_TSCAN_SINGLE_CELL_TRAJECTORY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ lpsdata.ext ] ]

    main:
    BIOC_TSCAN_SINGLE_CELL_TRAJECTORY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_TSCAN_SINGLE_CELL_TRAJECTORY_ANALYSIS.out.tables
    plots    = BIOC_TSCAN_SINGLE_CELL_TRAJECTORY_ANALYSIS.out.plots
    objects  = BIOC_TSCAN_SINGLE_CELL_TRAJECTORY_ANALYSIS.out.objects
    versions = BIOC_TSCAN_SINGLE_CELL_TRAJECTORY_ANALYSIS.out.versions
}
