#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: decontam — frequency_based_decontamination
// Identify and remove contaminating sequence features based on the inverse relationship between their frequency and sample DNA concentration.
// Input: otu_table, sample_data
// Container: quay.io/biocontainers/bioconductor-decontam:1.30.0--r45hdfd78af_1
// R packages: decontam, ggplot2, phyloseq
// Bioconductor: 3.20 | R: 4.4
// Requires: decontam, ggplot2, phyloseq
// Visualizations: plot (ggplot/base)
// QC: prevalence/abundance filtering
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load phyloseq object containing feature table and metadata
//  * 2. [Core Analysis] Run frequency-based contaminant identification using isContaminant
//  * 3. [Visualization & Output] Visualize frequency vs. concentration using plot_frequency
//  * 4. [Core Analysis] Filter out identified contaminants using prune_taxa

nextflow.enable.dsl = 2

process BIOC_DECONTAM_FREQUENCY_BASED_DECONTAMINATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20-deps"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("decontam", "ggplot2", "phyloseq")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    
    # Load required libraries
    library(phyloseq)
    library(ggplot2)
    library(decontam)
    
    # Helper function to read input files with various extensions
    read_input_file <- function(base_name) {
      extensions <- c(".csv", ".tsv", ".txt", ".rds")
      for (ext in extensions) {
        file_path <- paste0(base_name, ext)
        if (file.exists(file_path)) {
          if (ext == ".rds") {
            return(readRDS(file_path))
          } else if (ext == ".csv") {
            return(read.csv(file_path, row.names = 1, check.names = FALSE, stringsAsFactors = FALSE))
          } else {
            return(read.delim(file_path, row.names = 1, check.names = FALSE, stringsAsFactors = FALSE))
          }
        }
      }
      stop(paste("Error: Could not find file for", base_name, "with .csv, .tsv, .txt, or .rds extension."))
    }
    
    # 1. Load feature table and metadata from the working directory
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    otu_data <- read_input_file("otu_table")
    sam_data <- read_input_file("sample_data")
    
    # Ensure sample_data is a data.frame
    sam_data <- as.data.frame(sam_data)
    
    # Adapt metadata column name to match the documented code's expected "quant_reading"
    if (!"quant_reading" %in% colnames(sam_data)) {
      # Look for common DNA concentration column names
      conc_cols <- grep("conc|quant|pico|reading|intensity", colnames(sam_data), ignore.case = TRUE, value = TRUE)
      if (length(conc_cols) > 0) {
        colnames(sam_data)[colnames(sam_data) == conc_cols[1]] <- "quant_reading"
        message("Renamed column '", conc_cols[1], "' to 'quant_reading' for compatibility.")
      } else {
        # Fallback: find the first numeric column
        numeric_cols <- sapply(sam_data, is.numeric)
        if (any(numeric_cols)) {
          col_to_rename <- names(which(numeric_cols)[1])
          colnames(sam_data)[colnames(sam_data) == col_to_rename] <- "quant_reading"
          message("Renamed numeric column '", col_to_rename, "' to 'quant_reading' for compatibility.")
        } else {
          stop("Error: No numeric DNA concentration column found in sample_data.")
        }
      }
    }
    
    # Ensure quant_reading is numeric
    sam_data\$quant_reading <- as.numeric(sam_data\$quant_reading)
    
    # Convert OTU data to matrix
    otu_mat <- as.matrix(otu_data)
    
    # Determine orientation of OTU table (taxa as rows vs. taxa as columns)
    samples_in_rows <- any(rownames(otu_mat) %in% rownames(sam_data))
    samples_in_cols <- any(colnames(otu_mat) %in% rownames(sam_data))
    
    if (!samples_in_rows && !samples_in_cols) {
      stop("Error: Sample identifiers in otu_table and sample_data do not match.")
    }
    
    # Construct phyloseq object
    OTU <- otu_table(otu_mat, taxa_are_rows = !samples_in_rows)
    SAMP <- sample_data(sam_data)
    ps <- phyloseq(OTU, SAMP)
    
    # Ensure there are enough taxa to perform the documented plotting step
    if (ntaxa(ps) < 3) {
      stop("Error: phyloseq object must contain at least 3 taxa/features.")
    }
    
    # 2. Run frequency-based contaminant identification using isContaminant
    contamdf.freq <- isContaminant(ps, method="frequency", conc="quant_reading")
    print("Head of contaminant data frame:")
    print(head(contamdf.freq))
    
    print("Contaminant classification table:")
    print(table(contamdf.freq\$contaminant))
    
    print("Indices of identified contaminants:")
    print(head(which(contamdf.freq\$contaminant)))
    
    # 3. Visualize frequency vs. concentration using plot_frequency
    p <- plot_frequency(ps, taxa_names(ps)[c(1,3)], conc="quant_reading") + 
      xlab("DNA Concentration (PicoGreen fluorescent intensity)")
    
    # 4. Filter out identified contaminants using prune_taxa
    ps.noncontam <- prune_taxa(!contamdf.freq\$contaminant, ps)
    
    # Save outputs to the working directory
    write.csv(contamdf.freq, "contaminants_frequency.csv", row.names = TRUE)
    ggsave("frequency_plot.pdf", plot = p, width = 8, height = 6)
    saveRDS(ps.noncontam, "ps_noncontam.rds")
    
    message("Pipeline completed successfully. Outputs saved: 'contaminants_frequency.csv', 'frequency_plot.pdf', 'ps_noncontam.rds'.")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # microbiome prevalence/abundance filtering (Callahan 2017 F1000).
    .pa_kept <- NA_real_
    for (.pa_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .pa_obj <- tryCatch(readRDS(.pa_rds), error = function(e) NULL)
      .pa_mat <- if (is.matrix(.pa_obj) || is.data.frame(.pa_obj)) .pa_obj else NULL
      if (!is.null(.pa_mat) && nrow(.pa_mat) > 50) {
        .pa_m <- suppressWarnings(as.matrix(.pa_mat))
        .pa_prev <- suppressWarnings(apply(.pa_m, 1, function(r) mean(as.numeric(r) > 0, na.rm = TRUE)))
        .pa_kept <- sum(is.finite(.pa_prev) & .pa_prev >= 0.05) / nrow(.pa_m); break
      }
    }
    .gates_by_label[["prevalence/abundance filtering"]] <- list(
      gate_row = "bioc_low_count_filtering",
      metric_name = "taxa_kept_fraction",
      metric_value = if (is.finite(.pa_kept)) round(.pa_kept, 4) else NA_real_,
      passes = isTRUE(is.finite(.pa_kept) && .pa_kept >= 0.3 && .pa_kept <= 0.7),
      status = if (is.finite(.pa_kept)) "computed (rows w/ >=5% prevalence / total)"
               else "not_computed (no abundance matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_DECONTAM_FREQUENCY_BASED_DECONTAMINATION",
      domain  = "bioconductor",
      declared_qc_steps = c("prevalence/abundance filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_DECONTAM_FREQUENCY_BASED_DECONTAMINATION":',
        paste0('    decontam: ', as.character(packageVersion('decontam')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_frequency_based_decontamination.csv versions.yml
    """
}

workflow BIOC_DECONTAM_FREQUENCY_BASED_DECONTAMINATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ otu_table, sample_data ] ]

    main:
    BIOC_DECONTAM_FREQUENCY_BASED_DECONTAMINATION(ch_input)

    emit:
    tables   = BIOC_DECONTAM_FREQUENCY_BASED_DECONTAMINATION.out.tables
    plots    = BIOC_DECONTAM_FREQUENCY_BASED_DECONTAMINATION.out.plots
    objects  = BIOC_DECONTAM_FREQUENCY_BASED_DECONTAMINATION.out.objects
    versions = BIOC_DECONTAM_FREQUENCY_BASED_DECONTAMINATION.out.versions
}
