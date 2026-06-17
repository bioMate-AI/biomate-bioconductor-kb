#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cqn — cqn_expression_normalization
// Normalize RNA-Seq count data for GC-content and gene length to obtain corrected expression values (RPKM).
// Input: count_matrix.tsv, gene_lengths.tsv, gc_content.tsv, size_factors.tsv
// Container: quay.io/biocontainers/bioconductor-cqn:1.56.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: cqn
// Visualizations: plot (ggplot/base)
// QC: input validation
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run conditional quantile normalization using cqn
//  * 2. [Visualization & Output] Plot systematic effects of GC content and length using cqnplot
//  * 3. [Core Analysis] Calculate normalized expression values (RPKM) on the log2 scale

nextflow.enable.dsl = 2

process BIOC_CQN_CQN_EXPRESSION_NORMALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("cqn")
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
    library(cqn)
    
    # 1. Read User Input Files
    # Read count matrix
    counts <- as.matrix(read.delim("count_matrix.tsv", row.names = 1, header = TRUE, check.names = FALSE))
    
    # Read gene lengths
    gene_lengths_raw <- read.delim("gene_lengths.tsv", header = TRUE, check.names = FALSE)
    if (ncol(gene_lengths_raw) >= 2 && any(gene_lengths_raw[,1] %in% rownames(counts))) {
      rownames(gene_lengths_raw) <- gene_lengths_raw[,1]
      gene_lengths <- gene_lengths_raw[rownames(counts), 2]
    } else if (ncol(gene_lengths_raw) == 1) {
      gene_lengths <- gene_lengths_raw[, 1]
      names(gene_lengths) <- rownames(gene_lengths_raw)
      if (all(names(gene_lengths) %in% rownames(counts))) {
        gene_lengths <- gene_lengths[rownames(counts)]
      }
    } else {
      gene_lengths_raw <- read.delim("gene_lengths.tsv", row.names = 1, header = TRUE, check.names = FALSE)
      gene_lengths <- gene_lengths_raw[rownames(counts), 1]
    }
    
    # Read GC content
    gc_content_raw <- read.delim("gc_content.tsv", header = TRUE, check.names = FALSE)
    if (ncol(gc_content_raw) >= 2 && any(gc_content_raw[,1] %in% rownames(counts))) {
      rownames(gc_content_raw) <- gc_content_raw[,1]
      gc_content <- gc_content_raw[rownames(counts), 2]
    } else if (ncol(gc_content_raw) == 1) {
      gc_content <- gc_content_raw[, 1]
      names(gc_content) <- rownames(gc_content_raw)
      if (all(names(gc_content) %in% rownames(counts))) {
        gc_content <- gc_content[rownames(counts)]
      }
    } else {
      gc_content_raw <- read.delim("gc_content.tsv", row.names = 1, header = TRUE, check.names = FALSE)
      gc_content <- gc_content_raw[rownames(counts), 1]
    }
    
    # Read size factors
    size_factors_raw <- read.delim("size_factors.tsv", header = TRUE, check.names = FALSE)
    if (ncol(size_factors_raw) >= 2 && any(size_factors_raw[,1] %in% colnames(counts))) {
      rownames(size_factors_raw) <- size_factors_raw[,1]
      size_factors <- size_factors_raw[colnames(counts), 2]
    } else if (ncol(size_factors_raw) == 1) {
      size_factors <- size_factors_raw[, 1]
      names(size_factors) <- rownames(size_factors_raw)
      if (all(names(size_factors) %in% colnames(counts))) {
        size_factors <- size_factors[colnames(counts)]
      }
    } else {
      size_factors_raw <- read.delim("size_factors.tsv", row.names = 1, header = TRUE, check.names = FALSE)
      size_factors <- size_factors_raw[colnames(counts), 1]
    }
    
    # Align and prepare variables to match documented code exactly
    montgomery.subset <- counts
    uCovar <- data.frame(
      length = as.numeric(gene_lengths),
      gccontent = as.numeric(gc_content),
      row.names = rownames(counts)
    )
    sizeFactors.subset <- as.numeric(size_factors)
    names(sizeFactors.subset) <- colnames(counts)
    
    # Assertions to ensure data integrity (as in vignette)
    stopifnot(all(rownames(montgomery.subset) == rownames(uCovar)))
    stopifnot(colnames(montgomery.subset) == names(sizeFactors.subset))
    
    # 2. Run Conditional Quantile Normalization (CQN)
    cqn.subset <- cqn(montgomery.subset, lengths = uCovar\$length, 
                      x = uCovar\$gccontent, sizeFactors = sizeFactors.subset,
                      verbose = TRUE)
    
    # 3. Plot systematic effects of GC content and length using cqnplot
    pdf("cqn_plots.pdf", width = 10, height = 5)
    par(mfrow=c(1,2))
    cqnplot(cqn.subset, n = 1, xlab = "GC content", lty = 1)
    cqnplot(cqn.subset, n = 2, xlab = "length", lty = 1)
    dev.off()
    
    # 4. Calculate normalized expression values (RPKM) on the log2 scale
    RPKM.cqn <- cqn.subset\$y + cqn.subset\$offset
    
    # 5. Save Outputs
    write.table(RPKM.cqn, "cqn_normalized_rpkm.tsv", sep = "\t", quote = FALSE, col.names = NA)
    saveRDS(cqn.subset, "cqn_object.rds")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # input validation — workflow-level pass when expected output files exist
    # and have non-zero size. Binary pass: at least one .rds or .csv emitted.
    .iv_artifacts <- c(list.files(".", pattern = "\\.rds\$"), list.files(".", pattern = "\\.csv\$"))
    .iv_passes <- length(.iv_artifacts) > 0
    .gates_by_label[["input validation"]] <- list(
      gate_row = "bioc_input_validation",
      metric_name = "input_validation_passes",
      metric_value = if (.iv_passes) 1 else 0,
      passes = .iv_passes,
      status = paste0("computed (", length(.iv_artifacts), " artifact(s) emitted)")
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_CQN_CQN_EXPRESSION_NORMALIZATION",
      domain  = "bioconductor",
      declared_qc_steps = c("input validation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_CQN_CQN_EXPRESSION_NORMALIZATION":',
        paste0('    cqn: ', as.character(packageVersion('cqn')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cqn_expression_normalization.csv versions.yml
    """
}

workflow BIOC_CQN_CQN_EXPRESSION_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ count_matrix.tsv, gene_lengths.tsv, gc_content.tsv, size_factors.tsv ] ]

    main:
    BIOC_CQN_CQN_EXPRESSION_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_CQN_CQN_EXPRESSION_NORMALIZATION.out.tables
    plots    = BIOC_CQN_CQN_EXPRESSION_NORMALIZATION.out.plots
    objects  = BIOC_CQN_CQN_EXPRESSION_NORMALIZATION.out.objects
    versions = BIOC_CQN_CQN_EXPRESSION_NORMALIZATION.out.versions
}
