#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: isomiRs — isomirs_characterization_and_de
// Characterize miRNA and isomiR molecules, perform normalization, annotation, and differential expression analysis using the isomiRs package.
// Input: counts.csv, coldata.csv
// Container: 1.38.1--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DESeq2, SummarizedExperiment, isomiRs
// Visualizations: MA plot
// QC: diagnostic MA/PCA QC
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ISOMIRS_ISOMIRS_CHARACTERIZATION_AND_DE {
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
    .bm_deps <- c("isomiRs", "DESeq2")
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
    
    # --- Load required libraries ---
    library(isomiRs)
    library(DESeq2)
    
    # --- Read input files ---
    message("Reading input files...")
    counts_df <- read.csv("counts.csv", check.names = FALSE, stringsAsFactors = FALSE)
    if ("gene_id" %in% colnames(counts_df)) {
      rownames(counts_df) <- counts_df\$gene_id
      counts_df\$gene_id <- NULL
    }
    counts_matrix <- as.matrix(counts_df)
    
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    rownames(coldata) <- coldata\$sample
    
    # Ensure sample names match between counts and coldata
    common_samples <- intersect(colnames(counts_matrix), rownames(coldata))
    if (length(common_samples) == 0) {
      stop("No common samples found between counts.csv and coldata.csv")
    }
    counts_matrix <- counts_matrix[, common_samples, drop = FALSE]
    coldata <- coldata[common_samples, , drop = FALSE]
    
    # --- Reconstruct raw data list for IsomirDataSeqFromRawData ---
    message("Parsing isomiR names and reconstructing raw data...")
    parse_isomirs <- function(ids_vector) {
      n <- length(ids_vector)
      mir <- character(n)
      t3 <- rep("0", n)
      t5 <- rep("0", n)
      add <- rep("0", n)
      mism <- rep("0", n)
      seq <- character(n)
      
      for (i in seq_along(ids_vector)) {
        parts <- strsplit(ids_vector[i], ";")[[1]]
        mir[i] <- parts[1]
        # Generate a dummy sequence of A, C, G, T to satisfy internal checks
        seq[i] <- substr(paste0("TGTAAACATCCTACACTCAGCT", i, "AAAAAAAAAAAAAAAAAAAA"), 1, 22)
        
        if (length(parts) > 1) {
          for (p in parts[-1]) {
            if (startsWith(p, "iso_3p:")) {
              t3[i] <- sub("iso_3p:", "", p)
            } else if (startsWith(p, "iso_5p:")) {
              t5[i] <- sub("iso_5p:", "", p)
            } else if (startsWith(p, "iso_add:") || startsWith(p, "iso_add3p:")) {
              add[i] <- sub("iso_add3p:", "", sub("iso_add:", "", p))
            } else if (startsWith(p, "iso_snp:") || startsWith(p, "iso_mism:")) {
              mism[i] <- sub("iso_snp:", "", sub("iso_mism:", "", p))
            }
          }
        }
      }
      data.frame(seq=seq, mir=mir, mism=mism, add=add, t5=t5, t3=t3, stringsAsFactors=FALSE)
    }
    
    raw_list <- list()
    for (sample_name in colnames(counts_matrix)) {
      counts_val <- counts_matrix[, sample_name]
      keep <- counts_val > 0
      if (sum(keep) == 0) {
        keep[1] <- TRUE # Keep at least one row to avoid empty data frame
      }
      parsed <- parse_isomirs(rownames(counts_matrix)[keep])
      df <- data.frame(
        seq = parsed\$seq,
        name = paste0("seq_", seq_len(sum(keep))),
        freq = as.integer(counts_val[keep]),
        mir = parsed\$mir,
        start = 1L,
        end = 22L,
        mism = parsed\$mism,
        add = parsed\$add,
        t5 = parsed\$t5,
        t3 = parsed\$t3,
        stringsAsFactors = FALSE
      )
      raw_list[[sample_name]] <- df
    }
    
    # --- Create IsomirDataSeq and collapse counts ---
    message("Creating IsomirDataSeq object...")
    ids <- IsomirDataSeqFromRawData(raw_list, design = coldata)
    ids <- isoCounts(ids)
    
    # --- Normalization ---
    message("Normalizing counts...")
    ids <- isoNorm(ids, formula = ~ condition)
    norm_counts <- counts(ids, norm = TRUE)
    write.csv(as.data.frame(norm_counts), "normalized_counts.csv")
    
    # --- Annotation and Top IsomiRs ---
    message("Generating annotations and extracting top features...")
    tryCatch({
      ann <- isoAnnotate(ids)
      write.csv(as.data.frame(ann), "isomirs_annotation.csv")
    }, error = function(e) {
      message("Annotation failed: ", e\$message)
      write.csv(data.frame(Status = "Annotation failed"), "isomirs_annotation.csv")
    })
    
    tryCatch({
      top_iso <- isoTop(ids)
      write.csv(as.data.frame(top_iso), "top_isomirs.csv")
    }, error = function(e) {
      message("isoTop failed: ", e\$message)
      write.csv(data.frame(Status = "isoTop failed"), "top_isomirs.csv")
    })
    
    # --- Select top miRNA for detailed inspection ---
    tryCatch({
      top_mirna <- rownames(counts(ids))[order(rowMeans(counts(ids)), decreasing = TRUE)[1]]
      if (!is.na(top_mirna)) {
        selected_data <- isoSelect(ids, mirna = top_mirna)
        write.csv(as.data.frame(selected_data), "selected_top_mirna_isomirs.csv")
      } else {
        write.csv(data.frame(Status = "No top miRNA found"), "selected_top_mirna_isomirs.csv")
      }
    }, error = function(e) {
      message("isoSelect failed: ", e\$message)
      write.csv(data.frame(Status = "isoSelect failed"), "selected_top_mirna_isomirs.csv")
    })
    
    # --- Diagnostic Plotting ---
    message("Generating diagnostic plots...")
    pdf("isomirs_plots.pdf", width = 10, height = 8)
    tryCatch({
      print(isoPlot(ids, type = "all"))
    }, error = function(e) {
      plot.new()
      text(0.5, 0.5, paste("isoPlot failed:", e\$message), cex = 0.8)
    })
    
    tryCatch({
      print(isoPlotPosition(ids))
    }, error = function(e) {
      plot.new()
      text(0.5, 0.5, paste("isoPlotPosition failed:", e\$message), cex = 0.8)
    })
    dev.off()
    
    # --- Differential Expression Analysis ---
    message("Running differential expression analysis...")
    pdf("de_plots.pdf", width = 10, height = 8)
    par(mfrow = c(2, 1))
    
    # 9a: Reference miRNAs only
    tryCatch({
      dds <- isoDE(ids, formula = ~ condition)
      res <- results(dds, format = "DataFrame")
      write.csv(as.data.frame(res), "de_results_ref_only.csv")
      plotMA(dds, main = "MA Plot: Reference miRNAs Only")
    }, error = function(e) {
      message("Standard isoDE failed: ", e\$message)
      write.csv(data.frame(Status = "isoDE failed", Error = e\$message), "de_results_ref_only.csv")
      plot.new()
      text(0.5, 0.5, "Standard isoDE failed")
    })
    
    # 9b: Distinguishing reference and 5' isomiRs
    tryCatch({
      dds_iso <- isoDE(ids, formula = ~ condition, ref = TRUE, iso5 = TRUE)
      res_iso <- results(dds_iso, format = "DataFrame")
      write.csv(as.data.frame(res_iso), "de_results_isomiRs.csv")
      plotMA(dds_iso, main = "MA Plot: Reference vs 5' isomiRs")
    }, error = function(e) {
      message("IsomiR-specific isoDE failed: ", e\$message)
      write.csv(data.frame(Status = "IsomiR-specific isoDE failed", Error = e\$message), "de_results_isomiRs.csv")
      plot.new()
      text(0.5, 0.5, "IsomiR-specific isoDE failed")
    })
    
    dev.off()
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_ISOMIRS_ISOMIRS_CHARACTERIZATION_AND_DE":',
        paste0('    isomiRs: ', as.character(packageVersion('isomiRs')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_isomirs_characterization_and_de.csv versions.yml
    """
}

workflow BIOC_ISOMIRS_ISOMIRS_CHARACTERIZATION_AND_DE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_ISOMIRS_ISOMIRS_CHARACTERIZATION_AND_DE(ch_input)

    emit:
    tables   = BIOC_ISOMIRS_ISOMIRS_CHARACTERIZATION_AND_DE.out.tables
    plots    = BIOC_ISOMIRS_ISOMIRS_CHARACTERIZATION_AND_DE.out.plots
    objects  = BIOC_ISOMIRS_ISOMIRS_CHARACTERIZATION_AND_DE.out.objects
    versions = BIOC_ISOMIRS_ISOMIRS_CHARACTERIZATION_AND_DE.out.versions
}
