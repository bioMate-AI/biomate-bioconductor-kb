#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: iChip — ichip2_second_order_ising
// Identify enriched genomic regions in ChIP-chip data using a second-order hidden Ising model with a fixed interaction parameter (beta).
// Input: chip_data.txt
// Container: quay.io/biocontainers/bioconductor-ichip:1.64.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: iChip
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read the user input file
//  * 2. [Input & Preparation] Calculate enrichment measurements (limma t-statistics)
//  * 3. [Input & Preparation] Prepare the input matrix Y by combining chromosome and
//  * 4. [Input & Preparation] Run the second-order Ising model using iChip2
//  * 5. [Input & Preparation] Call enriched regions using enrichreg with posterior

nextflow.enable.dsl = 2

process BIOC_ICHIP_ICHIP2_SECOND_ORDER_ISING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("iChip")
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
    library(iChip)
    
    # --- Read the user input file ---
    # The file 'chip_data.txt' is expected to be a tab-delimited file containing:
    # Column 1: Chromosome
    # Column 2: Genomic Position
    # Columns 3-4: Control replicates (normalized intensities)
    # Columns 5-6: IP replicates (normalized intensities)
    if (!file.exists("chip_data.txt")) {
      stop("Error: 'chip_data.txt' not found in the working directory.")
    }
    
    oct4 <- read.table("chip_data.txt", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
    
    # Sort the data by chromosome and genomic position
    oct4 <- oct4[order(oct4[, 1], oct4[, 2]), ]
    
    # --- Calculate enrichment measurements (limma t-statistics) ---
    # Columns 5:6 are IP replicates, columns 3:4 are Control replicates
    oct4lmt <- lmtstat(oct4[, 5:6], oct4[, 3:4])
    
    # --- Prepare the input matrix Y by combining chromosome and ---
    oct4Y <- cbind(oct4[, 1], oct4lmt)
    
    # --- Run the second-order Ising model using iChip2 ---
    set.seed(777)
    oct4res2 <- iChip2(Y = oct4Y, burnin = 2000, sampling = 10000, winsize = 2,
                       sdcut = 2, beta = 1.25, verbose = FALSE)
    
    # Save the raw model results as an RDS object
    saveRDS(oct4res2, file = "ichip2_results.rds")
    
    # --- Call enriched regions using enrichreg with posterior ---
    # Method 1: Posterior probability cutoff (ppcut)
    reg1 <- enrichreg(pos = oct4[, 1:2], enrich = oct4lmt, pp = oct4res2\$pp,
                      cutoff = 0.9, method = "ppcut", maxgap = 500)
    
    # Method 2: False Discovery Rate cutoff (fdrcut)
    reg2 <- enrichreg(pos = oct4[, 1:2], enrich = oct4lmt, pp = oct4res2\$pp,
                      cutoff = 0.01, method = "fdrcut", maxgap = 500)
    
    # Write the identified enriched regions to CSV files
    write.csv(reg1, file = "enriched_regions_pp0.9.csv", row.names = FALSE)
    write.csv(reg2, file = "enriched_regions_fdr0.01.csv", row.names = FALSE)
    
    # Create and save BED files for downstream visualization (e.g., UCSC Genome Browser)
    if (!is.null(reg2) && nrow(reg2) > 0) {
      bed1 <- data.frame(chr = paste("chr", reg2[, 1], sep = ""), reg2[, 2:3])
      write.table(bed1, file = "enriched_regions_fdr0.01.bed", sep = "\t", 
                  row.names = FALSE, col.names = FALSE, quote = FALSE)
      
      bed2 <- data.frame(chr = paste("chr", reg2[, 1], sep = ""), 
                         gstart = reg2[, 6] - 100,
                         gend = reg2[, 6] + 100)
      write.table(bed2, file = "enriched_peaks_fdr0.01.bed", sep = "\t", 
                  row.names = FALSE, col.names = FALSE, quote = FALSE)
    }
    
    # Generate diagnostic plots to assess MCMC convergence
    pdf("ichip2_mcmc_diagnostics.pdf", width = 8, height = 8)
    par(mfrow = c(2, 2), mar = c(4.1, 4.1, 2.0, 1.0))
    plot(oct4res2\$mu0, pch = ".", xlab = "Iterations", ylab = "mu0", main = "mu0 Trace")
    plot(oct4res2\$lambda0, pch = ".", xlab = "Iterations", ylab = "lambda0", main = "lambda0 Trace")
    plot(oct4res2\$mu1, pch = ".", xlab = "Iterations", ylab = "mu1", main = "mu1 Trace")
    plot(oct4res2\$lambda1, pch = ".", xlab = "Iterations", ylab = "lambda1", main = "lambda1 Trace")
    dev.off()
    
    # Generate posterior probability histogram
    pdf("ichip2_pp_histogram.pdf", width = 6, height = 6)
    hist(oct4res2\$pp, xlab = "Posterior Probability", main = "Histogram of Posterior Probabilities")
    dev.off()

    writeLines(c(
        '"BIOC_ICHIP_ICHIP2_SECOND_ORDER_ISING":',
        paste0('    iChip: ', as.character(packageVersion('iChip')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ichip2_second_order_ising.csv versions.yml
    """
}

workflow BIOC_ICHIP_ICHIP2_SECOND_ORDER_ISING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ chip_data.txt ] ]

    main:
    BIOC_ICHIP_ICHIP2_SECOND_ORDER_ISING(ch_input)

    emit:
    tables   = BIOC_ICHIP_ICHIP2_SECOND_ORDER_ISING.out.tables
    plots    = BIOC_ICHIP_ICHIP2_SECOND_ORDER_ISING.out.plots
    objects  = BIOC_ICHIP_ICHIP2_SECOND_ORDER_ISING.out.objects
    versions = BIOC_ICHIP_ICHIP2_SECOND_ORDER_ISING.out.versions
}
