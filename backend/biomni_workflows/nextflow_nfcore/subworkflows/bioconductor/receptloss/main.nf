#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: receptLoss — recept_loss_detection
// Identify genes with lost expression in tumor subsets relative to normal tissue.
// Input: Gene expression dataset
// Container: quay.io/biocontainers/bioconductor-receptloss:1.18.0--r44hdfd78af_0
// R packages: SummarizedExperiment, dplyr, ggplot2, receptLoss
// Bioconductor: 3.20 | R: 4.4
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_RECEPTLOSS_RECEPT_LOSS_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-receptloss:1.18.0--r44hdfd78af_0"

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
    .bm_deps <- c("SummarizedExperiment", "dplyr", "ggplot2", "receptLoss")
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
    
    # --- Install and load the required packages ---
    if (!requireNamespace("receptLoss", quietly = TRUE)) {
      if (!requireNamespace("BiocManager", quietly = TRUE)) {
        install.packages("BiocManager", repos = "https://cloud.r-project.org")
      }
      tryCatch({
        BiocManager::install("receptLoss", update = FALSE, ask = FALSE, quiet = TRUE)
      }, error = function(e) {
        if (!requireNamespace("remotes", quietly = TRUE)) {
          install.packages("remotes", repos = "https://cloud.r-project.org")
        }
        remotes::install_git("https://git.bioconductor.org/packages/receptLoss", upgrade = "never")
      })
    }
    
    library(receptLoss)
    library(SummarizedExperiment)
    
    # --- Read user input files from the working directory ---
    # The pipeline expects either:
    #   - A single 'summarized_experiment.rds' file containing a SummarizedExperiment object, OR
    #   - 'expression_matrix.csv' (genes as rows, samples as columns) and 'sample_metadata.csv' (samples as rows)
    if (file.exists("summarized_experiment.rds")) {
      message("Loading SummarizedExperiment from RDS...")
      se <- readRDS("summarized_experiment.rds")
    } else if (file.exists("expression_matrix.csv") && file.exists("sample_metadata.csv")) {
      message("Loading expression matrix and metadata from CSV files...")
      exprs <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
      metadata <- read.csv("sample_metadata.csv", row.names = 1)
      
      # Align samples between expression matrix and metadata
      common_samples <- intersect(colnames(exprs), rownames(metadata))
      if (length(common_samples) == 0) {
        stop("Error: No common samples found between expression matrix and metadata.")
      }
      
      exprs <- as.matrix(exprs[, common_samples, drop = FALSE])
      metadata <- metadata[common_samples, , drop = FALSE]
      
      se <- SummarizedExperiment(assays = list(counts = exprs), colData = metadata)
    } else {
      stop("Error: Missing input files. Please provide 'summarized_experiment.rds' or both 'expression_matrix.csv' and 'sample_metadata.csv' in the working directory.")
    }
    
    # --- Auto-detect grouping column and tumor/normal values ---
    col_names <- colnames(colData(se))
    group_col <- NULL
    for (col in c("group", "status", "type", "condition", col_names)) {
      if (col %in% col_names) {
        group_col <- col
        break
      }
    }
    
    if (is.null(group_col)) {
      stop("Error: Could not find a suitable metadata column for grouping. Please ensure 'group', 'status', 'type', or 'condition' is present in metadata.")
    }
    
    unique_vals <- unique(colData(se)[[group_col]])
    normal_val <- NULL
    tumor_val <- NULL
    
    for (val in unique_vals) {
      val_lower <- tolower(as.character(val))
      if (val_lower %in% c("normal", "control", "nt", "n")) {
        normal_val <- val
      } else if (val_lower %in% c("tumor", "cancer", "tp", "t", "case")) {
        tumor_val <- val
      }
    }
    
    # Fallback if standard names are not found
    if (is.null(normal_val) || is.null(tumor_val)) {
      if (length(unique_vals) >= 2) {
        normal_val <- unique_vals[1]
        tumor_val <- unique_vals[2]
        message(sprintf("Using '%s' as normal and '%s' as tumor group by default.", normal_val, tumor_val))
      } else {
        stop("Error: Grouping column must have at least 2 unique values (representing normal and tumor groups).")
      }
    }
    
    # --- Run the expression loss identification workflow ---
    message("Running receptLoss analysis...")
    results <- receptLoss(
      se = se, 
      groupCol = group_col, 
      normalGroup = normal_val, 
      tumorGroup = tumor_val
    )
    
    # --- Save meaningful results ---
    message("Saving results...")
    saveRDS(results, "recept_loss_results.rds")
    
    if (is.data.frame(results)) {
      write.csv(results, "recept_loss_results.csv", row.names = TRUE)
    } else {
      # If results is a list or other object, attempt to extract a table or write as text
      tryCatch({
        write.csv(as.data.frame(results), "recept_loss_results.csv", row.names = TRUE)
      }, error = function(e) {
        sink("recept_loss_results_summary.txt")
        print(results)
        sink()
      })
    }
    
    # --- Generate visualization for the top gene with expression ---
    tryCatch({
      top_gene <- NULL
      if (is.data.frame(results) && nrow(results) > 0) {
        # Try to find a p-value or FDR column to sort by
        p_cols <- grep("p.val|pvalue|fdr|qval|adj", colnames(results), ignore.case = TRUE, value = TRUE)
        if (length(p_cols) > 0) {
          results_sorted <- results[order(results[[p_cols[1]]]), ]
          top_gene <- rownames(results_sorted)[1]
        } else {
          top_gene <- rownames(results)[1]
        }
      } else if (is.character(results) && length(results) > 0) {
        top_gene <- results[1]
      }
      
      if (!is.null(top_gene)) {
        message(sprintf("Plotting expression loss for top gene: %s", top_gene))
        pdf("top_gene_loss_plot.pdf", width = 7, height = 5)
        if (exists("plotLoss", mode = "function")) {
          p <- plotLoss(
            se = se, 
            gene = top_gene, 
            groupCol = group_col, 
            normalGroup = normal_val, 
            tumorGroup = tumor_val
          )
          if (inherits(p, "ggplot")) {
            print(p)
          }
        }
        dev.off()
      }
    }, error = function(e) {
      warning("Could not generate plot: ", e\$message)
    })
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_RECEPTLOSS_RECEPT_LOSS_DETECTION":',
        paste0('        receptLoss: ', as.character(packageVersion("receptLoss")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_recept_loss_detection.csv versions.yml
    """
}

workflow BIOC_RECEPTLOSS_RECEPT_LOSS_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Gene expression dataset ] ]

    main:
    BIOC_RECEPTLOSS_RECEPT_LOSS_DETECTION(ch_input)

    emit:
    tables   = BIOC_RECEPTLOSS_RECEPT_LOSS_DETECTION.out.tables
    plots    = BIOC_RECEPTLOSS_RECEPT_LOSS_DETECTION.out.plots
    objects  = BIOC_RECEPTLOSS_RECEPT_LOSS_DETECTION.out.objects
    versions = BIOC_RECEPTLOSS_RECEPT_LOSS_DETECTION.out.versions
}
