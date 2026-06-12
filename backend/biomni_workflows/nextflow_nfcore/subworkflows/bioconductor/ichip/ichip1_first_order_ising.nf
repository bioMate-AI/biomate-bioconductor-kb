#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: iChip — ichip1_first_order_ising
// Identify enriched genomic regions in ChIP-chip data using a first-order hidden Ising model where the interaction parameter (beta) is dynamically sampled.
// Input: chip_data.txt
// Container: quay.io/biocontainers/bioconductor-ichip:1.64.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: iChip
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read the user input file
//  * 2. [Core Analysis] Sort the data by chromosome and genomic position
//  * 3. [Core Analysis] Calculate enrichment measurements (limma t-statistics)
//  * 4. [Core Analysis] Run the first-order Ising model using iChip1
//  * 5. [Core Analysis] Call enriched regions using enrichreg with posterior
//  * 6. [Core Analysis] Write named output files for the meaningful results

nextflow.enable.dsl = 2

process BIOC_ICHIP_ICHIP1_FIRST_ORDER_ISING {
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
    # The file must be tab-delimited and contain chromosome, genomic position, and normalized intensity columns.
    chip_data <- read.table("chip_data.txt", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
    
    # --- Sort the data by chromosome and genomic position ---
    oct4 <- chip_data[order(chip_data[, 1], chip_data[, 2]), ]
    
    # Identify IP and Control columns dynamically or fallback to standard columns
    # Standard Agilent/Affy setup: columns 3:4 are Control (green), columns 5:6 are IP (red)
    ip_cols <- grep("ip|red", colnames(oct4), ignore.case = TRUE)
    control_cols <- grep("control|con|green", colnames(oct4), ignore.case = TRUE)
    
    if (length(ip_cols) >= 2 && length(control_cols) >= 2) {
      ip_data <- oct4[, ip_cols[1:2]]
      control_data <- oct4[, control_cols[1:2]]
    } else {
      # Fallback to the column indices from the documented vignette
      ip_data <- oct4[, 5:6]
      control_data <- oct4[, 3:4]
    }
    
    # --- Calculate enrichment measurements (limma t-statistics) ---
    oct4lmt <- lmtstat(ip_data, control_data)
    
    # --- Run the first-order Ising model using iChip1 ---
    oct4res1 <- iChip1(enrich=oct4lmt, burnin=2000, sampling=10000, sdcut=2, beta0=3,
                       minbeta=0, maxbeta=10, normsd=0.1, verbose=FALSE)
    
    # --- Call enriched regions using enrichreg with posterior ---
    reg_pp <- enrichreg(pos=oct4[, 1:2], enrich=oct4lmt, pp=oct4res1\$pp, cutoff=0.9,
                        method="ppcut", maxgap=500)
    
    reg_fdr <- enrichreg(pos=oct4[, 1:2], enrich=oct4lmt, pp=oct4res1\$pp, cutoff=0.01,
                         method="fdrcut", maxgap=500)
    
    # --- Write named output files for the meaningful results ---
    # Save the called enriched regions as CSV tables
    write.csv(reg_pp, file = "enriched_regions_ppcut.csv", row.names = FALSE)
    write.csv(reg_fdr, file = "enriched_regions_fdrcut.csv", row.names = FALSE)
    
    # Save the full MCMC results and enrichment statistics as an RDS object
    saveRDS(list(mcmc_results = oct4res1, enrichment_stats = oct4lmt), file = "ichip1_results.rds")
    
    # Save diagnostic plots of the model parameters to a PDF
    pdf("ichip1_parameter_plots.pdf", width = 8, height = 8)
    par(mfrow = c(2, 2), mar = c(4.1, 4.1, 2.0, 1.0))
    plot(oct4res1\$beta, pch = ".", xlab = "Iterations", ylab = "beta", main = "Beta Parameter")
    plot(oct4res1\$mu0, pch = ".", xlab = "Iterations", ylab = "mu0", main = "Mu0 Parameter")
    plot(oct4res1\$mu1, pch = ".", xlab = "Iterations", ylab = "mu1", main = "Mu1 Parameter")
    plot(oct4res1\$lambda, pch = ".", xlab = "Iterations", ylab = "lambda", main = "Lambda Parameter")
    dev.off()

    writeLines(c(
        '"BIOC_ICHIP_ICHIP1_FIRST_ORDER_ISING":',
        paste0('    iChip: ', as.character(packageVersion('iChip')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ichip1_first_order_ising.csv versions.yml
    """
}

workflow BIOC_ICHIP_ICHIP1_FIRST_ORDER_ISING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ chip_data.txt ] ]

    main:
    BIOC_ICHIP_ICHIP1_FIRST_ORDER_ISING(ch_input)

    emit:
    tables   = BIOC_ICHIP_ICHIP1_FIRST_ORDER_ISING.out.tables
    plots    = BIOC_ICHIP_ICHIP1_FIRST_ORDER_ISING.out.plots
    objects  = BIOC_ICHIP_ICHIP1_FIRST_ORDER_ISING.out.objects
    versions = BIOC_ICHIP_ICHIP1_FIRST_ORDER_ISING.out.versions
}
