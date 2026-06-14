#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MOFA2 — standard_mofa_analysis
// Train a standard multi-omic factor analysis model on multiple data modalities and perform downstream visualization and data extraction.
// Input: data, dt
// Container: quay.io/biocontainers/bioconductor-mofa2:1.20.2--r45h9ee0642_0
// R packages: ggplot2, MOFA2, pheatmap, tidyverse
// Bioconductor: 3.20 | R: 4.4
// Requires: MOFA2, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Create MOFA object
//  * 2. [Visualization & Output] Define data, model, and training options
//  * 3. [Visualization & Output] Prepare the MOFA object
//  * 4. [Visualization & Output] Train the model
//  * 5. [Visualization & Output] Perform downstream analysis

nextflow.enable.dsl = 2

process BIOC_MOFA2_STANDARD_MOFA_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("ggplot2", "MOFA2", "pheatmap", "tidyverse")
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
            library(MOFA2)
            library(ggplot2)
            
            # Read user inputs from the working directory
            # Assuming standard RDS format for R objects
            data <- readRDS("data.rds")
            dt <- readRDS("dt.rds")
            
            # --- Create MOFA object ---
            if (is.list(data) && !is.data.frame(data) && length(data) > 0) {
              MOFAobject <- create_mofa(data)
            } else {
              MOFAobject <- create_mofa(dt)
            }
            
            # Set up PDF to capture all downstream visualizations
            pdf("mofa_analysis_plots.pdf", width = 10, height = 8)
            
            print(plot_data_overview(MOFAobject))
            
            # --- Define data, model, and training options ---
            data_opts <- get_default_data_options(MOFAobject)
            model_opts <- get_default_model_options(MOFAobject)
            model_opts\$num_factors <- 10
            train_opts <- get_default_training_options(MOFAobject)
            
            # --- Prepare the MOFA object ---
            MOFAobject <- prepare_mofa(
              object = MOFAobject,
              data_options = data_opts,
              model_options = model_opts,
              training_options = train_opts
            )
            
            # --- Train the model ---
            outfile = file.path(tempdir(),"model.hdf5")
            MOFAobject.trained <- run_mofa(MOFAobject, outfile, use_basilisk=TRUE)
            
            # Load the trained model
            filepath <- outfile
            model <- load_model(filepath)
            print(plot_data_overview(model))
            
            # Add metadata to the model
            Nsamples = sum(get_dimensions(model)[["N"]])
            set.seed(42)
            sample_metadata <- data.frame(
              sample = unname(unlist(samples_names(model))),
              condition = sample(c("A","B"), size = Nsamples, replace = TRUE),
              age = sample(1:100, size = Nsamples, replace = TRUE)
            )
            samples_metadata(model) <- sample_metadata
            
            # --- Perform downstream analysis ---
            # Variance decomposition
            print(head(get_variance_explained(model)\$r2_total[[1]]))
            print(head(get_variance_explained(model)\$r2_per_factor[[1]]))
            print(plot_variance_explained(model, x="view", y="factor"))
            print(plot_variance_explained(model, x="view", y="factor", plot_total = TRUE)[[2]])
            
            # Factor visualization
            print(plot_factor(model, factor = 1:3, color_by = "age", shape_by = "condition"))
            p <- plot_factor(model, factors = c(1,2,3), color_by = "condition", dot_size = 3, dodge = TRUE, legend = FALSE, add_violin = TRUE, violin_alpha = 0.25)
            p <- p + scale_color_manual(values=c("A"="black", "B"="red")) + scale_fill_manual(values=c("A"="black", "B"="red"))
            print(p)
            print(plot_factors(model, factors = 1:3, color_by = "condition"))
            
            # Dynamically get view names for plotting
            view1 <- views_names(model)[1]
            view2 <- if (length(views_names(model)) > 1) views_names(model)[2] else views_names(model)[1]
            
            # Weight visualization
            print(plot_weights(model, view = view1, factor = 1, nfeatures = 10, scale = TRUE, abs = FALSE))
            print(plot_top_weights(model, view = view1, factor = 1, nfeatures = 10))
            
            # Data heatmaps and scatter plots
            print(plot_data_heatmap(model, view = view2, factor = 1, features = 20, cluster_rows = TRUE, cluster_cols = FALSE, show_rownames = TRUE, show_colnames = FALSE))
            print(plot_data_scatter(model, view = view2, factor = 1, features = 5, add_lm = TRUE, color_by = "condition"))
            
            # Non-linear dimensionality reduction
            set.seed(42)
            model <- run_umap(model)
            model <- run_tsne(model)
            print(plot_dimred(model, method = "TSNE", color_by = "condition", dot_size = 5))
            
            # Rename dimensions
            new_views <- c("Transcriptomics", "Proteomics")
            if (length(views_names(model)) > 2) {
              new_views <- c(new_views, paste("View", 3:length(views_names(model))))
            }
            views_names(model) <- new_views[1:length(views_names(model))]
            factors_names(model) <- paste("Factor", 1:get_dimensions(model)\$K, sep=" ")
            
            # Data extraction
            factors <- get_factors(model, factors = "all")
            weights <- get_weights(model, views = "all", factors = "all")
            data <- get_data(model)
            
            factors <- get_factors(model, as.data.frame = TRUE)
            weights <- get_weights(model, as.data.frame = TRUE)
            data <- get_data(model, as.data.frame = TRUE)
            
            # Close the plotting device
            dev.off()
            
            # Save extracted data and model outputs to the working directory
            write.csv(factors, "mofa_extracted_factors.csv", row.names = FALSE)
            write.csv(weights, "mofa_extracted_weights.csv", row.names = FALSE)
            write.csv(data, "mofa_extracted_data.csv", row.names = FALSE)
            file.copy(outfile, "mofa_trained_model.hdf5", overwrite = TRUE)

    writeLines(c(
        '"BIOC_MOFA2_STANDARD_MOFA_ANALYSIS":',
        paste0('    MOFA2: ', as.character(packageVersion('MOFA2')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_mofa_analysis.csv versions.yml
    """
}

workflow BIOC_MOFA2_STANDARD_MOFA_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data, dt ] ]

    main:
    BIOC_MOFA2_STANDARD_MOFA_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MOFA2_STANDARD_MOFA_ANALYSIS.out.tables
    plots    = BIOC_MOFA2_STANDARD_MOFA_ANALYSIS.out.plots
    objects  = BIOC_MOFA2_STANDARD_MOFA_ANALYSIS.out.objects
    versions = BIOC_MOFA2_STANDARD_MOFA_ANALYSIS.out.versions
}
