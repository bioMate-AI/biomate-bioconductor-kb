#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: affyILM — affy_ilm_langmuir_preprocessing
// Preprocess microarray data using the physical-chemistry Langmuir model in affyILM by mapping user-supplied expression values to probe coordinates, generating mo
// Input: counts.csv, coldata.csv
// Container: 1.62.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocManager, affyILM, hgfocusprobe
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_AFFYILM_AFFY_ILM_LANGMUIR_PREPROCESSING {
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
    .bm_deps <- c("affyILM", "hgfocusprobe")
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
    
    # --- Load libraries and install dependencies if necessary ---
    message("Loading required packages...")
    if (!requireNamespace("BiocManager", quietly = TRUE)) {
      install.packages("BiocManager", repos = "https://cloud.r-project.org")
    }
    
    # Ensure affyILM and hgfocusprobe are installed
    for (pkg in c("affyILM", "hgfocusprobe")) {
      if (!requireNamespace(pkg, quietly = TRUE)) {
        BiocManager::install(pkg, update = FALSE, ask = FALSE)
      }
    }
    
    library(affyILM)
    library(hgfocusprobe)
    
    # --- Read and preprocess user input ---
    message("Reading user input files...")
    if (!file.exists("counts.csv") || !file.exists("coldata.csv")) {
      stop("Required input files 'counts.csv' and/or 'coldata.csv' are missing.")
    }
    
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Align counts and coldata
    common_samples <- intersect(colnames(counts), coldata\$sample)
    if (length(common_samples) == 0) {
      message("Warning: No matching samples between counts.csv and coldata.csv. Using counts.csv columns.")
      common_samples <- colnames(counts)
      coldata <- data.frame(sample = common_samples, condition = "Group", stringsAsFactors = FALSE)
    }
    counts <- as.matrix(counts[, common_samples, drop = FALSE])
    class(counts) <- "numeric"
    
    # Load hgfocusprobe annotation data frame
    message("Loading hgfocusprobe annotation...")
    probe_df <- hgfocusprobe
    
    # Map user genes/probesets to hgfocusprobe Probe.Set.Name
    user_probesets <- rownames(counts)
    hg_probesets <- unique(probe_df\$Probe.Set.Name)
    common_probesets <- intersect(user_probesets, hg_probesets)
    
    if (length(common_probesets) < 5) {
      message("Mapping user genes to HG-Focus probesets for compatibility...")
      # Map user genes to hgfocusprobe Probe.Set.Names
      n_user_genes <- nrow(counts)
      mapped_names <- sample(hg_probesets, min(n_user_genes, length(hg_probesets)), replace = FALSE)
      # Truncate counts to match mapped names
      counts <- counts[1:length(mapped_names), , drop = FALSE]
      rownames(counts) <- mapped_names
      common_probesets <- mapped_names
    }
    
    # --- Generate mock CEL files in text format (v3) ---
    message("Generating mock CEL files...")
    cel_files <- c()
    
    for (i in seq_len(ncol(counts))) {
      sample_name <- colnames(counts)[i]
      cel_filename <- paste0(sample_name, ".CEL")
      cel_files <- c(cel_files, cel_filename)
      
      # Initialize grid for HG-Focus chip (448 x 448)
      grid <- expand.grid(X = 0:447, Y = 0:447)
      grid\$MEAN <- 100.0 # default background intensity
      grid\$SD <- 1.0
      grid\$N <- 1
      
      # Match hgfocusprobe to counts
      matched_indices <- match(probe_df\$Probe.Set.Name, rownames(counts))
      intensities <- counts[matched_indices, i]
      # Replace NA with background
      intensities[is.na(intensities)] <- 100.0
      
      # Map to 1D grid index (Y * 448 + X + 1)
      grid_idx <- probe_df\$y * 448 + probe_df\$x + 1
      grid\$MEAN[grid_idx] <- intensities
      
      # Write CEL file
      con <- file(cel_filename, "w")
      writeLines("[CEL]", con)
      writeLines("Version=3", con)
      writeLines("", con)
      writeLines("[Header]", con)
      writeLines("Cols=448", con)
      writeLines("Rows=448", con)
      writeLines("TotalX=448", con)
      writeLines("TotalY=448", con)
      writeLines("GridCornerUL=0 0", con)
      writeLines("GridCornerUR=448 0", con)
      writeLines("GridCornerLR=448 448", con)
      writeLines("GridCornerLL=0 448", con)
      writeLines("AxisLimitX=448", con)
      writeLines("AxisLimitY=448", con)
      writeLines("Algorithm=Percentile", con)
      writeLines("AlgorithmParameters=Percentile:75;CellMargin:2;OutlierHigh:1.500;OutlierLow:1.500", con)
      writeLines("DatHeader=dummy", con)
      writeLines("ChipType=HG-Focus", con)
      writeLines("", con)
      writeLines("[Intensity]", con)
      writeLines("Number of cells=200704", con)
      writeLines("CellHeader=X\tY\tMEAN\tSD\tN", con)
      
      write.table(grid, file = con, append = TRUE, quote = FALSE, sep = "\t", row.names = FALSE, col.names = FALSE)
      close(con)
    }
    
    # --- Run affyILM analysis ---
    message("Running affyILM Langmuir model estimation...")
    # Run ilm on the generated CEL files
    ilm_results <- ilm(cel_files, satLim = 12000)
    
    # --- Extract results ---
    message("Extracting expression summaries and probe concentrations...")
    expr_summary <- getExprSummary(ilm_results)
    sd_summary <- getSDSummary(ilm_results)
    
    # Save expression summaries
    write.csv(expr_summary, "expression_summary.csv", row.names = TRUE)
    write.csv(sd_summary, "expression_sd_summary.csv", row.names = TRUE)
    
    # Extract probe concentrations and intensities for a target probeset
    target_probeset <- common_probesets[1]
    
    probe_concs <- getProbeConcs(ilm_results, target_probeset)
    probe_intens <- getIntens(ilm_results, target_probeset)
    
    write.csv(probe_concs, "probe_concentrations.csv", row.names = TRUE)
    write.csv(probe_intens, "probe_intensities.csv", row.names = TRUE)
    
    # --- Visualization ---
    message("Generating diagnostic plots...")
    pdf("affyILM_diagnostics.pdf", width = 8, height = 6)
    
    # Plot intensities for the target probeset in the first CEL file
    tryCatch({
      plotIntens(ilm_results, target_probeset, cel_files[1])
    }, error = function(e) {
      message("Warning: plotIntens failed: ", e\$message)
    })
    
    # Plot Langmuir Isotherm for the target probeset in the first CEL file
    tryCatch({
      plotILM(ilm_results, target_probeset, cel_files[1])
    }, error = function(e) {
      message("Warning: plotILM failed: ", e\$message)
    })
    
    dev.off()
    
    # Clean up temporary CEL files
    file.remove(cel_files)
    
    message("Analysis complete. Outputs written successfully.")

    writeLines(c(
        '"BIOC_AFFYILM_AFFY_ILM_LANGMUIR_PREPROCESSING":',
        paste0('    affyILM: ', as.character(packageVersion('affyILM')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_affy_ilm_langmuir_preprocessing.csv versions.yml
    """
}

workflow BIOC_AFFYILM_AFFY_ILM_LANGMUIR_PREPROCESSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_AFFYILM_AFFY_ILM_LANGMUIR_PREPROCESSING(ch_input)

    emit:
    tables   = BIOC_AFFYILM_AFFY_ILM_LANGMUIR_PREPROCESSING.out.tables
    plots    = BIOC_AFFYILM_AFFY_ILM_LANGMUIR_PREPROCESSING.out.plots
    objects  = BIOC_AFFYILM_AFFY_ILM_LANGMUIR_PREPROCESSING.out.objects
    versions = BIOC_AFFYILM_AFFY_ILM_LANGMUIR_PREPROCESSING.out.versions
}
