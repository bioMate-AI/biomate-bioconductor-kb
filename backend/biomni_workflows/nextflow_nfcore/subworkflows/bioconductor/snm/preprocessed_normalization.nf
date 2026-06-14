#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: snm — preprocessed_normalization
// Normalize preprocessed microarray data (e.g., RMA processed) where intensity-dependent effects have already been removed, but probe-specific adjustment variable
// Input: raw.data, bio.var, adj.var
// Container: quay.io/biocontainers/bioconductor-snm:1.58.0--r45hdfd78af_0
// R packages: snm
// Bioconductor: 3.20 | R: 4.4
// Requires: snm
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run the snm function with rm.adj=TRUE to remove
//  * 2. [Core Analysis] Perform the Kolmogorov-Smirnov test on the null p-values

nextflow.enable.dsl = 2

process BIOC_SNM_PREPROCESSED_NORMALIZATION {
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
    .bm_deps <- c("snm")
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
    library(snm)
    
    # Helper function to load input files robustly
    load_input <- function(base_name) {
      extensions <- c("", ".rds", ".csv", ".tsv", ".txt")
      for (ext in extensions) {
        file_path <- paste0(base_name, ext)
        if (file.exists(file_path)) {
          # Try reading as RDS
          res <- tryCatch(readRDS(file_path), error = function(e) NULL)
          if (!is.null(res)) return(res)
          
          # Try reading as CSV
          res <- tryCatch({
            df <- read.csv(file_path, row.names = 1, check.names = FALSE)
            as.matrix(df)
          }, error = function(e) NULL)
          if (!is.null(res)) return(res)
          
          # Try reading as TSV
          res <- tryCatch({
            df <- read.table(file_path, header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
            as.matrix(df)
          }, error = function(e) NULL)
          if (!is.null(res)) return(res)
        }
      }
      stop(paste("Error: Required input file for", base_name, "not found or could not be read."))
    }
    
    # Construct the preProcessed list from user input files
    preProcessed <- list()
    preProcessed\$raw.data <- load_input("raw.data")
    preProcessed\$bio.var  <- load_input("bio.var")
    preProcessed\$adj.var  <- load_input("adj.var")
    
    # Attempt to load true.nulls if available, otherwise default to all probes
    preProcessed\$true.nulls <- tryCatch({
      load_input("true.nulls")
    }, error = function(e) {
      # Fallback: assume all probes are nulls if not specified
      seq_len(nrow(preProcessed\$raw.data))
    })
    
    # --- Run the snm function with rm.adj=TRUE to remove ---
    # from the preprocessed data without fitting intensity-dependent effects
    snm.obj5 <- snm(preProcessed\$raw.data,
                                preProcessed\$bio.var,
                                preProcessed\$adj.var, rm.adj=TRUE)
    
    # --- Perform the Kolmogorov-Smirnov test on the null p-values ---
    ks_res <- ks.test(snm.obj5\$pval[preProcessed\$true.nulls],"punif")
    
    # Write meaningful results to output files
    # Save normalized data
    write.csv(snm.obj5\$norm.dat, file = "normalized_data.csv", row.names = TRUE)
    saveRDS(snm.obj5\$norm.dat, file = "normalized_data.rds")
    
    # Save p-values
    probe_ids <- rownames(preProcessed\$raw.data)
    if (is.null(probe_ids)) {
      probe_ids <- paste0("Probe_", seq_len(nrow(preProcessed\$raw.data)))
    }
    pvals_df <- data.frame(probe_id = probe_ids, pvalue = snm.obj5\$pval)
    write.csv(pvals_df, file = "pvalues.csv", row.names = FALSE)
    
    # Save the entire snm object
    saveRDS(snm.obj5, file = "snm_output.rds")
    
    # Save KS-test results
    sink("ks_test_results.txt")
    print(ks_res)
    sink()
    
    # Save diagnostic plots
    pdf("diagnostic_plots.pdf")
    plot(snm.obj5)
    dev.off()

    writeLines(c(
        '"BIOC_SNM_PREPROCESSED_NORMALIZATION":',
        paste0('    snm: ', as.character(packageVersion('snm')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_preprocessed_normalization.csv versions.yml
    """
}

workflow BIOC_SNM_PREPROCESSED_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw.data, bio.var, adj.var ] ]

    main:
    BIOC_SNM_PREPROCESSED_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_SNM_PREPROCESSED_NORMALIZATION.out.tables
    plots    = BIOC_SNM_PREPROCESSED_NORMALIZATION.out.plots
    objects  = BIOC_SNM_PREPROCESSED_NORMALIZATION.out.objects
    versions = BIOC_SNM_PREPROCESSED_NORMALIZATION.out.versions
}
