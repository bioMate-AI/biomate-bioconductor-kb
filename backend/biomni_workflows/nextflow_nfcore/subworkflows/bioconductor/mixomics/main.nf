#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mixOmics — pca_spca
// Perform unsupervised dimensionality reduction and select key variables explaining the variance of a single dataset.
// Input: expression_matrix.csv
// Container: quay.io/biocontainers/bioconductor-mixomics:6.34.0--r45h575d39b_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: mixOmics
// Visualizations: box plot, PCA plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Tune the number of principal components using tune.pca
//  * 2. [Core Analysis] Run PCA using pca
//  * 3. [Core Analysis] Extract and rank informative variables using selectVar
//  * 4. [Visualization & Output] Visualize samples and variables using plotIndiv, plotVar, and biplot
//  * 5. [Core Analysis] Tune the number of variables to select using tune.spca
//  * 6. [Core Analysis] Run final sparse PCA using spca
//  * 7. [Visualization & Output] Visualize sparse PCA results using plotIndiv, plotVar, biplot, and plotLoadings

nextflow.enable.dsl = 2

process BIOC_MIXOMICS_PCA_SPCA {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
        
        # Load required library
        library(mixOmics)
        
        # 1. Read the user input file
        if (!file.exists("expression_matrix.csv")) {
          stop("Error: 'expression_matrix.csv' not found in the working directory.")
        }
        
        X_df <- read.csv("expression_matrix.csv", row.names = 1, header = TRUE)
        X <- as.matrix(X_df)
        
        # Check dimensions of data
        dim(X)
        
        # Since no group metadata is provided in the input, we create a dummy grouping factor
        # for visualization purposes (e.g., dividing samples into two groups)
        group_factor <- factor(rep(c("GroupA", "GroupB"), length.out = nrow(X)))
        
        # 2. PCA Workflow
        # Step 2.1: Choose the number of components
        ncomp_tune <- min(10, ncol(X), nrow(X) - 1)
        tune.pca.multi <- tune.pca(X, ncomp = ncomp_tune, scale = TRUE)
        
        # Save PCA tuning plot
        pdf("pca_tuning_screeplot.pdf")
        plot(tune.pca.multi)
        dev.off()
        
        # Step 2.2: Run PCA with fewer components
        ncomp_final <- min(3, ncol(X), nrow(X) - 1)
        final.pca.multi <- pca(X, ncomp = ncomp_final, center = TRUE, scale = TRUE)
        
        # Extract and save explained variance metrics
        final.pca.multi\$var.tot
        final.pca.multi\$prop_expl_var\$X
        final.pca.multi\$cum.var
        
        pca_variance_metrics <- data.frame(
          Component = paste0("PC", 1:ncomp_final),
          Prop_Explained_Variance = final.pca.multi\$prop_expl_var\$X,
          Cumulative_Variance = final.pca.multi\$cum.var
        )
        write.csv(pca_variance_metrics, "pca_explained_variance.csv", row.names = FALSE)
        
        # Step 2.3: Identify the informative variables
        pca_selected_comp1 <- selectVar(final.pca.multi, comp = 1)\$value
        head(pca_selected_comp1)
        write.csv(pca_selected_comp1, "pca_selected_variables_comp1.csv")
        
        # Step 2.4: Visualize samples and variables
        pdf("pca_diagnostic_plots.pdf")
        
        # Sample plot
        plotIndiv(final.pca.multi,
                  comp = 1:min(2, ncomp_final),   # Specify components to plot
                  ind.names = TRUE, # Show row names of samples
                  group = group_factor,
                  title = 'PCA comp 1 - 2',
                  legend = TRUE, legend.title = 'Group')
        
        # Variable plot
        plotVar(final.pca.multi, comp = 1:min(2, ncomp_final),
                var.names = TRUE,
                cex = 3,         # To change the font size
                title = 'PCA variable plot comp 1 - 2')
        
        # Biplot
        biplot(final.pca.multi, group = group_factor, 
               legend.title = 'Group')
        
        dev.off()
        
        # Boxplot of the top variable from PCA Component 1
        top_var_name <- rownames(pca_selected_comp1)[1]
        if (!is.null(top_var_name) && top_var_name %in% colnames(X)) {
          top_var_scale <- scale(X[, top_var_name], center = TRUE, scale = TRUE)
          
          pdf("pca_top_variable_boxplot.pdf")
          boxplot(top_var_scale ~
                  group_factor, col = color.mixo(1:length(levels(group_factor))),
                  xlab = 'Groups', ylab = 'Expression levels, scaled',
                  cex.axis = 0.5, # Font size
                  main = paste(top_var_name, 'variable'))
          dev.off()
        }
        
        # 3. Sparse PCA Workflow
        # Step 3.1: Choose the number of variables to select
        max_features <- ncol(X)
        grid.keepX <- unique(round(seq(min(5, max_features), min(30, max_features), length.out = 6)))
        
        set.seed(30) # For reproducibility
        tune.spca.result <- tune.spca(X, ncomp = min(3, ncol(X), nrow(X) - 1), 
                                      folds = min(5, nrow(X)), 
                                      test.keepX = grid.keepX, nrepeat = 10) 
        
        tune.spca.result\$choice.keepX
        
        pdf("spca_tuning_plot.pdf")
        plot(tune.spca.result)
        dev.off()
        
        # Step 3.2: Final sparse PCA
        ncomp_spca <- min(2, ncol(X), nrow(X) - 1)
        keepX.select <- tune.spca.result\$choice.keepX[1:ncomp_spca]
        final.spca.multi <- spca(X, ncomp = ncomp_spca, keepX = keepX.select)
        
        final.spca.multi\$prop_expl_var\$X
        
        spca_variance_metrics <- data.frame(
          Component = paste0("PC", 1:ncomp_spca),
          Prop_Explained_Variance = final.spca.multi\$prop_expl_var\$X
        )
        write.csv(spca_variance_metrics, "spca_explained_variance.csv", row.names = FALSE)
        
        # Step 3.3: Sample and variable plots for sPCA
        pdf("spca_diagnostic_plots.pdf")
        
        # Sample plot
        plotIndiv(final.spca.multi,
                  comp = 1:min(2, ncomp_spca),   # Specify components to plot
                  ind.names = TRUE, # Show row names of samples
                  group = group_factor,
                  title = 'sPCA comp 1 - 2',
                  legend = TRUE, legend.title = 'Group')
        
        # Biplot
        biplot(final.spca.multi, group = group_factor, 
               legend = FALSE)
        
        # Variable plot
        plotVar(final.spca.multi, comp = 1:min(2, ncomp_spca), var.names = TRUE,
                cex = 3, # To change the font size
                title = 'sPCA comp 1 - 2')
        
        # Loading plot
        plotLoadings(final.spca.multi, comp = min(2, ncomp_spca))
        
        dev.off()
        
        # Extract and save sPCA selected variables
        spca_selected_comp2 <- selectVar(final.spca.multi, comp = min(2, ncomp_spca))\$value
        head(spca_selected_comp2)
        write.csv(spca_selected_comp2, "spca_selected_variables_comp2.csv")
        
        # Save final models as RDS objects
        saveRDS(final.pca.multi, "final_pca_model.rds")
        saveRDS(final.spca.multi, "final_spca_model.rds")

    writeLines(c(
        '"BIOC_MIXOMICS_PCA_SPCA":',
        paste0('    mixOmics: ', as.character(packageVersion('mixOmics')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pca_spca.csv versions.yml
    """
}

workflow BIOC_MIXOMICS_PCA_SPCA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv ] ]

    main:
    BIOC_MIXOMICS_PCA_SPCA(ch_input)

    emit:
    tables   = BIOC_MIXOMICS_PCA_SPCA.out.tables
    plots    = BIOC_MIXOMICS_PCA_SPCA.out.plots
    objects  = BIOC_MIXOMICS_PCA_SPCA.out.objects
    versions = BIOC_MIXOMICS_PCA_SPCA.out.versions
}
