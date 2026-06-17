#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: baySeq — standard_nb_rna_seq
// Identify differential expression in standard RNA-seq count data using the negative-binomial model.
// Input: simData
// Container: quay.io/biocontainers/bioconductor-bayseq:2.44.0--r45hdfd78af_0
// R packages: baySeq
// Bioconductor: 3.20 | R: 4.4
// Requires: baySeq
// Visualizations: plot (ggplot/base)
// QC: diagnostic MA/PCA QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create countData object
//  * 2. [Core Analysis] Estimate library sizes
//  * 3. [Core Analysis] Estimate priors using getPriors.NB
//  * 4. [Core Analysis] Calculate posterior likelihoods using getLikelihoods
//  * 5. [Core Analysis] Extract top candidates using topCounts

nextflow.enable.dsl = 2

process BIOC_BAYSEQ_STANDARD_NB_RNA_SEQ {
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
    .bm_deps <- c("baySeq")
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
    library(baySeq)
    library(parallel)
    
    # 1. Read user input file 'simData' from the working directory
    input_file <- NULL
    for (f in c("simData.csv", "simData.tsv", "simData.txt", "simData")) {
      if (file.exists(f)) {
        input_file <- f
        break
      }
    }
    
    if (is.null(input_file)) {
      stop("Error: Input file 'simData' (with .csv, .tsv, .txt extension or no extension) not found in the working directory.")
    }
    
    if (grepl("\\\\.csv\$", input_file)) {
      simData_df <- read.csv(input_file, row.names = 1, check.names = FALSE)
    } else if (grepl("\\\\.tsv\$", input_file)) {
      simData_df <- read.delim(input_file, row.names = 1, check.names = FALSE)
    } else {
      simData_df <- read.table(input_file, header = TRUE, row.names = 1, check.names = FALSE)
    }
    simData <- as.matrix(simData_df)
    
    # Set up parallel cluster
    cl <- makeCluster(2)
    
    # Define replicates and groups based on the input data columns
    n_cols <- ncol(simData)
    if (n_cols == 10) {
      replicates <- c("simA", "simA", "simA", "simA", "simA",
                      "simB", "simB", "simB", "simB", "simB")
      groups <- list(NDE = c(1,1,1,1,1,1,1,1,1,1),
                     DE = c(1,1,1,1,1,2,2,2,2,2))
    } else {
      half <- ceiling(n_cols / 2)
      replicates <- c(rep("simA", half), rep("simB", n_cols - half))
      groups <- list(
        NDE = rep(1, n_cols),
        DE = c(rep(1, half), rep(2, n_cols - half))
      )
    }
    
    # === DOCUMENTED CODE ===
    CD <- new("countData", data = simData, replicates = replicates, groups = groups)
    libsizes(CD) <- getLibsizes(CD)
    CD <- getPriors.NB(CD, samplesize = 1000, estimation = "QL", cl = cl)
    CD <- getLikelihoods(CD, cl = cl, bootStraps = 3, verbose = FALSE)
    topCounts(CD, group = "DE")
    # === END DOCUMENTED CODE ===
    
    # Save outputs
    # 1. CSV of top counts
    de_results <- topCounts(CD, group = "DE", number = nrow(CD))
    write.csv(de_results, file = "differential_expression_results.csv", row.names = TRUE)
    
    # 2. RDS object
    saveRDS(CD, file = "baySeq_countData_object.rds")
    
    # 3. PDF plots
    pdf("baySeq_plots.pdf", width = 7, height = 7)
    tryCatch({
      plotMA.CD(CD, samplesA = "simA", samplesB = "simB")
    }, error = function(e) {
      warning("Could not generate MA plot: ", e\$message)
    })
    tryCatch({
      plotPosteriors(CD, group = "DE")
    }, error = function(e) {
      warning("Could not generate Posteriors plot: ", e\$message)
    })
    dev.off()
    
    # Clean up cluster
    if(!is.null(cl)) stopCluster(cl)
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # diagnostic MA/PCA QC — PC1 variance explained on any large matrix.
    # Pass when PC1 > 10% (Risso 2014 RUV-seq diagnostic).
    .pca_pc1 <- NA_real_; .pca_files <- character(0)
    for (.pca_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .pca_obj <- tryCatch(readRDS(.pca_rds), error = function(e) NULL)
      .pca_mat <- if (is.matrix(.pca_obj) || is.data.frame(.pca_obj)) .pca_obj else NULL
      if (!is.null(.pca_mat) && ncol(.pca_mat) >= 3 && nrow(.pca_mat) >= 100) {
        .pca_m <- suppressWarnings(as.matrix(.pca_mat))
        .pca_kept <- apply(.pca_m, 1, function(r) all(is.finite(r)) && var(r) > 0)
        if (sum(.pca_kept) >= 50) {
          .pca_fit <- tryCatch(prcomp(t(.pca_m[.pca_kept, , drop = FALSE])), error = function(e) NULL)
          if (!is.null(.pca_fit)) {
            .pca_vars <- (.pca_fit\$sdev^2) / sum(.pca_fit\$sdev^2)
            .pca_pc1 <- round(.pca_vars[1] * 100, 2); .pca_files <- c(.pca_files, .pca_rds); break
          }
        }
      }
    }
    .gates_by_label[["diagnostic MA/PCA QC"]] <- list(
      gate_row = "bioc_diagnostic_ma_pca_qc",
      metric_name = "pc1_var_explained",
      metric_value = .pca_pc1,
      passes = isTRUE(is.finite(.pca_pc1) && .pca_pc1 > 10),
      status = if (is.finite(.pca_pc1)) paste0("computed (PC1=", .pca_pc1, "%)")
               else "not_computed (no large numeric matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_BAYSEQ_STANDARD_NB_RNA_SEQ",
      domain  = "bioconductor",
      declared_qc_steps = c("diagnostic MA/PCA QC"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_BAYSEQ_STANDARD_NB_RNA_SEQ":',
        paste0('    baySeq: ', as.character(packageVersion('baySeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_nb_rna_seq.csv versions.yml
    """
}

workflow BIOC_BAYSEQ_STANDARD_NB_RNA_SEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ simData ] ]

    main:
    BIOC_BAYSEQ_STANDARD_NB_RNA_SEQ(ch_input)

    emit:
    tables   = BIOC_BAYSEQ_STANDARD_NB_RNA_SEQ.out.tables
    plots    = BIOC_BAYSEQ_STANDARD_NB_RNA_SEQ.out.plots
    objects  = BIOC_BAYSEQ_STANDARD_NB_RNA_SEQ.out.objects
    versions = BIOC_BAYSEQ_STANDARD_NB_RNA_SEQ.out.versions
}
