#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: monocle — single_cell_trajectory_analysis
// Order single cells in pseudotime along a trajectory and perform differential expression and clustering.
// Input: single_cell_expression_matrix.txt, cell_metadata.txt, gene_metadata.txt
// Container: quay.io/biocontainers/bioconductor-monocle:2.38.0--r45ha27e39d_0
// R packages: Biobase, ggplot2, knitr, monocle, reshape2
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, monocle
// Visualizations: pseudotime plot, cluster plot, trajectory plot
// QC: dispersion/size-factor estimation, clustering QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a CellDataSet object using newCellDataSet
//  * 2. [Core Analysis] Filter genes and detect expressed genes using detectGenes
//  * 3. [Core Analysis] Classify or cluster cells using clusterCells or classifyCells
//  * 4. [Core Analysis] Order cells along a trajectory using orderCells
//  * 5. [Core Analysis] Perform differential expression analysis using differentialGeneTest or BEAM
//  * 6. [Visualization & Output] Plot trajectories and gene expression using plot_cell_trajectory or plot_genes_in_pseudotime

nextflow.enable.dsl = 2

process BIOC_MONOCLE_SINGLE_CELL_TRAJECTORY_ANALYSIS {
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
    .bm_deps <- c("Biobase", "ggplot2", "knitr", "monocle", "reshape2")
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
    library(monocle)
    library(Biobase)
    
    # 1. Create a CellDataSet object using newCellDataSet
    # Read user input files from the working directory
    expr_matrix <- read.table("single_cell_expression_matrix.txt", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
    cell_metadata <- read.table("cell_metadata.txt", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
    gene_metadata <- read.table("gene_metadata.txt", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
    
    # Align inputs to ensure consistency across matrices and data frames
    common_cells <- intersect(colnames(expr_matrix), rownames(cell_metadata))
    if (length(common_cells) == 0) {
      stop("Error: No common cells between expression matrix columns and cell metadata rows.")
    }
    expr_matrix <- expr_matrix[, common_cells, drop = FALSE]
    cell_metadata <- cell_metadata[common_cells, , drop = FALSE]
    
    common_genes <- intersect(rownames(expr_matrix), rownames(gene_metadata))
    if (length(common_genes) == 0) {
      stop("Error: No common genes between expression matrix rows and gene metadata rows.")
    }
    expr_matrix <- expr_matrix[common_genes, , drop = FALSE]
    gene_metadata <- gene_metadata[common_genes, , drop = FALSE]
    
    # Ensure the required 'gene_short_name' column exists in gene metadata
    if (!"gene_short_name" %in% colnames(gene_metadata)) {
      gene_metadata\$gene_short_name <- rownames(gene_metadata)
    }
    
    # Construct AnnotatedDataFrame objects
    pd <- new("AnnotatedDataFrame", data = cell_metadata)
    fd <- new("AnnotatedDataFrame", data = gene_metadata)
    
    # Create the CellDataSet object (assuming negative binomial distribution for count data)
    cds <- newCellDataSet(as.matrix(expr_matrix),
                          phenoData = pd,
                          featureData = fd,
                          expressionFamily = negbinomial.size())
    
    # Estimate size factors and dispersions (essential preprocessing steps in Monocle)
    cds <- estimateSizeFactors(cds)
    cds <- estimateDispersions(cds)
    
    # 2. Filter genes and detect expressed genes using detectGenes
    cds <- detectGenes(cds, min_expr = 0.1)
    
    # Filter to genes expressed in at least a minimum threshold of cells
    min_cells <- max(5, round(ncol(cds) * 0.05))
    expressed_genes <- row.names(subset(fData(cds), num_cells_expressed >= min_cells))
    
    # 3. Classify or cluster cells using clusterCells
    # Identify high-dispersion genes to use for clustering
    disp_table <- dispersionTable(cds)
    ordering_genes <- subset(disp_table, mean_expression >= 0.1 & dispersion_empirical >= 1 * dispersion_fit)\$gene_id
    
    # Set ordering filter for dimensionality reduction
    cds <- setOrderingFilter(cds, ordering_genes)
    
    # Reduce dimensionality using tSNE for clustering
    cds <- reduceDimension(cds, max_components = 2, num_dim = min(6, length(ordering_genes)), reduction_method = 'tSNE', verbose = FALSE)
    
    # Cluster cells
    cds <- clusterCells(cds)
    
    # Save clustering visualization
    pdf("cell_clusters_plot.pdf")
    print(plot_cell_clusters(cds))
    dev.off()
    
    # 4. Order cells along a trajectory using orderCells
    # Reduce dimensionality using DDRTree for trajectory reconstruction
    cds <- reduceDimension(cds, max_components = 2, reduction_method = 'DDRTree')
    
    # Order cells along the trajectory
    cds <- orderCells(cds)
    
    # 5. Perform differential expression analysis using differentialGeneTest or BEAM
    # Test a subset of genes to keep execution time reasonable
    genes_to_test <- head(ordering_genes, 100)
    diff_test_res <- differentialGeneTest(cds[genes_to_test, ],
                                          fullModelFormulaStr = "~sm.ns(Pseudotime)",
                                          cores = 1)
    
    # Save differential expression results
    write.csv(diff_test_res, "differential_expression_results.csv", row.names = TRUE)
    
    # Perform BEAM analysis if branching is detected (State > 2)
    tryCatch({
      if (length(unique(pData(cds)\$State)) > 2) {
        beam_res <- BEAM(cds[genes_to_test, ], branch_point = 1, cores = 1)
        write.csv(beam_res, "beam_results.csv", row.names = TRUE)
      }
    }, error = function(e) {
      message("BEAM analysis skipped or failed: ", e\$message)
    })
    
    # 6. Plot trajectories and gene expression using plot_cell_trajectory or plot_genes_in_pseudotime
    # Plot trajectory colored by State
    pdf("trajectory_by_state.pdf")
    print(plot_cell_trajectory(cds, color_by = "State"))
    dev.off()
    
    # Plot trajectory colored by Pseudotime
    pdf("trajectory_by_pseudotime.pdf")
    print(plot_cell_trajectory(cds, color_by = "Pseudotime"))
    dev.off()
    
    # Plot trajectory colored by Cluster
    if ("Cluster" %in% colnames(pData(cds))) {
      pdf("trajectory_by_cluster.pdf")
      print(plot_cell_trajectory(cds, color_by = "Cluster"))
      dev.off()
    }
    
    # Plot top significant genes in pseudotime
    sig_genes <- row.names(subset(diff_test_res, qval < 0.05))
    if (length(sig_genes) > 0) {
      top_genes <- head(sig_genes, 4)
      pdf("top_genes_in_pseudotime.pdf")
      print(plot_genes_in_pseudotime(cds[top_genes, ], color_by = "State"))
      dev.off()
    }
    
    # Save the final CellDataSet object
    saveRDS(cds, "monocle_output_cds.rds")

    writeLines(c(
        '"BIOC_MONOCLE_SINGLE_CELL_TRAJECTORY_ANALYSIS":',
        paste0('    monocle: ', as.character(packageVersion('monocle')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_cell_trajectory_analysis.csv versions.yml
    """
}

workflow BIOC_MONOCLE_SINGLE_CELL_TRAJECTORY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ single_cell_expression_matrix.txt, cell_metadata.txt, gene_metadata.txt ] ]

    main:
    BIOC_MONOCLE_SINGLE_CELL_TRAJECTORY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MONOCLE_SINGLE_CELL_TRAJECTORY_ANALYSIS.out.tables
    plots    = BIOC_MONOCLE_SINGLE_CELL_TRAJECTORY_ANALYSIS.out.plots
    objects  = BIOC_MONOCLE_SINGLE_CELL_TRAJECTORY_ANALYSIS.out.objects
    versions = BIOC_MONOCLE_SINGLE_CELL_TRAJECTORY_ANALYSIS.out.versions
}
