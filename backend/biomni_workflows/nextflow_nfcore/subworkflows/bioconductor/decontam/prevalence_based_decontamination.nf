#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: decontam — prevalence_based_decontamination
// Identify and remove contaminating sequence features by comparing their presence/absence (prevalence) in true positive samples versus negative control samples.
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
//  * 2. [Input & Preparation] Define a logical variable indicating negative control samples
//  * 3. [Core Analysis] Run prevalence-based contaminant identification using isContaminant
//  * 4. [Core Analysis] Optionally run with an aggressive threshold (e.g., 0.5)
//  * 5. [Visualization & Output] Visualize prevalence in positive vs. negative samples

nextflow.enable.dsl = 2

process BIOC_DECONTAM_PREVALENCE_BASED_DECONTAMINATION {
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
          message(paste("Reading", file_path))
          if (ext == ".rds") {
            return(readRDS(file_path))
          } else if (ext == ".csv") {
            return(read.csv(file_path, row.names = 1, check.names = FALSE, stringsAsFactors = FALSE))
          } else {
            return(read.delim(file_path, row.names = 1, check.names = FALSE, stringsAsFactors = FALSE))
          }
        }
      }
      stop(paste("Required input file not found for base name:", base_name))
    }
    
    # 1. Load phyloseq object containing feature table and metadata
    message("Loading input files...")
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
    
    # Ensure OTU table is a matrix
    otu_mat <- as.matrix(otu_data)
    
    # Determine orientation of the OTU table (taxa as rows or columns)
    taxa_are_rows_guess <- TRUE
    sam_names <- rownames(sam_data)
    if (any(sam_names %in% colnames(otu_mat))) {
      taxa_are_rows_guess <- TRUE
    } else if (any(sam_names %in% rownames(otu_mat))) {
      taxa_are_rows_guess <- FALSE
    }
    
    # Construct phyloseq object
    OTU <- otu_table(otu_mat, taxa_are_rows = taxa_are_rows_guess)
    SAMP <- sample_data(sam_data)
    ps <- phyloseq(OTU, SAMP)
    
    # Standardize sample metadata to match the vignette's expected column names
    if (!"Sample_or_Control" %in% colnames(sample_data(ps))) {
      message("Mapping metadata columns to find negative controls...")
      possible_cols <- c("is.neg", "is_neg", "control", "is_control", "Control", "Type", "sample_type", "Sample_Type")
      found_col <- NULL
      for (col in possible_cols) {
        if (col %in% colnames(sample_data(ps))) {
          found_col <- col
          break
        }
      }
      
      if (!is.null(found_col)) {
        vals <- sample_data(ps)[[found_col]]
        if (is.logical(vals)) {
          sample_data(ps)\$Sample_or_Control <- ifelse(vals, "Control Sample", "True Sample")
        } else {
          is_ctrl <- grepl("control|neg|blank", tolower(as.character(vals)))
          sample_data(ps)\$Sample_or_Control <- ifelse(is_ctrl, "Control Sample", "True Sample")
        }
      } else {
        # Fallback: check for logical columns
        logical_cols <- sapply(as.data.frame(sample_data(ps)), is.logical)
        if (any(logical_cols)) {
          found_col <- names(logical_cols)[which(logical_cols)[1]]
          vals <- sample_data(ps)[[found_col]]
          sample_data(ps)\$Sample_or_Control <- ifelse(vals, "Control Sample", "True Sample")
        } else {
          # Fallback: check sample names for control keywords
          is_ctrl <- grepl("control|neg|blank|water", tolower(rownames(sample_data(ps))))
          sample_data(ps)\$Sample_or_Control <- ifelse(is_ctrl, "Control Sample", "True Sample")
        }
      }
    }
    
    # Verify that we have identified control samples
    num_controls <- sum(sample_data(ps)\$Sample_or_Control == "Control Sample")
    message(paste("Identified", num_controls, "negative control sample(s)."))
    if (num_controls == 0) {
      stop("No negative control samples could be identified. Please ensure your sample_data contains a column indicating controls.")
    }
    
    # 2. Define a logical variable indicating negative control samples
    sample_data(ps)\$is.neg <- sample_data(ps)\$Sample_or_Control == "Control Sample"
    
    # 3. Run prevalence-based contaminant identification using isContaminant (default threshold = 0.1)
    message("Running prevalence-based decontamination (threshold = 0.1)...")
    contamdf.prev <- isContaminant(ps, method="prevalence", neg="is.neg")
    print(table(contamdf.prev\$contaminant))
    print(head(which(contamdf.prev\$contaminant)))
    
    # Save default threshold results
    write.csv(contamdf.prev, "decontam_prevalence_results_threshold_01.csv", row.names = TRUE)
    
    # 4. Run with an aggressive threshold (0.5)
    message("Running prevalence-based decontamination (threshold = 0.5)...")
    contamdf.prev05 <- isContaminant(ps, method="prevalence", neg="is.neg", threshold=0.5)
    print(table(contamdf.prev05\$contaminant))
    
    # Save aggressive threshold results
    write.csv(contamdf.prev05, "decontam_prevalence_results_threshold_05.csv", row.names = TRUE)
    
    # 5. Visualize prevalence in positive vs. negative samples
    message("Generating prevalence visualization plot...")
    ps.pa <- transform_sample_counts(ps, function(abund) 1*(abund>0))
    ps.pa.neg <- prune_samples(sample_data(ps.pa)\$Sample_or_Control == "Control Sample", ps.pa)
    ps.pa.pos <- prune_samples(sample_data(ps.pa)\$Sample_or_Control == "True Sample", ps.pa)
    
    df.pa <- data.frame(pa.pos=taxa_sums(ps.pa.pos), pa.neg=taxa_sums(ps.pa.neg),
                        contaminant=contamdf.prev\$contaminant)
    
    p <- ggplot(data=df.pa, aes(x=pa.neg, y=pa.pos, color=contaminant)) + geom_point() +
      xlab("Prevalence (Negative Controls)") + ylab("Prevalence (True Samples)") +
      theme_minimal() +
      ggtitle("Prevalence of Sequence Features: Controls vs. True Samples")
    
    # Save plot to PDF
    ggsave("prevalence_plot.pdf", plot = p, width = 7, height = 6)
    
    # Save decontaminated phyloseq object (removing contaminants identified at default threshold)
    message("Saving decontaminated phyloseq object...")
    ps.noncontam <- prune_taxa(!contamdf.prev\$contaminant, ps)
    saveRDS(ps.noncontam, "decontaminated_phyloseq.rds")
    
    message("Pipeline completed successfully. Outputs written to working directory.")
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
      process = "BIOC_DECONTAM_PREVALENCE_BASED_DECONTAMINATION",
      domain  = "bioconductor",
      declared_qc_steps = c("prevalence/abundance filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_DECONTAM_PREVALENCE_BASED_DECONTAMINATION":',
        paste0('    decontam: ', as.character(packageVersion('decontam')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_prevalence_based_decontamination.csv versions.yml
    """
}

workflow BIOC_DECONTAM_PREVALENCE_BASED_DECONTAMINATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ otu_table, sample_data ] ]

    main:
    BIOC_DECONTAM_PREVALENCE_BASED_DECONTAMINATION(ch_input)

    emit:
    tables   = BIOC_DECONTAM_PREVALENCE_BASED_DECONTAMINATION.out.tables
    plots    = BIOC_DECONTAM_PREVALENCE_BASED_DECONTAMINATION.out.plots
    objects  = BIOC_DECONTAM_PREVALENCE_BASED_DECONTAMINATION.out.objects
    versions = BIOC_DECONTAM_PREVALENCE_BASED_DECONTAMINATION.out.versions
}
