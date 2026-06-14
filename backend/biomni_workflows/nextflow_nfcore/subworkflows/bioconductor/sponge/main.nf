#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SPONGE — cerna_network_inference
// Identify significant ceRNA interactions and construct a ceRNA network from paired gene and miRNA expression data.
// Input: gene_expr, mir_expr, targetscan_symbol
// Container: quay.io/biocontainers/bioconductor-sponge:1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SPONGE, htmlwidgets
// Visualizations: network plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter gene-miRNA interactions using regularized regression
//  * 2. [Core Analysis] Compute sensitivity correlation (mscor) for gene pairs
//  * 3. [Input & Preparation] Build null model for p-value computation
//  * 4. [Core Analysis] Compute empirical p-values and adjust for multiple testing
//  * 5. [Visualization & Output] Filter for significant interactions and plot network/centralities

nextflow.enable.dsl = 2

process BIOC_SPONGE_CERNA_NETWORK_INFERENCE {
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
    .bm_deps <- c("SPONGE")
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
        library(SPONGE)
        
        # Helper function to robustly read user input files from the working directory
        read_input <- function(base_name) {
          # Check RDS format
          if (file.exists(paste0(base_name, ".rds"))) {
            message("Reading ", base_name, ".rds")
            return(readRDS(paste0(base_name, ".rds")))
          }
          # Check CSV format
          if (file.exists(paste0(base_name, ".csv"))) {
            message("Reading ", base_name, ".csv")
            return(as.matrix(read.csv(paste0(base_name, ".csv"), row.names = 1, check.names = FALSE)))
          }
          # Check TSV format
          if (file.exists(paste0(base_name, ".tsv"))) {
            message("Reading ", base_name, ".tsv")
            return(as.matrix(read.delim(paste0(base_name, ".tsv"), row.names = 1, check.names = FALSE)))
          }
          # Check plain file
          if (file.exists(base_name)) {
            message("Reading ", base_name)
            obj <- tryCatch(readRDS(base_name), error = function(e) NULL)
            if (!is.null(obj)) return(obj)
            return(as.matrix(read.table(base_name, header = TRUE, row.names = 1, check.names = FALSE)))
          }
          stop(paste("Error: Required input file not found for", base_name))
        }
        
        # 1. Read user input files
        message("Loading input datasets...")
        gene_expr <- read_input("gene_expr")
        mir_expr <- read_input("mir_expr")
        targetscan_symbol <- read_input("targetscan_symbol")
        
        # 2. Filter gene-miRNA interactions using regularized regression
        message("Filtering gene-miRNA interactions...")
        genes_miRNA_candidates <- sponge_gene_miRNA_interaction_filter(
          gene_expr = gene_expr,
          mir_expr = mir_expr,
          mir_predicted_targets = targetscan_symbol
        )
        
        # 3. Compute sensitivity correlation (mscor) for gene pairs
        message("Computing ceRNA interactions...")
        ceRNA_interactions <- sponge(
          gene_expr = gene_expr,
          mir_expr = mir_expr,
          mir_interactions = genes_miRNA_candidates
        )
        
        # 4. Build null model for p-value computation
        message("Building null model...")
        mscor_null_model <- sponge_build_null_model(
          number_of_datasets = 1e6, 
          number_of_samples = nrow(gene_expr)
        )
        
        # Plot simulation results
        message("Plotting simulation results...")
        pdf("sponge_simulation_results.pdf", width = 10, height = 7)
        tryCatch({
          print(sponge_plot_simulation_results(mscor_null_model))
        }, error = function(e) {
          message("Warning: Could not plot simulation results: ", e\$message)
        })
        dev.off()
        
        # 5. Compute empirical p-values and adjust for multiple testing
        message("Computing empirical p-values...")
        ceRNA_interactions_sign <- sponge_compute_p_values(
          sponge_result = ceRNA_interactions, 
          null_model = mscor_null_model
        )
        
        # 6. Filter for significant interactions
        message("Filtering for significant interactions...")
        ceRNA_interactions_fdr <- ceRNA_interactions_sign[which(ceRNA_interactions_sign\$p.adj < 0.2),]
        
        # Plot network
        message("Plotting ceRNA network...")
        tryCatch({
          net_plot <- sponge_plot_network(ceRNA_interactions_fdr, genes_miRNA_candidates)
          if (!is.null(net_plot) && requireNamespace("htmlwidgets", quietly = TRUE)) {
            htmlwidgets::saveWidget(net_plot, "sponge_network.html", selfcontained = TRUE)
            message("Saved interactive network plot to 'sponge_network.html'")
          }
        }, error = function(e) {
          message("Warning: Could not plot or save network: ", e\$message)
        })
        
        # 7. Compute network centralities
        message("Computing network centralities...")
        network_centralities <- sponge_node_centralities(ceRNA_interactions_fdr)
        
        # 8. Compute weighted network centralities
        message("Computing weighted network centralities...")
        ceRNA_interactions_fdr_weight <- ceRNA_interactions_fdr
        ceRNA_interactions_fdr_weight\$weight <- -log10(ceRNA_interactions_fdr\$p.adj)
        weighted_network_centralities <- sponge_node_centralities(ceRNA_interactions_fdr_weight)
        
        # Plot network centralities
        message("Plotting network centralities...")
        pdf("sponge_network_centralities_top1.pdf", width = 7, height = 7)
        tryCatch({
          print(sponge_plot_network_centralities(weighted_network_centralities, top = 1))
        }, error = function(e) {
          message("Warning: Could not plot network centralities (top = 1): ", e\$message)
        })
        dev.off()
        
        pdf("sponge_network_centralities_btw_top1.pdf", width = 7, height = 7)
        tryCatch({
          print(sponge_plot_network_centralities(weighted_network_centralities, measure = "btw", top = 1))
        }, error = function(e) {
          message("Warning: Could not plot network centralities (btw, top = 1): ", e\$message)
        })
        dev.off()
        
        # 9. Save output files
        message("Saving output tables and objects...")
        saveRDS(genes_miRNA_candidates, "genes_miRNA_candidates.rds")
        saveRDS(ceRNA_interactions, "ceRNA_interactions.rds")
        saveRDS(mscor_null_model, "mscor_null_model.rds")
        saveRDS(ceRNA_interactions_sign, "ceRNA_interactions_sign.rds")
        saveRDS(ceRNA_interactions_fdr, "ceRNA_interactions_fdr.rds")
        saveRDS(network_centralities, "network_centralities.rds")
        saveRDS(weighted_network_centralities, "weighted_network_centralities.rds")
        
        write.csv(ceRNA_interactions, "ceRNA_interactions.csv", row.names = FALSE)
        write.csv(ceRNA_interactions_sign, "ceRNA_interactions_sign.csv", row.names = FALSE)
        write.csv(ceRNA_interactions_fdr, "ceRNA_interactions_fdr.csv", row.names = FALSE)
        write.csv(network_centralities, "network_centralities.csv", row.names = FALSE)
        write.csv(weighted_network_centralities, "weighted_network_centralities.csv", row.names = FALSE)
        
        message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_SPONGE_CERNA_NETWORK_INFERENCE":',
        paste0('    SPONGE: ', as.character(packageVersion('SPONGE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cerna_network_inference.csv versions.yml
    """
}

workflow BIOC_SPONGE_CERNA_NETWORK_INFERENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_expr, mir_expr, targetscan_symbol ] ]

    main:
    BIOC_SPONGE_CERNA_NETWORK_INFERENCE(ch_input)

    emit:
    tables   = BIOC_SPONGE_CERNA_NETWORK_INFERENCE.out.tables
    plots    = BIOC_SPONGE_CERNA_NETWORK_INFERENCE.out.plots
    objects  = BIOC_SPONGE_CERNA_NETWORK_INFERENCE.out.objects
    versions = BIOC_SPONGE_CERNA_NETWORK_INFERENCE.out.versions
}
