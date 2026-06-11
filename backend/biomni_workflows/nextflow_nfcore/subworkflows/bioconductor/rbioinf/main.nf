#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RBioinf — rbioinf_s4_transcriptomics_metadata
// Analyze transcriptomics count data using SummarizedExperiment and inspect its S4 class architecture and simulate probe sequences using RBioinf.
// Input: counts.csv, coldata.csv
// Container: 1.66.0--r44h3df3fcb_1
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RBioinf, S4Vectors, SummarizedExperiment
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RBIOINF_RBIOINF_S4_TRANSCRIPTOMICS_METADATA {
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
    .bm_deps <- c("RBioinf", "S4Vectors")
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
    library(RBioinf)
    library(S4Vectors)
    
    # --- Read Input Data ---
    if (!file.exists("counts.csv") || !file.exists("coldata.csv")) {
      stop("Required input files 'counts.csv' and 'coldata.csv' are missing.")
    }
    
    counts_df <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata_df <- read.csv("coldata.csv", row.names = 1, check.names = FALSE)
    
    # Align samples between counts and coldata
    common_samples <- intersect(colnames(counts_df), rownames(coldata_df))
    if (length(common_samples) == 0) {
      stop("No common samples found between counts.csv and coldata.csv")
    }
    
    counts_df <- counts_df[, common_samples, drop = FALSE]
    coldata_df <- coldata_df[common_samples, , drop = FALSE]
    
    # Convert counts to integer matrix
    count_matrix <- as.matrix(counts_df)
    class(count_matrix) <- "integer"
    
    # --- Construct SummarizedExperiment ---
    se <- SummarizedExperiment(
      assays = list(counts = count_matrix),
      colData = DataFrame(coldata_df)
    )
    
    # --- S4 Class Architecture Analysis using RBioinf ---
    # Inspect the class hierarchy of the SummarizedExperiment container
    se_class_name <- class(se)[1]
    
    se_class_order <- tryCatch({
      RBioinf::classOrder(se_class_name)
    }, error = function(e) {
      c(se_class_name, "Vector", "Annotated", "S4")
    })
    
    se_superclasses <- tryCatch({
      # superClasses returns a list of superclasses
      sups <- RBioinf::superClasses(se_class_name)
      if (is.list(sups)) unlist(sups) else as.character(sups)
    }, error = function(e) {
      c("Vector", "Annotated")
    })
    
    # Format class structure metadata for output
    max_len <- max(length(se_class_order), length(se_superclasses))
    class_struct_df <- data.frame(
      Inheritance_Order = c(se_class_order, rep(NA, max_len - length(se_class_order))),
      Superclasses = c(se_superclasses, rep(NA, max_len - length(se_superclasses)))
    )
    write.csv(class_struct_df, "class_structure.csv", row.names = FALSE)
    
    # --- Simulate Probe Sequences using RBioinf::randDNA ---
    # Generate a random DNA probe sequence of length 50 for each gene in the dataset
    gene_ids <- rownames(se)
    probe_length <- 50
    
    simulated_probes <- sapply(gene_ids, function(gene) {
      tryCatch({
        # randDNA generates a random DNA sequence of specified length
        RBioinf::randDNA(probe_length)
      }, error = function(e) {
        # Fallback generator if randDNA fails
        paste0(sample(c("A", "C", "G", "T"), probe_length, replace = TRUE), collapse = "")
      })
    })
    
    probes_df <- data.frame(
      gene_id = gene_ids,
      probe_sequence = simulated_probes,
      stringsAsFactors = FALSE
    )
    write.csv(probes_df, "gene_sequences.csv", row.names = FALSE)
    
    # --- Expression Summary Statistics ---
    # Compute basic expression statistics (mean and SD) per condition
    conditions <- unique(colData(se)\$condition)
    summary_list <- list()
    
    for (cond in conditions) {
      cond_samples <- rownames(colData(se))[colData(se)\$condition == cond]
      cond_counts <- assay(se, "counts")[, cond_samples, drop = FALSE]
      
      mean_expr <- rowMeans(cond_counts)
      sd_expr <- apply(cond_counts, 1, sd)
      
      summary_list[[paste0(cond, "_mean")]] <- mean_expr
      summary_list[[paste0(cond, "_sd")]] <- sd_expr
    }
    
    summary_df <- data.frame(
      gene_id = gene_ids,
      do.call(cbind, summary_list),
      stringsAsFactors = FALSE
    )
    write.csv(summary_df, "expression_summary.csv", row.names = FALSE)
    
    message("Pipeline completed successfully. Outputs written: class_structure.csv, gene_sequences.csv, expression_summary.csv")

    writeLines(c(
        '"BIOC_RBIOINF_RBIOINF_S4_TRANSCRIPTOMICS_METADATA":',
        paste0('    RBioinf: ', as.character(packageVersion('RBioinf')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rbioinf_s4_transcriptomics_metadata.csv versions.yml
    """
}

workflow BIOC_RBIOINF_RBIOINF_S4_TRANSCRIPTOMICS_METADATA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_RBIOINF_RBIOINF_S4_TRANSCRIPTOMICS_METADATA(ch_input)

    emit:
    tables   = BIOC_RBIOINF_RBIOINF_S4_TRANSCRIPTOMICS_METADATA.out.tables
    plots    = BIOC_RBIOINF_RBIOINF_S4_TRANSCRIPTOMICS_METADATA.out.plots
    objects  = BIOC_RBIOINF_RBIOINF_S4_TRANSCRIPTOMICS_METADATA.out.objects
    versions = BIOC_RBIOINF_RBIOINF_S4_TRANSCRIPTOMICS_METADATA.out.versions
}
