#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: lfa — logistic_factor_analysis
// Estimate genetic population structure and compute individual-specific allele frequencies from SNP genotype data.
// Input: genotypes.bed, genotypes.bim, genotypes.fam
// Container: quay.io/biocontainers/bioconductor-lfa:2.10.0--r45h01b2380_0
// R packages: genio, ggplot2, lfa
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LFA_LOGISTIC_FACTOR_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-lfa:2.10.0--r45h01b2380_0"

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
    .bm_deps <- c("genio", "ggplot2", "lfa")
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
    
    # Load required libraries
    library(lfa)
    library(genio)
    library(ggplot2)
    
    # --- Read the PLINK files from the working directory ---
    # genio::read_plink expects the prefix of the files (genotypes.bed, genotypes.bim, genotypes.fam)
    plink_data <- genio::read_plink("genotypes")
    hgdp_subset <- as.matrix(plink_data\$X)
    
    # --- Estimate logistic factors using lfa ---
    LF <- lfa(hgdp_subset, 4)
    
    # Save logistic factors to a CSV file
    write.csv(LF, "logistic_factors.csv", row.names = FALSE)
    
    # Plot the first two logistic factors and save as PDF
    geo_info <- if (!is.null(plink_data\$fam) && !is.null(plink_data\$fam\$fam)) {
        plink_data\$fam\$fam
    } else {
        "Individual"
    }
    
    dat <- data.frame(LF[, 1], LF[, 2], geo_info)
    colnames(dat) <- c("LF1", "LF2", "geo")
    
    p <- ggplot(dat, aes(LF1, LF2, color = geo)) + 
        geom_point() + 
        theme_bw() +
        coord_fixed(ratio = (max(dat[, 1]) - min(dat[, 1])) / (max(dat[, 2]) - min(dat[, 2])))
    
    ggsave("logistic_factors_plot.pdf", plot = p, width = 6, height = 5)
    
    # --- Compute individual-specific allele frequencies using af ---
    allele_freqs <- af(hgdp_subset, LF)
    saveRDS(allele_freqs, "allele_frequencies.rds")
    
    # Compute subset of allele frequencies as documented
    subset <- af(hgdp_subset[15:25, ], LF)
    saveRDS(subset, "allele_frequencies_subset.rds")
    
    # --- Compute log-likelihood for each SNP ---
    ll <- function(snp, af) {
        -sum(snp * log(af) + (2 - snp) * log(1 - af))
    }
    
    log_lik <- sapply(1:nrow(hgdp_subset), function(i) {
        ll(hgdp_subset[i, ], allele_freqs[i, ])
    })
    
    # Save log-likelihoods to a CSV file
    log_lik_df <- data.frame(
        SNP = rownames(hgdp_subset),
        LogLikelihood = log_lik
    )
    write.csv(log_lik_df, "snp_log_likelihoods.csv", row.names = FALSE)
    
    # Find the SNP with the maximum log-likelihood and save the index
    max_log_lik_index <- which(max(log_lik) == log_lik)
    writeLines(as.character(max_log_lik_index), "max_log_lik_index.txt")

    writeLines(c(
        '"BIOC_LFA_LOGISTIC_FACTOR_ANALYSIS":',
        paste0('        lfa: ', as.character(packageVersion("lfa")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_logistic_factor_analysis.csv versions.yml
    """
}

workflow BIOC_LFA_LOGISTIC_FACTOR_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genotypes.bed, genotypes.bim, genotypes.fam ] ]

    main:
    BIOC_LFA_LOGISTIC_FACTOR_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_LFA_LOGISTIC_FACTOR_ANALYSIS.out.tables
    plots    = BIOC_LFA_LOGISTIC_FACTOR_ANALYSIS.out.plots
    objects  = BIOC_LFA_LOGISTIC_FACTOR_ANALYSIS.out.objects
    versions = BIOC_LFA_LOGISTIC_FACTOR_ANALYSIS.out.versions
}
