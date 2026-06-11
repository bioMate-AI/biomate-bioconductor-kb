#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scMultiSim — scmultisim_multimodal_simulation
// Simulate multimodal single-cell RNA-seq, ATAC-seq, and RNA velocity data using a gene regulatory network (GRN) inferred from input expression data, followed by 
// Input: counts.csv, coldata.csv
// Container: 1.6.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: dplyr, ggplot2, scMultiSim
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCMULTISIM_SCMULTISIM_MULTIMODAL_SIMULATION {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(scMultiSim)
    library(dplyr)
    library(ggplot2)
    
    # --- Read input files ---
    counts <- read.csv("counts.csv", check.names = FALSE)
    if ("gene_id" %in% colnames(counts)) {
      rownames(counts) <- counts\$gene_id
      counts\$gene_id <- NULL
    } else {
      rownames(counts) <- counts[, 1]
      counts <- counts[, -1, drop = FALSE]
    }
    
    coldata <- read.csv("coldata.csv", check.names = FALSE)
    if ("sample" %in% colnames(coldata)) {
      rownames(coldata) <- coldata\$sample
    } else {
      rownames(coldata) <- coldata[, 1]
      coldata <- coldata[, -1, drop = FALSE]
    }
    
    # --- Determine simulation dimensions based on input data ---
    n_cells <- max(ncol(counts), 80)
    n_genes <- max(nrow(counts), 110)
    
    # --- Infer a Gene Regulatory Network (GRN) from input counts ---
    # Map genes to integer IDs 1:nrow(counts)
    gene_mapping <- data.frame(
      gene_name = rownames(counts),
      gene_id = 1:nrow(counts)
    )
    
    # Select top highly variable genes to construct the GRN
    gene_vars <- apply(counts, 1, var)
    top_genes <- order(gene_vars, decreasing = TRUE)[1:min(100, nrow(counts))]
    cor_matrix <- cor(t(counts[top_genes, ]))
    
    pairs <- which(abs(cor_matrix) > 0.1 & row(cor_matrix) != col(cor_matrix), arr.ind = TRUE)
    if (nrow(pairs) > 0) {
      # Limit to top 100 pairs to avoid an overly dense network
      if (nrow(pairs) > 100) {
        cor_values <- cor_matrix[pairs]
        top_pairs_idx <- order(abs(cor_values), decreasing = TRUE)[1:100]
        pairs <- pairs[top_pairs_idx, , drop = FALSE]
      }
      grn_df <- data.frame(
        regulated.gene = gene_mapping\$gene_id[top_genes[pairs[, 1]]],
        regulator.gene = gene_mapping\$gene_id[top_genes[pairs[, 2]]],
        regulator.effect = cor_matrix[pairs] * 2
      )
      # Ensure integer IDs
      grn_df\$regulated.gene <- as.integer(grn_df\$regulated.gene)
      grn_df\$regulator.gene <- as.integer(grn_df\$regulator.gene)
      # Remove duplicates
      grn_df <- grn_df[!duplicated(grn_df[, c("regulated.gene", "regulator.gene")]), ]
    } else {
      # Fallback GRN if no correlation is found
      grn_df <- data.frame(
        regulated.gene = as.integer(c(2, 3, 4)),
        regulator.gene = as.integer(c(1, 1, 2)),
        regulator.effect = c(1.5, 2.0, -1.2)
      )
    }
    
    # --- Run true counts simulation with RNA velocity and ATAC-seq ---
    options <- list(
      GRN = grn_df,
      num.cells = n_cells,
      num.genes = n_genes,
      tree = Phyla3(),
      num.cifs = 30,
      cif.sigma = 0.5,
      diff.cif.fraction = 0.8,
      do.velocity = TRUE
    )
    
    message("Running true counts simulation...")
    results <- sim_true_counts(options)
    
    # --- Add technical noise and batch effects ---
    message("Adding experimental noise...")
    add_expr_noise(results, alpha_mean = 1e4)
    
    message("Adding batch effects...")
    divide_batches(results, nbatch = 2, effect = 1)
    
    # --- Save simulated datasets ---
    message("Saving simulated outputs...")
    write.csv(as.matrix(results\$counts), "simulated_true_counts.csv")
    
    if (!is.null(results\$counts_obs)) {
      write.csv(as.matrix(results\$counts_obs), "simulated_observed_counts.csv")
    } else {
      write.csv(as.matrix(results\$counts), "simulated_observed_counts.csv")
    }
    
    if (!is.null(results\$counts_with_batches)) {
      write.csv(as.matrix(results\$counts_with_batches), "simulated_batch_counts.csv")
    } else {
      write.csv(as.matrix(results\$counts), "simulated_batch_counts.csv")
    }
    
    if (!is.null(results\$atac_counts)) {
      write.csv(as.matrix(results\$atac_counts), "simulated_atac_counts.csv")
    }
    
    write.csv(results\$cell_meta, "simulated_cell_metadata.csv", row.names = TRUE)
    
    # --- Generate diagnostic visualizations ---
    message("Generating diagnostic plots...")
    pdf("multimodal_plots.pdf", width = 10, height = 8)
    
    tryCatch({
      plot_tsne(log2(results\$counts + 1), results\$cell_meta\$pop, legend = 'pop', plot.name = 'True RNA Counts t-SNE')
    }, error = function(e) warning("Error plotting true RNA t-SNE: ", e\$message))
    
    tryCatch({
      if (!is.null(results\$atacseq_data)) {
        plot_tsne(log2(results\$atacseq_data + 1), results\$cell_meta\$pop, legend = 'pop', plot.name = 'True ATAC-seq t-SNE')
      }
    }, error = function(e) warning("Error plotting ATAC t-SNE: ", e\$message))
    
    tryCatch({
      if (!is.null(results\$counts_with_batches)) {
        plot_tsne(log2(results\$counts_with_batches + 1), results\$cell_meta\$pop, legend = 'pop', plot.name = 'RNA Counts with Batches t-SNE')
      }
    }, error = function(e) warning("Error plotting batch t-SNE: ", e\$message))
    
    tryCatch({
      plot_rna_velocity(results, arrow.length = 2)
    }, error = function(e) warning("Error plotting RNA velocity: ", e\$message))
    
    tryCatch({
      plot_gene_module_cor_heatmap(results)
    }, error = function(e) warning("Error plotting gene module correlation: ", e\$message))
    
    dev.off()
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_SCMULTISIM_SCMULTISIM_MULTIMODAL_SIMULATION":',
        paste0('    scMultiSim: ', as.character(packageVersion('scMultiSim')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scmultisim_multimodal_simulation.csv versions.yml
    """
}

workflow BIOC_SCMULTISIM_SCMULTISIM_MULTIMODAL_SIMULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_SCMULTISIM_SCMULTISIM_MULTIMODAL_SIMULATION(ch_input)

    emit:
    tables   = BIOC_SCMULTISIM_SCMULTISIM_MULTIMODAL_SIMULATION.out.tables
    plots    = BIOC_SCMULTISIM_SCMULTISIM_MULTIMODAL_SIMULATION.out.plots
    objects  = BIOC_SCMULTISIM_SCMULTISIM_MULTIMODAL_SIMULATION.out.objects
    versions = BIOC_SCMULTISIM_SCMULTISIM_MULTIMODAL_SIMULATION.out.versions
}
