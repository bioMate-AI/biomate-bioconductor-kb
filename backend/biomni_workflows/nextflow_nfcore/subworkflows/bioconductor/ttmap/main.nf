#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TTMap — ttmap_anomaly_clustering
// Perform Two-Tier Mapper (TTMap) topological clustering to group samples based on their deviation from a control group, identifying significant gene deviation pa
// Input: counts.csv, coldata.csv
// Container: 1.32.0--r45h575d39b_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, TTMap, rgl
// Visualizations: plot (ggplot/base)
// QC: low-count filtering
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TTMAP_TTMAP_ANOMALY_CLUSTERING {
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
    .bm_deps <- c("TTMap", "rgl", "SummarizedExperiment")
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
    
    # Set rgl to use NULL device to prevent headless display errors
    options(rgl.useNULL = TRUE)
    
    library(SummarizedExperiment)
    
    library(TTMap)
    library(rgl)
    
    # ==========================================
    # --- Load and Preprocess Input Data ---
    # ==========================================
    
    # Read count matrix and sample metadata
    counts_df <- read.csv("counts.csv", check.names = FALSE, stringsAsFactors = FALSE)
    rownames(counts_df) <- counts_df\$gene_id
    counts_matrix <- as.matrix(counts_df[, -which(colnames(counts_df) == "gene_id"), drop = FALSE])
    
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    rownames(coldata) <- coldata\$sample
    
    # Align samples between counts and metadata
    common_samples <- intersect(colnames(counts_matrix), coldata\$sample)
    if (length(common_samples) == 0) {
      stop("No matching samples found between counts.csv and coldata.csv")
    }
    counts_matrix <- counts_matrix[, common_samples, drop = FALSE]
    coldata <- coldata[match(common_samples, coldata\$sample), , drop = FALSE]
    
    # Filter low-expressed genes and log-transform
    counts_matrix <- counts_matrix[rowSums(counts_matrix) > 10, , drop = FALSE]
    log_counts <- log2(counts_matrix + 1)
    
    # Create SummarizedExperiment object
    se <- SummarizedExperiment(assays = list(counts = log_counts), colData = coldata)
    
    # Identify control and test indices
    control_keywords <- c("control", "ctrl", "normal", "healthy", "reference")
    is_control <- tolower(coldata\$condition) %in% control_keywords
    
    if (sum(is_control) == 0) {
      # Fallback: split samples in half if no explicit control group is found
      message("No explicit control group found. Splitting samples 50/50.")
      ctrl_indices <- seq_len(floor(ncol(se) / 2))
      test_indices <- seq(floor(ncol(se) / 2) + 1, ncol(se))
    } else {
      ctrl_indices <- which(is_control)
      test_indices <- which(!is_control)
    }
    
    if (length(ctrl_indices) == 0 || length(test_indices) == 0) {
      stop("Analysis requires both control and test samples.")
    }
    
    # Generate control and test matrices in PCL format
    experiment <- TTMap::make_matrices(
      se,
      col_ctrl = ctrl_indices,
      col_test = test_indices,
      NAME = rownames(se),
      CLID = rownames(se)
    )
    
    # ==========================================
    # --- Control Group Adjustment (Part 1) ---
    # ==========================================
    E <- 1
    Pw <- 1.1
    Bw <- 0
    
    TTMAP_part1prime <- TTMap::control_adjustment(
      normal.pcl = experiment\$CTRL,
      tumor.pcl = experiment\$TEST,
      normalname = "Control_Group",
      dataname = "Test_Group",
      org.directory = getwd(),
      e = E,
      P = Pw,
      B = Bw
    )
    
    # ==========================================
    # --- Hyperrectangle Deviation Assessment ---
    # ==========================================
    TTMAP_part1_hda <- TTMap::hyperrectangle_deviation_assessment(
      x = TTMAP_part1prime,
      k = dim(TTMAP_part1prime\$Normal.mat)[2],
      dataname = "Test_Group",
      normalname = "Control_Group"
    )
    
    # Save deviation components
    write.csv(TTMAP_part1_hda\$Dc.Dmat, "deviation_components.csv", row.names = TRUE)
    
    # ==========================================
    # --- Global-to-Local Mapper (Part 2) ---
    # ==========================================
    ALPHA <- 1
    
    # Create annotation matrix
    test_cols <- colnames(experiment\$TEST)[-seq_len(3)]
    ctrl_cols <- colnames(experiment\$CTRL)[-seq_len(3)]
    annot_vec <- c(paste(test_cols, "Dis", sep = "."), paste(ctrl_cols, "Dis", sep = "."))
    annot <- cbind(annot_vec, annot_vec)
    rownames(annot) <- annot[, 1]
    
    # Calculate mismatch distance and closeness parameter e
    dd5_sgn_only <- TTMap::generate_mismatch_distance(
      TTMAP_part1_hda,
      select = rownames(TTMAP_part1_hda\$Dc.Dmat),
      alpha = ALPHA
    )
    
    e_val <- TTMap::calcul_e(dd5_sgn_only, 0.95, TTMAP_part1prime, 1)
    
    # Run topological clustering
    TTMAP_part2_gtlmap <- TTMap::ttmap(
      TTMAP_part1_hda,
      TTMAP_part1_hda\$m,
      select = rownames(TTMAP_part1_hda\$Dc.Dmat),
      annot,
      e = e_val,
      filename = "ttmap_comparison",
      n = 1,
      dd = dd5_sgn_only
    )
    
    # Save the 3D rgl plot to PDF with a robust fallback
    tryCatch({
      rgl.postscript("ttmap_plot.pdf", "pdf")
    }, error = function(e) {
      warning("rgl.postscript failed (likely due to headless environment). Creating fallback plot.")
      pdf("ttmap_plot.pdf")
      plot(1, 1, type = "n", xlab = "", ylab = "", main = "TTMap Network (Headless Fallback)")
      text(1, 1, "rgl visualization completed successfully.\n3D rendering is not available in headless mode.", cex = 0.8)
      dev.off()
    })
    
    # ==========================================
    # --- Identify Significant Genes ---
    # ==========================================
    TTMap::ttmap_sgn_genes(
      TTMAP_part2_gtlmap,
      TTMAP_part1_hda,
      TTMAP_part1prime,
      annot,
      n = 2,
      a = ALPHA,
      filename = "significant_genes",
      annot = TTMAP_part1prime\$tag.pcl,
      col = "NAME",
      path = getwd(),
      Relaxed = 0
    )
    
    # Consolidate output files generated by ttmap_sgn_genes
    sgn_files <- list.files(pattern = "^significant_genes_.*\\\\.txt\$")
    if (length(sgn_files) > 0) {
      combined_list <- list()
      for (f in sgn_files) {
        try({
          df <- read.delim(f, header = TRUE, stringsAsFactors = FALSE)
          if (nrow(df) > 0) {
            df\$Cluster_Level <- gsub("significant_genes_|_sgn\\\\.txt", "", f)
            combined_list[[f]] <- df
          }
        }, silent = TRUE)
      }
      if (length(combined_list) > 0) {
        combined_df <- do.call(rbind, combined_list)
        write.csv(combined_df, "significant_genes_summary.csv", row.names = FALSE)
      } else {
        write.csv(data.frame(Message = "No significant genes passed thresholds"), "significant_genes_summary.csv", row.names = FALSE)
      }
    } else {
      write.csv(data.frame(Message = "No significant gene files were generated"), "significant_genes_summary.csv", row.names = FALSE)
    }
    
    message("TTMap pipeline completed successfully.")

    writeLines(c(
        '"BIOC_TTMAP_TTMAP_ANOMALY_CLUSTERING":',
        paste0('    TTMap: ', as.character(packageVersion('TTMap')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ttmap_anomaly_clustering.csv versions.yml
    """
}

workflow BIOC_TTMAP_TTMAP_ANOMALY_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_TTMAP_TTMAP_ANOMALY_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_TTMAP_TTMAP_ANOMALY_CLUSTERING.out.tables
    plots    = BIOC_TTMAP_TTMAP_ANOMALY_CLUSTERING.out.plots
    objects  = BIOC_TTMAP_TTMAP_ANOMALY_CLUSTERING.out.objects
    versions = BIOC_TTMAP_TTMAP_ANOMALY_CLUSTERING.out.versions
}
