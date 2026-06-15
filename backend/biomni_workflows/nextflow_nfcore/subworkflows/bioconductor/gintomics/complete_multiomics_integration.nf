#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gINTomics — complete_multiomics_integration
// Perform a complete multi-omics integration using a MultiAssayExperiment, followed by downstream interactive visualization, static plotting, and functional enric
// Input: gene_exp_matrix.csv, miRNA_exp_matrix.csv, meth_matrix.csv, gene_cnv_matrix.csv, miRNA_cnv_matrix.csv
// Container: quay.io/biocontainers/r-base:4.3.1
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MultiAssayExperiment, gINTomics, htmlwidgets, shiny
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a MultiAssayExperiment object using create_multiassay
//  * 2. [Core Analysis] Run the complete multi-omics integration using run_multiomics
//  * 3. [Core Analysis] Extract model results using extract_model_res
//  * 4. [Visualization & Output] Launch the interactive Shiny visualization app using run_shiny
//  * 5. [Visualization & Output] Generate static plots (network, Venn, volcano, ridge, chromosome distribution, TF distribution)
//  * 6. [Visualization & Output] Run genomic enrichment using run_genomic_enrich and visualize with dot_plotly

nextflow.enable.dsl = 2

process BIOC_GINTOMICS_COMPLETE_MULTIOMICS_INTEGRATION {
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
    .bm_deps <- c("gINTomics", "MultiAssayExperiment", "shiny")
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
    library(gINTomics)
    library(MultiAssayExperiment)
    library(shiny)
    
    # -----------------------------------------------------------------------------
    # Stage 1: Read User Input Files and Create MultiAssayExperiment
    # -----------------------------------------------------------------------------
    
    message("Reading input matrices from the working directory...")
    
    gene_exp_matrix  <- as.matrix(read.csv("gene_exp_matrix.csv", row.names = 1, check.names = FALSE))
    miRNA_exp_matrix <- as.matrix(read.csv("miRNA_exp_matrix.csv", row.names = 1, check.names = FALSE))
    meth_matrix      <- as.matrix(read.csv("meth_matrix.csv", row.names = 1, check.names = FALSE))
    gene_cnv_matrix  <- as.matrix(read.csv("gene_cnv_matrix.csv", row.names = 1, check.names = FALSE))
    miRNA_cnv_matrix <- as.matrix(read.csv("miRNA_cnv_matrix.csv", row.names = 1, check.names = FALSE))
    
    message("Creating MultiAssayExperiment object...")
    new_multiassay <- create_multiassay(methylation = meth_matrix, 
                                        gene_exp = gene_exp_matrix,
                                        cnv_data = gene_cnv_matrix,
                                        miRNA_exp = miRNA_exp_matrix,
                                        miRNA_cnv_data = miRNA_cnv_matrix)
    
    print(new_multiassay)
    
    # -----------------------------------------------------------------------------
    # Stage 2: Run Complete Multi-Omics Integration
    # -----------------------------------------------------------------------------
    
    message("Running multi-omics integration...")
    multiomics_integration <- run_multiomics(data = new_multiassay)
    summary(multiomics_integration)
    
    # Save the integration model object
    saveRDS(multiomics_integration, "multiomics_integration_model.rds")
    
    # -----------------------------------------------------------------------------
    # Stage 3: Extract Model Results
    # -----------------------------------------------------------------------------
    
    message("Extracting model results...")
    data_table <- extract_model_res(multiomics_integration)
    data_table <- data_table[data_table\$cov!="(Intercept)",]
    
    # Save the extracted results table
    write.csv(data_table, "multiomics_integration_results.csv", row.names = FALSE)
    
    # -----------------------------------------------------------------------------
    # Stage 4: Launch Interactive Shiny App (Conditional on Interactive Session)
    # -----------------------------------------------------------------------------
    
    if (interactive()) {
      message("Launching interactive Shiny visualization app...")
      run_shiny(multiomics_integration)
    } else {
      message("Skipping interactive run_shiny() call in non-interactive mode.")
    }
    
    # -----------------------------------------------------------------------------
    # Stage 5: Generate Static Plots
    # -----------------------------------------------------------------------------
    
    message("Generating static plots...")
    pdf("gINTomics_static_plots.pdf", width = 10, height = 8)
    
    # Network plot
    tryCatch({
      message("Plotting network...")
      p_net <- plot_network(data_table, num_interactions = 200)
      print(p_net)
    }, error = function(e) {
      message("Failed to generate network plot: ", e\$message)
    })
    
    # Venn Diagram
    tryCatch({
      message("Plotting Venn diagram...")
      p_venn <- plot_venn(data_table)
      print(p_venn)
    }, error = function(e) {
      message("Failed to generate Venn diagram: ", e\$message)
    })
    
    # Volcano plots
    tryCatch({
      message("Plotting Volcano (CNV)...")
      p_vol_cnv <- plot_volcano(data_table, omics = "gene_genomic_res", cnv_met = "cnv")
      print(p_vol_cnv)
    }, error = function(e) {
      message("Failed to generate Volcano plot (CNV): ", e\$message)
    })
    
    tryCatch({
      message("Plotting Volcano (Methylation)...")
      p_vol_met <- plot_volcano(data_table, omics = "gene_genomic_res", cnv_met = "met")
      print(p_vol_met)
    }, error = function(e) {
      message("Failed to generate Volcano plot (Methylation): ", e\$message)
    })
    
    # Ridgeline plots
    tryCatch({
      message("Plotting Ridgeline (CNV)...")
      p_ridge_cnv <- plot_ridge(data_table, omics = "gene_genomic_res", cnv_met = "cnv")
      print(p_ridge_cnv)
    }, error = function(e) {
      message("Failed to generate Ridgeline plot (CNV): ", e\$message)
    })
    
    tryCatch({
      message("Plotting Ridgeline (Methylation)...")
      p_ridge_met <- plot_ridge(data_table, omics = "gene_genomic_res", cnv_met = "met")
      print(p_ridge_met)
    }, error = function(e) {
      message("Failed to generate Ridgeline plot (Methylation): ", e\$message)
    })
    
    # Chromosome distribution plot
    tryCatch({
      message("Plotting chromosome distribution...")
      p_chr <- plot_chr_distribution(data_table = data_table, omics = "gene_genomic_res")
      print(p_chr)
    }, error = function(e) {
      message("Failed to generate chromosome distribution plot: ", e\$message)
    })
    
    # TF distribution plot
    tryCatch({
      message("Plotting TF distribution...")
      p_tf <- plot_tf_distribution(data_table = data_table)
      print(p_tf)
    }, error = function(e) {
      message("Failed to generate TF distribution plot: ", e\$message)
    })
    
    dev.off()
    message("Static plots saved to 'gINTomics_static_plots.pdf'.")
    
    # -----------------------------------------------------------------------------
    # Stage 6: Functional Enrichment Analysis
    # -----------------------------------------------------------------------------
    
    message("Running genomic enrichment analysis...")
    tryCatch({
      gen_enr <- run_genomic_enrich(multiomics_integration, qvalueCutoff = 1, pvalueCutoff = 0.05, pAdjustMethod = "none")
      saveRDS(gen_enr, "genomic_enrichment_results.rds")
      
      message("Visualizing enrichment with dot_plotly...")
      p_enrich <- dot_plotly(gen_enr\$cnv[[1]]\$go)
      
      # Save the interactive plotly widget if htmlwidgets is available
      if (requireNamespace("htmlwidgets", quietly = TRUE)) {
        htmlwidgets::saveWidget(p_enrich, "enrichment_dot_plotly.html")
        message("Enrichment plot saved to 'enrichment_dot_plotly.html'.")
      } else {
        print(p_enrich)
      }
    }, error = function(e) {
      message("Failed to run or plot genomic enrichment: ", e\$message)
    })
    
    message("Pipeline complete.")

    writeLines(c(
        '"BIOC_GINTOMICS_COMPLETE_MULTIOMICS_INTEGRATION":',
        paste0('    gINTomics: ', as.character(packageVersion('gINTomics')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_complete_multiomics_integration.csv versions.yml
    """
}

workflow BIOC_GINTOMICS_COMPLETE_MULTIOMICS_INTEGRATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_exp_matrix.csv, miRNA_exp_matrix.csv, meth_matrix.csv, gene_cnv_matrix.csv, miRNA_cnv_matrix.csv ] ]

    main:
    BIOC_GINTOMICS_COMPLETE_MULTIOMICS_INTEGRATION(ch_input)

    emit:
    tables   = BIOC_GINTOMICS_COMPLETE_MULTIOMICS_INTEGRATION.out.tables
    plots    = BIOC_GINTOMICS_COMPLETE_MULTIOMICS_INTEGRATION.out.plots
    objects  = BIOC_GINTOMICS_COMPLETE_MULTIOMICS_INTEGRATION.out.objects
    versions = BIOC_GINTOMICS_COMPLETE_MULTIOMICS_INTEGRATION.out.versions
}
