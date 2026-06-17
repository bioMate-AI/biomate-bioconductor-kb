#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: edge — static_de_analysis
// Identify differentially expressed genes across distinct biological groups in a static experiment (without respect to time), adjusting for covariates.
// Input: gibexpr, gender, batch, location
// Container: quay.io/biocontainers/bioconductor-edge:2.42.0--r45h01b2380_0
// R packages: edge, ggplot2, reshape2
// Bioconductor: 3.20 | R: 4.4
// Requires: edge
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Build the deSet object using build_study with sampling="static"
//  * 2. [Core Analysis] Fit the models using fit_models
//  * 3. [Core Analysis] Perform significance testing using odp or lrt
//  * 4. [Core Analysis] Extract p-values, q-values, local FDR, and pi0 using qvalueObj

nextflow.enable.dsl = 2

process BIOC_EDGE_STATIC_DE_ANALYSIS {
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
    .bm_deps <- c("edge", "ggplot2", "reshape2")
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
    library(edge)
    
    # Helper function to robustly read user input files from the working directory
    read_input <- function(base_name, is_matrix = FALSE) {
      possible_files <- c(
        base_name,
        paste0(base_name, ".rds"),
        paste0(base_name, ".csv"),
        paste0(base_name, ".tsv"),
        paste0(base_name, ".txt")
      )
      
      for (f in possible_files) {
        if (file.exists(f)) {
          if (grepl("\\\\.rds\$", f)) {
            val <- readRDS(f)
            if (is_matrix) return(as.matrix(val))
            return(val)
          } else if (grepl("\\\\.csv\$", f)) {
            val <- read.csv(f, row.names = if (is_matrix) 1 else NULL, header = TRUE, check.names = FALSE)
            if (is_matrix) return(as.matrix(val))
            if (ncol(val) == 1) return(val[[1]])
            return(val)
          } else if (grepl("\\\\.tsv\$", f) || grepl("\\\\.txt\$", f)) {
            val <- read.delim(f, row.names = if (is_matrix) 1 else NULL, header = TRUE, check.names = FALSE)
            if (is_matrix) return(as.matrix(val))
            if (ncol(val) == 1) return(val[[1]])
            return(val)
          } else {
            # Try reading as RDS first, then as table
            try_rds <- try(readRDS(f), silent = TRUE)
            if (!inherits(try_rds, "try-error")) {
              if (is_matrix) return(as.matrix(try_rds))
              return(try_rds)
            }
            try_table <- try(read.table(f, header = TRUE, row.names = if (is_matrix) 1 else NULL, check.names = FALSE), silent = TRUE)
            if (!inherits(try_table, "try-error")) {
              if (is_matrix) return(as.matrix(try_table))
              if (ncol(try_table) == 1) return(try_table[[1]])
              return(try_table)
            }
            # Try reading as a simple vector
            if (!is_matrix) {
              try_scan <- try(scan(f, what = character(), quiet = TRUE), silent = TRUE)
              if (!inherits(try_scan, "try-error")) return(try_scan)
            }
          }
        }
      }
      stop(paste("Error: Required input file not found in the working directory:", base_name))
    }
    
    # Read the exact user input files
    gibexpr <- read_input("gibexpr", is_matrix = TRUE)
    gender  <- as.vector(read_input("gender", is_matrix = FALSE))
    batch   <- as.vector(read_input("batch", is_matrix = FALSE))
    location <- as.vector(read_input("location", is_matrix = FALSE))
    
    # --- BEGIN DOCUMENTED WORKFLOW ---
    
    # 1. Build the deSet object using build_study with sampling="static"
    de_obj <- build_study(data = gibexpr, adj.var = cbind(gender, batch), grp = location, sampling = "static")
    
    # 2. Fit the models using fit_models
    ef_obj <- fit_models(de_obj, stat.type="lrt")
    
    # 3. Perform significance testing using lrt and odp
    de_lrt <- lrt(de_obj, nullDistn="normal")
    de_odp <- odp(de_obj, bs.its = 50, verbose = FALSE, n.mods = 50)
    
    # Capture summary output
    summary_output <- capture.output(summary(de_odp))
    writeLines(summary_output, "de_odp_summary.txt")
    
    # 4. Extract p-values, q-values, local FDR, and pi0 using qvalueObj
    sig_results <- qvalueObj(de_odp)
    pvalues <- sig_results\$pvalues
    qvalues <- sig_results\$qvalues
    lfdr <- sig_results\$lfdr
    pi0 <- sig_results\$pi0
    
    # --- END DOCUMENTED WORKFLOW ---
    
    # Save meaningful results to output files
    
    # Save the main statistics table
    results_df <- data.frame(
      gene_id = rownames(gibexpr),
      pvalue  = pvalues,
      qvalue  = qvalues,
      local_fdr = lfdr,
      stringsAsFactors = FALSE
    )
    write.csv(results_df, "de_analysis_results.csv", row.names = FALSE)
    
    # Save the estimated proportion of true null hypotheses (pi0)
    writeLines(paste("pi0 =", pi0), "pi0_estimate.txt")
    
    # Save the generated R objects for downstream analysis
    saveRDS(de_obj, "de_obj.rds")
    saveRDS(ef_obj, "ef_obj.rds")
    saveRDS(de_lrt, "de_lrt.rds")
    saveRDS(de_odp, "de_odp.rds")
    saveRDS(sig_results, "sig_results.rds")
    
    # Generate and save the diagnostic p-value histogram plot
    pdf("pvalue_histogram.pdf", width = 8, height = 6)
    hist(sig_results)
    dev.off()

    writeLines(c(
        '"BIOC_EDGE_STATIC_DE_ANALYSIS":',
        paste0('    edge: ', as.character(packageVersion('edge')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_static_de_analysis.csv versions.yml
    """
}

workflow BIOC_EDGE_STATIC_DE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gibexpr, gender, batch, location ] ]

    main:
    BIOC_EDGE_STATIC_DE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_EDGE_STATIC_DE_ANALYSIS.out.tables
    plots    = BIOC_EDGE_STATIC_DE_ANALYSIS.out.plots
    objects  = BIOC_EDGE_STATIC_DE_ANALYSIS.out.objects
    versions = BIOC_EDGE_STATIC_DE_ANALYSIS.out.versions
}
