#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: onlineFDR — online_fdr_synchronous
// Control the False Discovery Rate (FDR) for a stream of sequentially arriving p-values under independent or dependent conditions.
// Input: sample.df
// Container: quay.io/biocontainers/bioconductor-onlinefdr:2.18.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: onlineFDR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read the sequential dataset from the working directory
//  * 2. [Input & Preparation] Set seed and run LOND algorithm for independent or
//  * 3. [Input & Preparation] Set seed and run LORD algorithm with different version
//  * 4. [Input & Preparation] Write outputs to files
//  * 5. [Input & Preparation] Generate visualization of adjusted significance thresholds

nextflow.enable.dsl = 2

process BIOC_ONLINEFDR_ONLINE_FDR_SYNCHRONOUS {
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
    .bm_deps <- c("onlineFDR")
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
    
    # Load required library
    library(onlineFDR)
    
    # --- Read the sequential dataset from the working directory ---
    if (file.exists("sample.df")) {
      sample.df <- tryCatch({
        read.csv("sample.df", stringsAsFactors = FALSE)
      }, error = function(e) {
        readRDS("sample.df")
      })
    } else if (file.exists("sample.df.csv")) {
      sample.df <- read.csv("sample.df.csv", stringsAsFactors = FALSE)
    } else if (file.exists("sample.df.rds")) {
      sample.df <- readRDS("sample.df.rds")
    } else {
      stop("Error: Required input file 'sample.df' (or sample.df.csv/rds) not found in the working directory.")
    }
    
    # Ensure date column is formatted correctly if present
    if ("date" %in% colnames(sample.df)) {
      sample.df\$date <- as.Date(sample.df\$date)
    }
    
    # --- Set seed and run LOND algorithm for independent or ---
    set.seed(1); results.indep <- LOND(sample.df)    # for independent p-values
    set.seed(1); results.dep <- LOND(sample.df, dep=TRUE)   # for dependent p-values
    
    # Compare adjusted significance thresholds for LOND
    lond_comparison <- cbind(independent = results.indep\$alphai, dependent = results.dep\$alphai)
    
    # --- Set seed and run LORD algorithm with different version ---
    set.seed(1); results.LORD.plus <- LORD(sample.df)
    set.seed(1); results.LORD3 <- LORD(sample.df, version=3)
    set.seed(1); results.LORD.discard <- LORD(sample.df, version='discard')
    set.seed(1); results.LORD.dep <- LORD(sample.df, version='dep') 
    
    # Compare adjusted significance thresholds for LORD
    lord_comparison <- cbind(LORD.plus = results.LORD.plus\$alphai,
                             LORD3 = results.LORD3\$alphai,
                             LORD.discard  = results.LORD.discard\$alphai,
                             LORD.dep = results.LORD.dep\$alphai)
    
    # --- Write outputs to files ---
    write.csv(results.indep, "results_lond_indep.csv", row.names = FALSE)
    write.csv(results.dep, "results_lond_dep.csv", row.names = FALSE)
    write.csv(results.LORD.plus, "results_lord_plus.csv", row.names = FALSE)
    write.csv(results.LORD3, "results_lord3.csv", row.names = FALSE)
    write.csv(results.LORD.discard, "results_lord_discard.csv", row.names = FALSE)
    write.csv(results.LORD.dep, "results_lord_dep.csv", row.names = FALSE)
    
    write.csv(lond_comparison, "lond_threshold_comparison.csv", row.names = FALSE)
    write.csv(lord_comparison, "lord_threshold_comparison.csv", row.names = FALSE)
    
    # Save RDS objects for downstream analysis
    saveRDS(results.indep, "results_lond_indep.rds")
    saveRDS(results.dep, "results_lond_dep.rds")
    saveRDS(results.LORD.plus, "results_lord_plus.rds")
    saveRDS(results.LORD3, "results_lord3.rds")
    saveRDS(results.LORD.discard, "results_lord_discard.rds")
    saveRDS(results.LORD.dep, "results_lord_dep.rds")
    
    # --- Generate visualization of adjusted significance thresholds ---
    pdf("threshold_comparison_plot.pdf", width = 8, height = 6)
    x <- seq_len(nrow(sample.df))
    plot(x, log(results.indep\$alphai), ylim = c(-15, -1), type = 'l', col = "green",
         xlab = "Index", ylab = "log(alphai)", main = "Adjusted Significance Thresholds (log scale)",
         panel.first = grid())
    lines(x, log(results.dep\$alphai), col = "darkgreen", lty = 2)
    lines(x, log(results.LORD.plus\$alphai), col = "blue")
    lines(x, log(results.LORD3\$alphai), col = "cyan")
    lines(x, log(results.LORD.discard\$alphai), col = "orange")
    lines(x, log(results.LORD.dep\$alphai), col = "red")
    legend("bottomleft", legend = c("LOND Indep", "LOND Dep", "LORD++", "LORD3", "LORD Discard", "LORD Dep"),
           col = c("green", "darkgreen", "blue", "cyan", "orange", "red"),
           lty = c(1, 2, 1, 1, 1, 1), cex = 0.8)
    dev.off()

    writeLines(c(
        '"BIOC_ONLINEFDR_ONLINE_FDR_SYNCHRONOUS":',
        paste0('    onlineFDR: ', as.character(packageVersion('onlineFDR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_online_fdr_synchronous.csv versions.yml
    """
}

workflow BIOC_ONLINEFDR_ONLINE_FDR_SYNCHRONOUS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample.df ] ]

    main:
    BIOC_ONLINEFDR_ONLINE_FDR_SYNCHRONOUS(ch_input)

    emit:
    tables   = BIOC_ONLINEFDR_ONLINE_FDR_SYNCHRONOUS.out.tables
    plots    = BIOC_ONLINEFDR_ONLINE_FDR_SYNCHRONOUS.out.plots
    objects  = BIOC_ONLINEFDR_ONLINE_FDR_SYNCHRONOUS.out.objects
    versions = BIOC_ONLINEFDR_ONLINE_FDR_SYNCHRONOUS.out.versions
}
