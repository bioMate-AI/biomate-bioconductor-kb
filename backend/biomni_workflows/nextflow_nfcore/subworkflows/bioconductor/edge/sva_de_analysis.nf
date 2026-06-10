#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: edge — sva_de_analysis
// Perform differential expression analysis while identifying and adjusting for surrogate variables (unknown sources of variation or batch effects) using SVA.
// Input: kidexpr, sex, age
// Container: quay.io/biocontainers/bioconductor-edge:2.42.0--r45h01b2380_0
// R packages: edge
// Bioconductor: 3.20 | R: 4.4
// Requires: edge
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Build the initial deSet object using build_models
//  * 2. [Core Analysis] Apply surrogate variable analysis using apply_sva to estimate surrogate variables and update the models
//  * 3. [Core Analysis] Perform significance testing on the SVA-adjusted object using odp or lrt
//  * 4. [Core Analysis] Extract significance statistics using qvalueObj

nextflow.enable.dsl = 2

process BIOC_EDGE_SVA_DE_ANALYSIS {
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
    .bm_deps <- c("edge")
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
    library(splines)
    
    # Helper function to robustly load user input files
    load_file <- function(base_name) {
      extensions <- c("", ".rds", ".csv", ".tsv", ".txt")
      for (ext in extensions) {
        file_path <- paste0(base_name, ext)
        if (file.exists(file_path)) {
          if (grepl("\\\\.rds\$", file_path, ignore.case = TRUE)) {
            return(readRDS(file_path))
          } else if (grepl("\\\\.csv\$", file_path, ignore.case = TRUE)) {
            df <- read.csv(file_path, header = TRUE, row.names = 1, check.names = FALSE)
            if (ncol(df) == 0) {
              df <- read.csv(file_path, header = FALSE)
            }
            if (ncol(df) == 1) {
              return(df[[1]])
            }
            return(as.matrix(df))
          } else if (grepl("\\\\.(tsv|txt)\$", file_path, ignore.case = TRUE)) {
            df <- read.delim(file_path, header = TRUE, row.names = 1, check.names = FALSE)
            if (ncol(df) == 0) {
              df <- read.delim(file_path, header = FALSE)
            }
            if (ncol(df) == 1) {
              return(df[[1]])
            }
            return(as.matrix(df))
          } else {
            # No extension, try reading as RDS first, then CSV
            try_rds <- try(readRDS(file_path), silent = TRUE)
            if (!inherits(try_rds, "try-error")) return(try_rds)
            try_csv <- try(read.csv(file_path, header = TRUE, row.names = 1, check.names = FALSE), silent = TRUE)
            if (!inherits(try_csv, "try-error")) {
              if (ncol(try_csv) == 1) return(try_csv[[1]])
              return(as.matrix(try_csv))
            }
          }
        }
      }
      stop(paste("Error: Could not find or read file for", base_name))
    }
    
    # Read user input files from the working directory
    kidexpr <- load_file("kidexpr")
    if (!is.matrix(kidexpr)) {
      kidexpr <- as.matrix(kidexpr)
    }
    
    sex <- load_file("sex")
    if (is.list(sex) || is.data.frame(sex)) {
      sex <- sex[[1]]
    }
    
    age <- load_file("age")
    if (is.list(age) || is.data.frame(age)) {
      age <- age[[1]]
    }
    
    # --- ADAPTED DOCUMENTED CODE ---
    cov <- data.frame(sex = sex, age = age)
    null_model <- ~sex
    full_model <- ~sex + ns(age, df=4)
    de_obj <- build_models(data = kidexpr, cov = cov, full.model = full_model, null.model = null_model)
    de_sva <- apply_sva(de_obj, n.sv = 3, B = 10)
    de_odp <- odp(de_sva, bs.its = 50, verbose = FALSE)
    de_lrt <- lrt(de_sva, verbose = FALSE)
    qval_obj <- qvalueObj(de_odp)
    qvals <- qval_obj\$qvalues
    lfdr <- qval_obj\$lfdr
    pvals <- qval_obj\$pvalues
    pi0 <- qval_obj\$pi0
    # --- END OF ADAPTED DOCUMENTED CODE ---
    
    # Prepare and write outputs
    gene_names <- rownames(kidexpr)
    if (is.null(gene_names)) {
      gene_names <- paste0("Gene_", seq_len(nrow(kidexpr)))
    }
    
    results_df <- data.frame(
      gene_id = gene_names,
      pvalue = pvals,
      qvalue = qvals,
      local_fdr = lfdr,
      stringsAsFactors = FALSE
    )
    
    # Write CSV results table
    write.csv(results_df, "sva_de_results.csv", row.names = FALSE)
    
    # Write RDS objects for downstream analysis
    saveRDS(qval_obj, "qval_obj.rds")
    saveRDS(de_sva, "de_sva.rds")
    saveRDS(de_odp, "de_odp.rds")
    saveRDS(de_lrt, "de_lrt.rds")
    
    # Save a summary text file
    summary_stats <- capture.output(summary(de_odp))
    writeLines(c(
      paste("Estimated proportion of null genes (pi0):", pi0),
      "",
      summary_stats
    ), "sva_de_summary.txt")
    
    # Save diagnostic plots
    pdf("pvalue_histogram.pdf", width = 7, height = 5)
    hist(qval_obj)
    dev.off()

    writeLines(c(
        '"BIOC_EDGE_SVA_DE_ANALYSIS":',
        paste0('    edge: ', as.character(packageVersion('edge')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sva_de_analysis.csv versions.yml
    """
}

workflow BIOC_EDGE_SVA_DE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ kidexpr, sex, age ] ]

    main:
    BIOC_EDGE_SVA_DE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_EDGE_SVA_DE_ANALYSIS.out.tables
    plots    = BIOC_EDGE_SVA_DE_ANALYSIS.out.plots
    objects  = BIOC_EDGE_SVA_DE_ANALYSIS.out.objects
    versions = BIOC_EDGE_SVA_DE_ANALYSIS.out.versions
}
