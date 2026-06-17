#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cytofqc — step_by_step_qc_modeling
// Manually run step-by-step initial classification and SVM labeling for each event type (beads, debris, doublets, dead cells).
// Input: raw_cytof.fcs
// Container: quay.io/biocontainers/bioconductor-cytofqc:1.6.0--r44hdfd78af_0
// R packages: CATALYST, SingleCellExperiment, cytofQC, ggplot2, gridExtra
// Bioconductor: 3.20 | R: 4.4
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)
// QC: doublet detection QC

nextflow.enable.dsl = 2

process BIOC_CYTOFQC_STEP_BY_STEP_QC_MODELING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-cytofqc:1.6.0--r44hdfd78af_0"

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
    .bm_deps <- c("CATALYST", "SingleCellExperiment", "cytofQC", "ggplot2", "gridExtra")
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
    library(cytofQC)
    library(CATALYST)
    library(SingleCellExperiment)
    library(ggplot2)
    library(gridExtra)
    
    # --- Read FCS data and define QC channels using readCytof ---
    f <- "raw_cytof.fcs"
    if (!file.exists(f)) {
      stop("Required input file 'raw_cytof.fcs' not found in the working directory.")
    }
    
    x <- readCytof(f, 
                   beads = c("Bead"),
                   dna = c("DNA1", "DNA2"),
                   event_length = "Event_length",
                   viability = "Live_Dead",
                   gaussian = c("Center", "Offset", "Width", "Residual"))
    
    # --- Initialize and label beads using initialBead and svmLabel ---
    x <- initialBead(x)
    x <- svmLabel(x, type = "bead", n = 500)
    
    # --- Initialize and label debris using initialDebris and ---
    x <- initialDebris(x)
    x <- svmLabel(x, type = "debris", n = 500)
    
    # --- Initialize and label doublets using initialDoublet and ---
    x <- initialDoublet(x)
    x <- svmLabel(x, type = "doublet", n = 500)
    
    # --- Initialize and label dead cells using initialDead and ---
    # Wrapped in tryCatch because if there are fewer than 100 dead cells, 
    # a classification model cannot be built and may throw an error or warning.
    x <- tryCatch({
      x <- initialDead(x)
      x <- svmLabel(x, type = "dead", n = 500)
      x
    }, error = function(e) {
      warning("Dead cell labeling skipped or failed: ", e\$message)
      x
    })
    
    # --- Save Outputs ---
    
    # Save the SingleCellExperiment object
    saveRDS(x, file = "cytofQC_labeled_sce.rds")
    
    # Create and save a summary table of the labels
    label_summary <- as.data.frame(table(label(x), useNA = "ifany"))
    colnames(label_summary) <- c("QC_Label", "Count")
    write.csv(label_summary, file = "qc_labels_summary.csv", row.names = FALSE)
    
    # Create and save a detailed table of labels, scores, and probabilities
    detailed_df <- data.frame(
      Label = label(x),
      Bead_Score = scores(x, type = "bead"),
      Debris_Score = scores(x, type = "debris"),
      Doublet_Score = scores(x, type = "doublet"),
      Dead_Score = scores(x, type = "dead"),
      Bead_Prob = probs(x, type = "bead"),
      Debris_Prob = probs(x, type = "debris"),
      Doublet_Prob = probs(x, type = "doublet"),
      Dead_Prob = probs(x, type = "dead")
    )
    write.csv(detailed_df, file = "qc_labels_detailed.csv", row.names = FALSE)
    
    # Generate and save diagnostic plots
    pdf("qc_plots.pdf", width = 8, height = 10)
    
    # Histograms of scores
    p_bead <- cytofHist(scores(x, type = 'bead'), label(x), title = "Bead score")
    p_debris <- cytofHist(scores(x, type = 'debris'), label(x), title = "Debris score")
    p_doublet <- cytofHist(scores(x, type = 'doublet'), label(x), title = "Doublet score")
    
    grid.arrange(p_bead, p_debris, p_doublet, ncol = 1)
    
    # Density histograms
    p_bead_dens <- cytofHist(scores(x, type = 'bead'), label(x), type = "density", title = "Bead score (Density)")
    p_debris_dens <- cytofHist(scores(x, type = 'debris'), label(x), type = "density", title = "Debris score (Density)")
    p_doublet_dens <- cytofHist(scores(x, type = 'doublet'), label(x), type = "density", title = "Doublet score (Density)")
    
    grid.arrange(p_bead_dens, p_debris_dens, p_doublet_dens, ncol = 1)
    
    dev.off()
    
    cat("Pipeline completed successfully. Outputs saved to 'cytofQC_labeled_sce.rds', 'qc_labels_summary.csv', 'qc_labels_detailed.csv', and 'qc_plots.pdf'.\n")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # doublet detection — SCE/Seurat with doublet column; pass: rate ≤ 10%.
    .dbl_rate <- NA_real_
    for (.dbl_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .dbl_obj <- tryCatch(readRDS(.dbl_rds), error = function(e) NULL)
      .dbl_calls <- NULL
      if (!is.null(.dbl_obj)) {
        if (inherits(.dbl_obj, "SingleCellExperiment")) {
          .dbl_cd <- tryCatch(colData(.dbl_obj), error = function(e) NULL)
          if (!is.null(.dbl_cd)) {
            .dbl_col <- intersect(c("doublet_class","scDblFinder.class","DoubletFinder","is_doublet"), colnames(.dbl_cd))
            if (length(.dbl_col) > 0) .dbl_calls <- as.character(.dbl_cd[[.dbl_col[1]]])
          }
        } else if (inherits(.dbl_obj, "Seurat")) {
          .dbl_md <- tryCatch(.dbl_obj@meta.data, error = function(e) NULL)
          if (!is.null(.dbl_md)) {
            .dbl_col <- intersect(c("DoubletFinder","scDblFinder.class","doublet_class","is_doublet"), colnames(.dbl_md))
            if (length(.dbl_col) > 0) .dbl_calls <- as.character(.dbl_md[[.dbl_col[1]]])
          }
        }
      }
      if (!is.null(.dbl_calls) && length(.dbl_calls) > 0) {
        .dbl_rate <- round(mean(grepl("doublet|TRUE|1", .dbl_calls, ignore.case = TRUE), na.rm = TRUE), 4); break
      }
    }
    .gates_by_label[["doublet detection QC"]] <- list(
      gate_row = "bioc_doublet_detection_qc",
      metric_name = "doublet_rate",
      metric_value = .dbl_rate,
      passes = isTRUE(is.finite(.dbl_rate) && .dbl_rate <= 0.10),
      status = if (is.finite(.dbl_rate)) "computed (SCE colData / Seurat meta.data doublet col)"
               else "not_computed (no SCE/Seurat with doublet column present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_CYTOFQC_STEP_BY_STEP_QC_MODELING",
      domain  = "bioconductor",
      declared_qc_steps = c("doublet detection QC"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_CYTOFQC_STEP_BY_STEP_QC_MODELING":',
        paste0('        cytofqc: ', as.character(packageVersion("cytofqc")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_step_by_step_qc_modeling.csv versions.yml
    """
}

workflow BIOC_CYTOFQC_STEP_BY_STEP_QC_MODELING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_cytof.fcs ] ]

    main:
    BIOC_CYTOFQC_STEP_BY_STEP_QC_MODELING(ch_input)

    emit:
    tables   = BIOC_CYTOFQC_STEP_BY_STEP_QC_MODELING.out.tables
    plots    = BIOC_CYTOFQC_STEP_BY_STEP_QC_MODELING.out.plots
    objects  = BIOC_CYTOFQC_STEP_BY_STEP_QC_MODELING.out.objects
    versions = BIOC_CYTOFQC_STEP_BY_STEP_QC_MODELING.out.versions
}
