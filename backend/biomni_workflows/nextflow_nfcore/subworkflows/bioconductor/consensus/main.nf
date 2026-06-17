#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: consensus — cross_platform_consensus_analysis
// Fit row-linear models to cross-platform genomic measurements to compare platform sensitivity, precision, and dynamic range, and identify highly discordant featu
// Input: matrix1.csv, matrix2.csv, matrix3.csv
// Container: quay.io/biocontainers/bioconductor-consensus:1.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RColorBrewer, consensus
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and data
//  * 2. [Input & Preparation] Construct a MultiMeasure object using MultiMeasure()
//  * 3. [Visualization & Output] Visualize a single gene fit using plotOneFit()
//  * 4. [Core Analysis] Fit the consensus model using fitConsensus()
//  * 5. [Visualization & Output] Plot marginal distributions of average, sensitivity, and precision using plotMarginals()
//  * 6. [Visualization & Output] Identify and plot the most discordant genes using plotMostDiscordant()

nextflow.enable.dsl = 2

process BIOC_CONSENSUS_CROSS_PLATFORM_CONSENSUS_ANALYSIS {
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
    .bm_deps <- c("consensus", "RColorBrewer")
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
    library(consensus)
    library(RColorBrewer)
    
    # 1. Load the data from user-specified files
    matrix1_file <- "matrix1.csv"
    matrix2_file <- "matrix2.csv"
    matrix3_file <- "matrix3.csv"
    
    if (!file.exists(matrix1_file) || !file.exists(matrix2_file) || !file.exists(matrix3_file)) {
      stop("Error: One or more of the required input files (matrix1.csv, matrix2.csv, matrix3.csv) are missing.")
    }
    
    m1 <- as.matrix(read.csv(matrix1_file, row.names = 1, check.names = FALSE))
    m2 <- as.matrix(read.csv(matrix2_file, row.names = 1, check.names = FALSE))
    m3 <- as.matrix(read.csv(matrix3_file, row.names = 1, check.names = FALSE))
    
    # Ensure identical dimensions, row names, and column names
    common_rows <- intersect(rownames(m1), intersect(rownames(m2), rownames(m3)))
    common_cols <- intersect(colnames(m1), intersect(colnames(m2), colnames(m3)))
    
    if (length(common_rows) == 0 || length(common_cols) == 0) {
      stop("Error: No common features (rows) or samples (columns) found across the input matrices.")
    }
    
    m1 <- m1[common_rows, common_cols, drop = FALSE]
    m2 <- m2[common_rows, common_cols, drop = FALSE]
    m3 <- m3[common_rows, common_cols, drop = FALSE]
    
    # 2. Construct a MultiMeasure object using MultiMeasure()
    tcga_mm <- MultiMeasure(names=c("Platform1", "Platform2", "Platform3"), 
                            data=list(m1, m2, m3))
    
    # Determine genes to plot (use TP53/MYO7B if present, otherwise fallback to available genes)
    gene1 <- if ("TP53" %in% common_rows) "TP53" else common_rows[1]
    gene2 <- if ("MYO7B" %in% common_rows) "MYO7B" else common_rows[min(2, length(common_rows))]
    
    # Open PDF device to save all visualizations
    pdf("consensus_analysis_plots.pdf", width = 8, height = 6)
    
    # 3. Visualize a single gene fit using plotOneFit()
    plotOneFit(tcga_mm, gene1, brewer.pal(n = 3, name = "Dark2"))
    
    # 4. Fit the consensus model using fitConsensus()
    fit <- fitConsensus(tcga_mm)
    
    # Save the fit object
    saveRDS(fit, "consensus_fit.rds")
    
    # 5. Plot marginal distributions of average, sensitivity, and precision using plotMarginals()
    plotMarginals(fit, "average", brewer.pal(n = 3, name = "Dark2"))
    plotMarginals(fit, "sensitivity", brewer.pal(n = 3, name = "Dark2"))
    plotMarginals(fit, "precision", brewer.pal(n = 3, name = "Dark2"))
    
    # 6. Identify and plot the most discordant genes using plotMostDiscordant()
    n_discordant <- min(15, length(common_rows))
    plotMostDiscordant(fit, "sensitivity", n_discordant)
    
    # Plot second gene fit
    plotOneFit(tcga_mm, gene2, brewer.pal(n = 3, name = "Dark2"))
    
    # Close PDF device
    dev.off()
    
    # Export fit parameters to CSV files for downstream analysis
    tryCatch({
      slots <- slotNames(fit)
      for (s in slots) {
        val <- slot(fit, s)
        if (is.matrix(val) || is.vector(val) || is.data.frame(val)) {
          write.csv(as.data.frame(val), paste0("consensus_fit_", s, ".csv"), row.names = TRUE)
        }
      }
    }, error = function(e) {
      warning("Could not export individual slots to CSV: ", e\$message)
    })

    writeLines(c(
        '"BIOC_CONSENSUS_CROSS_PLATFORM_CONSENSUS_ANALYSIS":',
        paste0('    consensus: ', as.character(packageVersion('consensus')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cross_platform_consensus_analysis.csv versions.yml
    """
}

workflow BIOC_CONSENSUS_CROSS_PLATFORM_CONSENSUS_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ matrix1.csv, matrix2.csv, matrix3.csv ] ]

    main:
    BIOC_CONSENSUS_CROSS_PLATFORM_CONSENSUS_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CONSENSUS_CROSS_PLATFORM_CONSENSUS_ANALYSIS.out.tables
    plots    = BIOC_CONSENSUS_CROSS_PLATFORM_CONSENSUS_ANALYSIS.out.plots
    objects  = BIOC_CONSENSUS_CROSS_PLATFORM_CONSENSUS_ANALYSIS.out.objects
    versions = BIOC_CONSENSUS_CROSS_PLATFORM_CONSENSUS_ANALYSIS.out.versions
}
