#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: NormqPCR — normalized_relative_quantities
// Compute normalized relative quantities (NRQs) using amplification efficiencies and reference genes.
// Input: qPCR.example.txt, Efficiencies.txt
// Container: quay.io/biocontainers/bioconductor-normqpcr:1.56.0--r45h575d39b_0
// R packages: NormqPCR, ReadqPCR
// Bioconductor: 3.20 | R: 4.4
// Requires: NormqPCR, ReadqPCR
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read raw qPCR data using read.qPCR
//  * 2. [Core Analysis] Combine technical replicates and compute standard deviations using combineTechRepsWithSD
//  * 3. [Input & Preparation] Load amplification efficiencies and assign them to the qPCRBatch object
//  * 4. [Core Analysis] Compute normalized relative quantities and their standard errors using ComputeNRQs

nextflow.enable.dsl = 2

process BIOC_NORMQPCR_NORMALIZED_RELATIVE_QUANTITIES {
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
    .bm_deps <- c("NormqPCR", "ReadqPCR")
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
    library(ReadqPCR)
    library(NormqPCR)
    
    # Define input file paths (must be in the working directory)
    qpcr_input <- "qPCR.example.txt"
    efficiencies_input <- "Efficiencies.txt"
    
    # Check if input files exist
    if (!file.exists(qpcr_input)) {
      stop(paste("Required input file missing:", qpcr_input))
    }
    if (!file.exists(efficiencies_input)) {
      stop(paste("Required input file missing:", efficiencies_input))
    }
    
    # 1. Read raw qPCR data using read.qPCR
    message("Reading raw qPCR data...")
    Cq.data <- read.qPCR(qpcr_input)
    
    # 2. Combine technical replicates and compute standard deviations
    message("Combining technical replicates...")
    Cq.data1 <- combineTechRepsWithSD(Cq.data)
    
    # 3. Load amplification efficiencies and assign them to the qPCRBatch object
    message("Loading amplification efficiencies...")
    Cq.effs <- read.table(file = efficiencies_input, row.names = 1, header = TRUE)
    
    # Match the row order of efficiencies to the feature names of the combined data
    features <- featureNames(Cq.data1)
    if (!all(features %in% rownames(Cq.effs))) {
      stop("Some features in the qPCR data are missing from the efficiencies file.")
    }
    Cq.effs <- Cq.effs[features, , drop = FALSE]
    
    # Assign efficiencies and their standard errors
    effs(Cq.data1) <- as.matrix(Cq.effs[, "efficiency", drop = FALSE])
    se.effs(Cq.data1) <- as.matrix(Cq.effs[, "SD.efficiency", drop = FALSE])
    
    # 4. Compute normalized relative quantities (NRQs) using reference genes
    message("Computing Normalized Relative Quantities (NRQs)...")
    # Use the first two features as default reference genes to avoid hardcoding specific names
    hkgs <- head(featureNames(Cq.data1), 2)
    res <- ComputeNRQs(Cq.data1, hkgs = hkgs)
    
    # 5. Export results
    message("Exporting results...")
    
    # Save the complete result object as RDS
    saveRDS(res, file = "nrq_results.rds")
    
    # Extract and save NRQ values
    nrq_values <- exprs(res)
    write.csv(nrq_values, file = "nrq_values.csv", row.names = TRUE)
    
    # Extract and save Standard Errors of NRQs
    nrq_se <- se.exprs(res)
    write.csv(nrq_se, file = "nrq_standard_errors.csv", row.names = TRUE)
    
    # Generate a summary plot of the NRQs and save as PDF
    pdf("nrq_barplot.pdf", width = 10, height = 7)
    par(mar = c(7, 5, 4, 2) + 0.1)
    barplot(
      nrq_values, 
      beside = TRUE, 
      las = 2,
      col = rainbow(nrow(nrq_values)),
      main = "Normalized Relative Quantities (NRQs) per Sample",
      ylab = "NRQ Value",
      legend.text = rownames(nrq_values),
      args.legend = list(x = "topright", bty = "n", cex = 0.7)
    )
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to 'nrq_results.rds', 'nrq_values.csv', 'nrq_standard_errors.csv', and 'nrq_barplot.pdf'.")

    writeLines(c(
        '"BIOC_NORMQPCR_NORMALIZED_RELATIVE_QUANTITIES":',
        paste0('    NormqPCR: ', as.character(packageVersion('NormqPCR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_normalized_relative_quantities.csv versions.yml
    """
}

workflow BIOC_NORMQPCR_NORMALIZED_RELATIVE_QUANTITIES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ qPCR.example.txt, Efficiencies.txt ] ]

    main:
    BIOC_NORMQPCR_NORMALIZED_RELATIVE_QUANTITIES(ch_input)

    emit:
    tables   = BIOC_NORMQPCR_NORMALIZED_RELATIVE_QUANTITIES.out.tables
    plots    = BIOC_NORMQPCR_NORMALIZED_RELATIVE_QUANTITIES.out.plots
    objects  = BIOC_NORMQPCR_NORMALIZED_RELATIVE_QUANTITIES.out.objects
    versions = BIOC_NORMQPCR_NORMALIZED_RELATIVE_QUANTITIES.out.versions
}
