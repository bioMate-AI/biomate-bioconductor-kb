#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowClust — standard_clustering_and_outliers
// Perform robust model-based clustering on flow cytometry data, select the best model using BIC, adjust outlier identification rules, and visualize the results.
// Input: rituximab
// Container: quay.io/biocontainers/bioconductor-flowclust:3.48.0--r45h01b2380_0
// R packages: flowClust, flowCore, flowStats
// Bioconductor: 3.20 | R: 4.4
// Requires: flowClust, flowCore
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run initial single-cluster clustering to identify and remove outliers
//  * 2. [Core Analysis] Run multi-cluster estimation on selected parameters
//  * 3. [Visualization & Output] Select the best model using BIC and summarize
//  * 4. [Core Analysis] Adjust outlier rules (quantile level and posterior probability cutoff)
//  * 5. [Visualization & Output] Visualize results using scatter, contour, image, and histogram plots

nextflow.enable.dsl = 2

process BIOC_FLOWCLUST_STANDARD_CLUSTERING_AND_OUTLIERS {
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
    .bm_deps <- c("flowClust", "flowCore", "flowStats")
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
        library(flowClust)
        library(flowCore)
        
        # -----------------------------------------------------------------------------
        # Stage 0: Read User Input
        # -----------------------------------------------------------------------------
        # The pipeline must read the 'rituximab' flowFrame object from the working directory.
        if (file.exists("rituximab")) {
          rituximab <- readRDS("rituximab")
        } else if (file.exists("rituximab.rds")) {
          rituximab <- readRDS("rituximab.rds")
        } else {
          stop("Error: Input file 'rituximab' or 'rituximab.rds' not found in the working directory.")
        }
        
        # Print summary of the input flowFrame
        sink("rituximab_summary.txt")
        print(summary(rituximab))
        sink()
        
        # -----------------------------------------------------------------------------
        # Stage 1: Run initial single-cluster clustering to identify and remove outliers
        # -----------------------------------------------------------------------------
        res1 <-
        	flowClust(
        		rituximab,
        		varNames = c("FSC.H", "SSC.H"),
        		K = 1,
        		B = 100
        	)
        
        # Save the first stage clustering result
        saveRDS(res1, "res1.rds")
        
        # Subset the flowFrame to remove outliers
        rituximab2 <- rituximab[rituximab %in% res1, ]
        saveRDS(rituximab2, "rituximab2.rds")
        
        # -----------------------------------------------------------------------------
        # Stage 2: Run multi-cluster estimation on selected parameters
        # -----------------------------------------------------------------------------
        res2 <-
        	flowClust(
        		rituximab2,
        		varNames = c("FL1.H", "FL3.H"),
        		K = 1:6,
        		B = 100
        	)
        
        # Save the second stage clustering result
        saveRDS(res2, "res2.rds")
        
        # -----------------------------------------------------------------------------
        # Stage 3: Select the best model using BIC and summarize
        # -----------------------------------------------------------------------------
        bic_values <- criterion(res2, "BIC")
        
        # Save BIC values to a CSV file
        bic_df <- data.frame(K = 1:6, BIC = bic_values)
        write.csv(bic_df, "bic_values.csv", row.names = FALSE)
        
        # Summarize the 3-cluster model (index 3 of res2)
        sink("summary_res2_k3_default.txt")
        print(summary(res2[[3]]))
        sink()
        
        # -----------------------------------------------------------------------------
        # Stage 4: Adjust outlier rules (quantile level and posterior probability cutoff)
        # -----------------------------------------------------------------------------
        # Apply the 95% quantile rule
        ruleOutliers(res2[[3]]) <- list(level = 0.95)
        sink("summary_res2_k3_level95.txt")
        print(summary(res2[[3]]))
        sink()
        
        # Combine with z.cutoff (posterior probability threshold)
        ruleOutliers(res2[[3]]) <- list(z.cutoff = 0.6)
        sink("summary_res2_k3_zcutoff06.txt")
        print(summary(res2[[3]]))
        sink()
        
        # Run alternative clustering with min/max boundary filtering
        res_alt <- flowClust(
        	rituximab2,
        	varNames = c("FL1.H", "FL3.H"),
        	K = 2,
        	B = 100,
        	min = c(0, 0),
        	max = c(400, 800)
        )
        saveRDS(res_alt, "res_alt.rds")
        
        # -----------------------------------------------------------------------------
        # Stage 5: Visualize results using scatter, contour, image, and histogram plots
        # -----------------------------------------------------------------------------
        pdf("clustering_plots.pdf", width = 8, height = 6)
        
        # Scatter plot with custom outlier rules
        plot(res2[[3]],
        	  data = rituximab2,
        	  level = 0.8,
        	  z.cutoff = 0)
        
        # Density estimation and contour/image plots
        res2.den <- density(res2[[3]], data = rituximab2)
        plot(res2.den)
        plot(res2.den, type = "image")
        
        # Histograms along chosen dimensions
        hist(res2[[3]], data = rituximab2, subset = "FL1.H")
        hist(res2[[3]], data = rituximab2, subset = 1)
        
        dev.off()

    writeLines(c(
        '"BIOC_FLOWCLUST_STANDARD_CLUSTERING_AND_OUTLIERS":',
        paste0('    flowClust: ', as.character(packageVersion('flowClust')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_clustering_and_outliers.csv versions.yml
    """
}

workflow BIOC_FLOWCLUST_STANDARD_CLUSTERING_AND_OUTLIERS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ rituximab ] ]

    main:
    BIOC_FLOWCLUST_STANDARD_CLUSTERING_AND_OUTLIERS(ch_input)

    emit:
    tables   = BIOC_FLOWCLUST_STANDARD_CLUSTERING_AND_OUTLIERS.out.tables
    plots    = BIOC_FLOWCLUST_STANDARD_CLUSTERING_AND_OUTLIERS.out.plots
    objects  = BIOC_FLOWCLUST_STANDARD_CLUSTERING_AND_OUTLIERS.out.objects
    versions = BIOC_FLOWCLUST_STANDARD_CLUSTERING_AND_OUTLIERS.out.versions
}
