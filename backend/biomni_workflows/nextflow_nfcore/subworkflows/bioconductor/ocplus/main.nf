#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: OCplus — ocplus_microarray_pipeline
// Perform a comprehensive microarray operating characteristics analysis, estimating global and local FDR, identifying differentially expressed genes, and planning
// Input: counts.csv, coldata.csv
// Container: 1.84.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: OCplus
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OCPLUS_OCPLUS_MICROARRAY_PIPELINE {
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
    .bm_deps <- c("OCplus")
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
    library(OCplus)
    
    # Define parameters
    FDR_CUTOFF <- 0.1
    EFFECT_SIZE <- 1.0
    
    # ==========================================
    # --- Load and Preprocess Input Data ---
    # ==========================================
    cat("Loading input data...\n")
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # If 'gene_id' is a column instead of row names, set it as row names
    if ("gene_id" %in% colnames(counts)) {
        rownames(counts) <- counts\$gene_id
        counts\$gene_id <- NULL
    }
    
    # Align columns of counts with samples in coldata
    common_samples <- intersect(colnames(counts), coldata\$sample)
    if (length(common_samples) == 0) {
        stop("Error: No matching samples found between counts.csv and coldata.csv")
    }
    counts <- counts[, common_samples, drop = FALSE]
    coldata <- coldata[match(common_samples, coldata\$sample), ]
    
    # Extract group labels and validate
    group_labels <- as.character(coldata\$condition)
    unique_groups <- unique(group_labels)
    if (length(unique_groups) != 2) {
        stop("Error: OCplus analysis requires exactly two groups/conditions.")
    }
    
    # Filter out genes with zero or extremely low variance to ensure numerical stability
    row_vars <- apply(counts, 1, var)
    counts_filtered <- as.matrix(counts[row_vars > 1e-4, ])
    cat(sprintf("Data loaded successfully. Analyzing %d genes across %d samples.\n", 
                nrow(counts_filtered), ncol(counts_filtered)))
    
    # ==========================================
    # --- Empirical Operating Characteristics (EOC) ---
    # ==========================================
    cat("Running Empirical Operating Characteristics (EOC)...\n")
    sim1 <- EOC(counts_filtered, group_labels, plot = FALSE)
    p0_eoc <- p0(sim1)
    
    # Extract top DE genes using global FDR
    top_eoc <- tryCatch({
        topDE(sim1, co = FDR_CUTOFF)
    }, error = function(e) {
        warning("topDE for EOC failed or returned empty: ", e\$message)
        data.frame()
    })
    
    # ==========================================
    # Stage 3: 1D Local FDR (fdr1d)
    # ==========================================
    cat("Running 1D Local FDR (fdr1d)...\n")
    sim2 <- fdr1d(counts_filtered, group_labels, verb = FALSE)
    p0_fdr1d <- p0(sim2)
    
    # Extract top DE genes using 1D local FDR
    top_fdr1d <- tryCatch({
        topDE(sim2, co = FDR_CUTOFF)
    }, error = function(e) {
        warning("topDE for fdr1d failed or returned empty: ", e\$message)
        data.frame()
    })
    
    # ==========================================
    # Stage 4: 2D Local FDR (fdr2d)
    # ==========================================
    cat("Running 2D Local FDR (fdr2d)...\n")
    # Use the robust p0 estimate from fdr1d as recommended
    sim3 <- fdr2d(counts_filtered, group_labels, p0 = p0_fdr1d, verb = FALSE)
    
    # Extract top DE genes using 2D local FDR
    top_fdr2d <- tryCatch({
        topDE(sim3, co = FDR_CUTOFF)
    }, error = function(e) {
        warning("topDE for fdr2d failed or returned empty: ", e\$message)
        data.frame()
    })
    
    # ==========================================
    # --- Mixture Model for p0 Estimation ---
    # ==========================================
    cat("Estimating p0 using mixture t-distributions...\n")
    p0_mix <- NA
    tryCatch({
        tt <- tstatistics(counts_filtered, group_labels)
        tm <- tMixture(tt, nq = 3)
        p0_mix <- tm\$p0.est
    }, error = function(e) {
        warning("tMixture estimation failed: ", e\$message)
    })
    
    # Save all p0 estimates
    p0_df <- data.frame(
        Method = c("EOC_Storey", "fdr1d_Efron", "tMixture"),
        p0_Estimate = c(p0_eoc, p0_fdr1d, p0_mix)
    )
    write.csv(p0_df, "p0_estimates.csv", row.names = FALSE)
    
    # ==========================================
    # --- Sample Size & Design Planning ---
    # ==========================================
    cat("Performing sample size planning...\n")
    # Use the empirical fdr1d p0 estimate for planning, fallback to 0.9 if invalid
    p0_plan <- if (!is.na(p0_fdr1d) && p0_fdr1d > 0 && p0_fdr1d < 1) p0_fdr1d else 0.9
    
    ss_plan <- samplesize(p0 = p0_plan, D = EFFECT_SIZE, crit = 0.01, plot = FALSE)
    write.csv(as.data.frame(ss_plan), "sample_size_planning.csv", row.names = TRUE)
    
    # ==========================================
    # --- Export Tables and Generate Plots ---
    # ==========================================
    cat("Exporting results and generating diagnostic plots...\n")
    
    # Write top DE tables
    write.csv(top_eoc, "top_de_eoc.csv", row.names = TRUE)
    write.csv(top_fdr1d, "top_de_fdr1d.csv", row.names = TRUE)
    write.csv(top_fdr2d, "top_de_fdr2d.csv", row.names = TRUE)
    
    # Generate comprehensive PDF report
    pdf("ocplus_diagnostic_plots.pdf", width = 10, height = 8)
    
    # 1. EOC Plot
    plot(sim1)
    title(sub = "Empirical Operating Characteristics (EOC)")
    
    # 2. fdr1d Plot
    plot(sim2)
    title(sub = "1D Local FDR")
    
    # 3. fdr2d Plot
    plot(sim3)
    title(sub = "2D Local FDR (t-statistic vs log standard error)")
    
    # 4. 1D vs 2D Comparison Plot
    plot(sim2)
    lines(average.fdr(sim3), lty = 2, col = "red", lwd = 2)
    legend("topright", legend = c("1D fdr", "Averaged 2D fdr"), lty = c(1, 2), col = c("black", "red"), lwd = c(1, 2))
    title(sub = "Comparison of 1D and Averaged 2D Local FDR")
    
    # 5. Method Performance Comparison (OCshow)
    OCshow(sim1, sim2, sim3, legend = c("FDR (EOC)", "fdr1d", "fdr2d"))
    title(sub = "Operating Characteristics Comparison")
    
    # 6. Theoretical Operating Characteristics (TOC) for future design
    TOC(n = 20, p0 = p0_plan, D = EFFECT_SIZE, alpha = FALSE, legend = TRUE)
    title(sub = sprintf("Theoretical Operating Characteristics (n=20, p0=%.3f, D=%.1f)", p0_plan, EFFECT_SIZE))
    
    dev.off()
    
    cat("Pipeline completed successfully!\n")

    writeLines(c(
        '"BIOC_OCPLUS_OCPLUS_MICROARRAY_PIPELINE":',
        paste0('    OCplus: ', as.character(packageVersion('OCplus')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ocplus_microarray_pipeline.csv versions.yml
    """
}

workflow BIOC_OCPLUS_OCPLUS_MICROARRAY_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_OCPLUS_OCPLUS_MICROARRAY_PIPELINE(ch_input)

    emit:
    tables   = BIOC_OCPLUS_OCPLUS_MICROARRAY_PIPELINE.out.tables
    plots    = BIOC_OCPLUS_OCPLUS_MICROARRAY_PIPELINE.out.plots
    objects  = BIOC_OCPLUS_OCPLUS_MICROARRAY_PIPELINE.out.objects
    versions = BIOC_OCPLUS_OCPLUS_MICROARRAY_PIPELINE.out.versions
}
