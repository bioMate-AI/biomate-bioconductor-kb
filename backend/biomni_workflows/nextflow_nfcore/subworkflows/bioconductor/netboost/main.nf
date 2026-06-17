#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: netboost — netboost_dimension_reduction
// Perform boosting-supported network clustering, extract module eigengenes, plot dendrograms, and transfer the clustering to new datasets.
// Input: tcga_aml_meth_rna_chr18
// Container: quay.io/biocontainers/bioconductor-netboost:2.0.0--r41h399db7b_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: netboost
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and input dataset
//  * 2. [Core Analysis] Run the netboost pipeline to identify modules and aggregate them into principal components
//  * 3. [Core Analysis] Inspect results (module names, colors, and explained variance)
//  * 4. [Visualization & Output] Plot the dendrogram using nb_plot_dendro
//  * 5. [Core Analysis] Transfer the clustering to a new dataset using nb_transfer

nextflow.enable.dsl = 2

process BIOC_NETBOOST_NETBOOST_DIMENSION_REDUCTION {
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
    .bm_deps <- c("netboost")
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
        library(netboost)
        
        # 1. Load the input dataset from the working directory
        # We check for common formats (RDS, CSV, TSV, or unextended file)
        input_file <- "tcga_aml_meth_rna_chr18"
        
        if (file.exists(paste0(input_file, ".rds"))) {
          tcga_aml_meth_rna_chr18 <- readRDS(paste0(input_file, ".rds"))
        } else if (file.exists(paste0(input_file, ".csv"))) {
          tcga_aml_meth_rna_chr18 <- read.csv(paste0(input_file, ".csv"), row.names = 1, check.names = FALSE)
          tcga_aml_meth_rna_chr18 <- as.matrix(tcga_aml_meth_rna_chr18)
        } else if (file.exists(paste0(input_file, ".txt"))) {
          tcga_aml_meth_rna_chr18 <- read.table(paste0(input_file, ".txt"), header = TRUE, row.names = 1, check.names = FALSE)
          tcga_aml_meth_rna_chr18 <- as.matrix(tcga_aml_meth_rna_chr18)
        } else if (file.exists(input_file)) {
          tcga_aml_meth_rna_chr18 <- tryCatch({
            readRDS(input_file)
          }, error = function(e) {
            as.matrix(read.csv(input_file, row.names = 1, check.names = FALSE))
          })
        } else {
          stop("Error: Input file 'tcga_aml_meth_rna_chr18' (with or without .rds/.csv/.txt extension) not found in the working directory.")
        }
        
        # Print dimensions of the loaded dataset
        print("Dimensions of input dataset:")
        print(dim(tcga_aml_meth_rna_chr18))
        
        # 2. Run the netboost pipeline to identify modules and aggregate them into principal components
        results <- netboost(
          datan = tcga_aml_meth_rna_chr18,
          stepno = 20L,
          soft_power = 3L,
          min_cluster_size = 10L,
          n_pc = 2,
          scale = TRUE,
          ME_diss_thres = 0.25
        )
        
        # 3. Inspect results (module names, colors, and explained variance)
        print("Names of results list:")
        print(names(results))
        
        print("Column names of MEs (Module Eigengenes):")
        print(colnames(results\$MEs))
        
        n_cols <- min(5, ncol(results\$var_explained))
        print(paste("Variance explained by the first", n_cols, "modules:"))
        if (n_cols > 0) {
          print(results\$var_explained[, seq_len(n_cols), drop = FALSE])
        } else {
          print("No modules found.")
        }
        
        if (length(results\$colors) > 0) {
          unique_colors <- unique(results\$colors)
          # Prefer a non-background module (0 is typically background) if available
          mod_to_check <- if (any(unique_colors != 0)) unique_colors[unique_colors != 0][1] else unique_colors[1]
          print(paste("Features belonging to module", mod_to_check, ":"))
          features_mod <- results\$names[results\$colors == mod_to_check]
          print(features_mod)
        } else {
          print("No modules found to display features.")
        }
        
        # 4. Plot the dendrogram using nb_plot_dendro
        pdf("netboost_dendrogram.pdf", width = 10, height = 7)
        set.seed(123)
        nb_plot_dendro(nb_summary = results, labels = FALSE, colorsrandom = TRUE)
        dev.off()
        
        # 5. Transfer the clustering to a new dataset (using the same dataset for validation)
        ME_transfer <- nb_transfer(
          nb_summary = results,
          new_data = tcga_aml_meth_rna_chr18,
          scale = TRUE
        )
        
        # Verify transfer consistency
        transfer_check <- all(round(results\$MEs, 10) == round(ME_transfer, 10))
        print(paste("Transfer verification (all equal):", transfer_check))
        
        # Write verification result to a text file
        writeLines(
          text = c(
            paste("Transfer verification (all equal):", transfer_check),
            paste("Timestamp:", Sys.time())
          ),
          con = "transfer_verification.txt"
        )
        
        # Save meaningful outputs to files
        saveRDS(results, file = "netboost_results.rds")
        write.csv(as.data.frame(results\$MEs), file = "module_eigengenes.csv", row.names = TRUE)
        write.csv(as.data.frame(results\$var_explained), file = "variance_explained.csv", row.names = TRUE)
        write.csv(as.data.frame(ME_transfer), file = "transferred_eigengenes.csv", row.names = TRUE)
        write.csv(data.frame(Feature = results\$names, Module_Color = results\$colors), file = "feature_module_assignments.csv", row.names = FALSE)
        
        print("Pipeline completed successfully. Outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_NETBOOST_NETBOOST_DIMENSION_REDUCTION":',
        paste0('    netboost: ', as.character(packageVersion('netboost')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_netboost_dimension_reduction.csv versions.yml
    """
}

workflow BIOC_NETBOOST_NETBOOST_DIMENSION_REDUCTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tcga_aml_meth_rna_chr18 ] ]

    main:
    BIOC_NETBOOST_NETBOOST_DIMENSION_REDUCTION(ch_input)

    emit:
    tables   = BIOC_NETBOOST_NETBOOST_DIMENSION_REDUCTION.out.tables
    plots    = BIOC_NETBOOST_NETBOOST_DIMENSION_REDUCTION.out.plots
    objects  = BIOC_NETBOOST_NETBOOST_DIMENSION_REDUCTION.out.objects
    versions = BIOC_NETBOOST_NETBOOST_DIMENSION_REDUCTION.out.versions
}
