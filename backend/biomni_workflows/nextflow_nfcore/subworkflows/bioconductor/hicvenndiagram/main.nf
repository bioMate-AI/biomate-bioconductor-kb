#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: hicVennDiagram — hic_venn_diagram_pipeline
// Perform genomic overlap and enrichment analysis of chromatin interactions or peak regions across experimental conditions using hicVennDiagram, generating high-r
// Input: matrix.csv, coldata.csv
// Container: 1.8.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, hicVennDiagram
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HICVENNDIAGRAM_HIC_VENN_DIAGRAM_PIPELINE {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(hicVennDiagram)
    library(ggplot2)
    
    # ==========================================
    # --- Read and Parse Input Data ---
    # ==========================================
    message("Stage 1: Reading input files...")
    
    # Read feature-by-sample matrix and sample metadata
    mat <- read.csv("matrix.csv", row.names = NULL, check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Identify the feature ID column
    if ("feature_id" %in% colnames(mat)) {
      feature_col <- "feature_id"
    } else {
      feature_col <- colnames(mat)[1]
    }
    feature_ids <- mat[[feature_col]]
    
    # Extract numeric sample columns
    sample_mat <- mat[, setdiff(colnames(mat), feature_col), drop = FALSE]
    rownames(sample_mat) <- feature_ids
    
    # Align samples between matrix and coldata
    common_samples <- intersect(colnames(sample_mat), coldata\$sample)
    if (length(common_samples) == 0) {
      stop("Error: No common samples found between matrix.csv and coldata.csv")
    }
    sample_mat <- sample_mat[, common_samples, drop = FALSE]
    coldata <- coldata[coldata\$sample %in% common_samples, ]
    
    # ==========================================
    # --- Parse Genomic Coordinates (BED vs BEDPE) ---
    # ==========================================
    message("Stage 2: Parsing genomic coordinates...")
    
    # Helper function to parse feature IDs into BED or BEDPE format
    parse_features <- function(ids) {
      ids <- trimws(ids)
      # Check if features represent genomic interactions (contain two distinct regions)
      has_two_chrs <- grepl("chr.*chr", ids, ignore.case = TRUE)
      
      if (any(has_two_chrs)) {
        # Parse as BEDPE (chrom1, start1, end1, chrom2, start2, end2)
        parsed <- lapply(ids, function(x) {
          matches <- regmatches(x, gregexpr("[a-zA-Z0-9]+", x))[[1]]
          if (length(matches) >= 6) {
            return(matches[1:6])
          } else {
            return(NULL)
          }
        })
        valid <- !sapply(parsed, is.null)
        if (sum(valid) == 0) stop("Could not parse features as BEDPE.")
        df <- do.call(rbind, parsed[valid])
        colnames(df) <- c("chrom1", "start1", "end1", "chrom2", "start2", "end2")
        df <- as.data.frame(df, stringsAsFactors = FALSE)
        df\$start1 <- as.numeric(df\$start1)
        df\$end1 <- as.numeric(df\$end1)
        df\$start2 <- as.numeric(df\$start2)
        df\$end2 <- as.numeric(df\$end2)
        return(list(type = "BEDPE", data = df))
      } else {
        # Parse as BED (chrom, start, end)
        parsed <- lapply(ids, function(x) {
          matches <- regmatches(x, gregexpr("[a-zA-Z0-9]+", x))[[1]]
          if (length(matches) >= 3) {
            return(matches[1:3])
          } else {
            return(NULL)
          }
        })
        valid <- !sapply(parsed, is.null)
        if (sum(valid) == 0) stop("Could not parse features as BED.")
        df <- do.call(rbind, parsed[valid])
        colnames(df) <- c("chrom", "start", "end")
        df <- as.data.frame(df, stringsAsFactors = FALSE)
        df\$start <- as.numeric(df\$start)
        df\$end <- as.numeric(df\$end)
        return(list(type = "BED", data = df))
      }
    }
    
    parsed_features <- parse_features(feature_ids)
    parsed_type <- parsed_features\$type
    parsed_df <- parsed_features\$data
    parsed_df\$feature_id <- feature_ids[as.numeric(rownames(parsed_df))]
    
    message(paste("Detected feature type:", parsed_type))
    
    # ==========================================
    # --- Identify Active Features & Write Temp Files ---
    # ==========================================
    message("Stage 3: Identifying active features per condition...")
    
    conditions <- unique(coldata\$condition)
    file_list <- c()
    
    for (cond in conditions) {
      cond_samples <- coldata\$sample[coldata\$condition == cond]
      
      # Calculate mean signal/count for this condition
      if (length(cond_samples) > 1) {
        mean_counts <- rowMeans(sample_mat[, cond_samples, drop = FALSE], na.rm = TRUE)
      } else {
        mean_counts <- sample_mat[, cond_samples]
      }
      
      # Filter active features (above median of non-zero counts)
      non_zero <- mean_counts[mean_counts > 0]
      threshold <- if (length(non_zero) > 0) median(non_zero) else 0
      active_ids <- names(mean_counts)[mean_counts > threshold]
      
      # Limit to top 1000 features per condition to ensure clean visualization
      if (length(active_ids) > 1000) {
        active_ids <- names(sort(mean_counts, decreasing = TRUE))[1:1000]
      }
      
      cond_df <- parsed_df[parsed_df\$feature_id %in% active_ids, ]
      
      # Write to temporary files with appropriate extensions
      if (parsed_type == "BEDPE") {
        tmp_file <- tempfile(pattern = paste0("cond_", cond, "_"), fileext = ".bedpe")
        write.table(cond_df[, c("chrom1", "start1", "end1", "chrom2", "start2", "end2")],
                    file = tmp_file, sep = "\t", col.names = FALSE, row.names = FALSE, quote = FALSE)
      } else {
        tmp_file <- tempfile(pattern = paste0("cond_", cond, "_"), fileext = ".bed")
        write.table(cond_df[, c("chrom", "start", "end")],
                    file = tmp_file, sep = "\t", col.names = FALSE, row.names = FALSE, quote = FALSE)
      }
      file_list[cond] <- tmp_file
    }
    
    # ==========================================
    # --- Overlap Calculation using hicVennDiagram ---
    # ==========================================
    message("Stage 4: Calculating overlaps...")
    
    # Run vennCount with user-defined parameters
    venn <- vennCount(file_list, maxgap = 50000, FUN = min)
    
    # Save Venn summary table
    tryCatch({
      write.csv(as.data.frame(venn), "venn_summary.csv", row.names = TRUE)
    }, error = function(e) {
      # Fallback if direct coercion is not supported
      sink("venn_summary.csv")
      show(venn)
      sink()
    })
    
    # ==========================================
    # --- Visualization (Venn & UpSet Plots) ---
    # ==========================================
    message("Stage 5: Generating plots...")
    
    # Define standard UpSet theme fixes from the vignette
    upset_themes_fix <- list(
      intersections_matrix = list(
        ggplot2::theme_minimal(),
        ggplot2::theme(
          axis.text.x = ggplot2::element_blank(),
          axis.ticks.x = ggplot2::element_blank(),
          axis.title.y = ggplot2::element_blank()
        )
      ),
      'Intersection size' = list(
        ggplot2::theme_minimal(),
        ggplot2::theme(
          axis.text.x = ggplot2::element_blank(),
          axis.title.x = ggplot2::element_blank()
        )
      ),
      overall_sizes = list(
        ggplot2::theme_minimal(),
        ggplot2::theme(
          axis.title.y = ggplot2::element_blank(),
          axis.text.y = ggplot2::element_blank(),
          axis.ticks.y = ggplot2::element_blank()
        )
      ),
      default = list(
        ggplot2::theme_minimal(),
        ggplot2::theme(
          axis.text.x = ggplot2::element_blank(),
          axis.title.x = ggplot2::element_blank()
        )
      )
    )
    
    # Generate and save Venn Plot
    pdf("venn_plot.pdf", width = 8, height = 8)
    tryCatch({
      print(vennPlot(venn))
    }, error = function(e) {
      plot.new()
      text(0.5, 0.5, paste("Venn plot not available:\n", e\$message), cex = 1.2)
    })
    dev.off()
    
    # Generate and save UpSet Plot
    pdf("upset_plot.pdf", width = 10, height = 7)
    tryCatch({
      print(upsetPlot(venn, themes = upset_themes_fix))
    }, error = function(e) {
      plot.new()
      text(0.5, 0.5, paste("UpSet plot not available:\n", e\$message), cex = 1.2)
    })
    dev.off()
    
    # ==========================================
    # --- Genomic Loops Enrichment (GLEAM) ---
    # ==========================================
    message("Stage 6: Running GLEAM enrichment analysis...")
    
    # Initialize output file
    write.csv(data.frame(Message = "GLEAM test only applicable for genomic interactions (BEDPE)"), 
              "gleam_enrichment_results.csv", row.names = FALSE)
    
    if (parsed_type == "BEDPE") {
      tryCatch({
        set.seed(123)
        background <- createGIbackground(file_list)
        gleam_res <- gleamTest(file_list, background = background, method = 'binom')
        write.csv(as.data.frame(gleam_res), "gleam_enrichment_results.csv", row.names = TRUE)
        message("GLEAM enrichment analysis completed successfully.")
      }, error = function(e) {
        warning("GLEAM test failed: ", e\$message)
      })
    }
    
    # Cleanup temporary files
    unlink(file_list)
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_HICVENNDIAGRAM_HIC_VENN_DIAGRAM_PIPELINE":',
        paste0('    hicVennDiagram: ', as.character(packageVersion('hicVennDiagram')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hic_venn_diagram_pipeline.csv versions.yml
    """
}

workflow BIOC_HICVENNDIAGRAM_HIC_VENN_DIAGRAM_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_HICVENNDIAGRAM_HIC_VENN_DIAGRAM_PIPELINE(ch_input)

    emit:
    tables   = BIOC_HICVENNDIAGRAM_HIC_VENN_DIAGRAM_PIPELINE.out.tables
    plots    = BIOC_HICVENNDIAGRAM_HIC_VENN_DIAGRAM_PIPELINE.out.plots
    objects  = BIOC_HICVENNDIAGRAM_HIC_VENN_DIAGRAM_PIPELINE.out.objects
    versions = BIOC_HICVENNDIAGRAM_HIC_VENN_DIAGRAM_PIPELINE.out.versions
}
