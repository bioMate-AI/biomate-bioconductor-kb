#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: snpstats — fst_calculation
// Calculate Wright's Fst coefficient to measure population differentiation across strata.
// Input: snps.10, subject.support$stratum
// Container: quay.io/biocontainers/bioconductor-snpstats:1.60.0--r45h01b2380_0
// R packages: snpStats
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SNPSTATS_FST_CALCULATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-snpstats:1.60.0--r45h01b2380_0"

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
    .bm_deps <- c("snpStats")
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
    library(snpStats)
    
    # Read user input files from the working directory
    # snps.10 is expected to be a SnpMatrix object saved as an RDS file
    # subject.support is expected to be a data frame containing the 'stratum' factor vector, saved as an RDS file
    snps.10 <- readRDS("snps.10.rds")
    subject.support <- readRDS("subject.support.rds")
    
    # --- Calculate pairwise Fst ---
    f1 <- Fst(snps.10, subject.support\$stratum, pairwise=TRUE)
    mean_f1 <- weighted.mean(f1\$Fst, f1\$weight)
    
    # --- Calculate overall Fst ---
    f2 <- Fst(snps.10, subject.support\$stratum, pairwise=FALSE)
    mean_f2 <- weighted.mean(f2\$Fst, f2\$weight)
    
    # Save meaningful results to output files
    saveRDS(f1, "fst_pairwise.rds")
    saveRDS(f2, "fst_overall.rds")
    
    # Create a summary table of the weighted mean Fst values
    summary_df <- data.frame(
      Analysis = c("Pairwise", "Overall"),
      Weighted_Mean_Fst = c(mean_f1, mean_f2)
    )
    write.csv(summary_df, "fst_summary.csv", row.names = FALSE)
    
    # Save a plot of the overall Fst values across SNPs
    pdf("fst_overall_plot.pdf", width = 7, height = 5)
    plot(f2\$Fst, 
         main = "Overall Fst per SNP", 
         xlab = "SNP Index", 
         ylab = "Fst", 
         col = "steelblue", 
         pch = 20)
    abline(h = mean_f2, col = "red", lty = 2, lwd = 2)
    legend("topright", 
           legend = paste("Weighted Mean Fst =", round(mean_f2, 5)), 
           col = "red", 
           lty = 2, 
           lwd = 2)
    dev.off()
    
    # Print summary to console
    cat("Fst Calculation Completed Successfully.\n")
    cat("Pairwise Weighted Mean Fst:", mean_f1, "\n")
    cat("Overall Weighted Mean Fst:", mean_f2, "\n")

    writeLines(c(
        '"BIOC_SNPSTATS_FST_CALCULATION":',
        paste0('        snpstats: ', as.character(packageVersion("snpstats")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fst_calculation.csv versions.yml
    """
}

workflow BIOC_SNPSTATS_FST_CALCULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ snps.10, subject.support$stratum ] ]

    main:
    BIOC_SNPSTATS_FST_CALCULATION(ch_input)

    emit:
    tables   = BIOC_SNPSTATS_FST_CALCULATION.out.tables
    plots    = BIOC_SNPSTATS_FST_CALCULATION.out.plots
    objects  = BIOC_SNPSTATS_FST_CALCULATION.out.objects
    versions = BIOC_SNPSTATS_FST_CALCULATION.out.versions
}
