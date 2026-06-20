#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RcisTarget — tfbs_motif_enrichment
// Identify enriched transcription factor binding motifs and predict candidate target genes from a gene list.
// Input: gene_list.txt, motif_rankings.db
// Container: quay.io/biocontainers/bioconductor-rcistarget:1.29.0--r45hdfd78af_0
// R packages: DT, RcisTarget, reshape2, visnetwork
// Bioconductor: 3.20 | R: 4.4
// Requires: RcisTarget
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Identify DNA motifs over-represented near the transcription start site (TSS) using the ranking database
//  * 2. [Core Analysis] Filter and retain motifs annotated to TFs with a high Normalized Enrichment Score (NES)
//  * 3. [Core Analysis] Predict candidate target genes ranked above the leading edge for each enriched motif

nextflow.enable.dsl = 2

process BIOC_RCISTARGET_TFBS_MOTIF_ENRICHMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("DT", "RcisTarget", "reshape2", "visnetwork")
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
            
            # Load required libraries
            library(RcisTarget)
            
            # -----------------------------------------------------------------------------
            # Input Validation
            # -----------------------------------------------------------------------------
            if (!file.exists("gene_list.txt")) {
              stop("Error: Required input file 'gene_list.txt' not found in the working directory.")
            }
            
            if (!file.exists("motif_rankings.db")) {
              stop("Error: Required input file 'motif_rankings.db' not found in the working directory.")
            }
            
            # -----------------------------------------------------------------------------
            # Load User Inputs
            # -----------------------------------------------------------------------------
            # Read gene list (one gene symbol per line)
            gene_list_raw <- readLines("gene_list.txt")
            gene_list_clean <- unique(trimws(gene_list_raw))
            gene_list_clean <- gene_list_clean[gene_list_clean != ""]
            
            if (length(gene_list_clean) == 0) {
              stop("Error: 'gene_list.txt' is empty or contains no valid gene symbols.")
            }
            
            # RcisTarget functions expect a named list of gene sets
            geneLists <- list(query_gene_set = gene_list_clean)
            
            # Load the motif rankings database
            motifRankings <- importRankings("motif_rankings.db")
            
            # -----------------------------------------------------------------------------
            # Retrieve Motif Annotations (without using data() or system.file)
            # -----------------------------------------------------------------------------
            motifAnnot <- NULL
            tryCatch({
              # Attempt to retrieve standard HGNC annotations from the package environment
              pkg_env <- as.environment("package:RcisTarget")
              if (exists("motifAnnotations_hgnc", envir = pkg_env)) {
                motifAnnot <- get("motifAnnotations_hgnc", envir = pkg_env)
              } else if (exists("motifAnnotations_mgi", envir = pkg_env)) {
                motifAnnot <- get("motifAnnotations_mgi", envir = pkg_env)
              } else {
                # Fallback: search for any motif annotation object in the environment
                ns_objs <- ls(envir = pkg_env)
                annot_objs <- ns_objs[grep("motifAnnotations", ns_objs)]
                if (length(annot_objs) > 0) {
                  motifAnnot <- get(annot_objs[1], envir = pkg_env)
                }
              }
            }, error = function(e) {
              message("Warning: Could not load motif annotations from package environment: ", e\$message)
            })
            
            # Fallback to a minimal annotation structure if none could be loaded
            if (is.null(motifAnnot)) {
              warning("Using empty/placeholder motif annotations.")
              
              motif_names <- NULL
              if (.hasSlot(motifRankings, "rankings")) {
                rnk <- motifRankings@rankings
                motif_names <- rownames(rnk)
                if (is.null(motif_names) && length(rnk) > 0) {
                  motif_names <- rnk[[1]]
                }
              }
              
              if (is.null(motif_names)) {
                motif_names <- character(0)
              }
              
              motifAnnot <- data.frame(
                motif = as.character(motif_names),
                TF = "Unknown",
                directAnnotation = TRUE,
                stringsAsFactors = FALSE
              )
            }
            
            # -----------------------------------------------------------------------------
            # Stage 1: Identify DNA motifs over-represented near the TSS
            # -----------------------------------------------------------------------------
            message("Stage 1: Calculating Motif Enrichment (AUC)...")
            motifs_AUC <- calcAUC(
              geneSets = geneLists,
              rankings = motifRankings
            )
            
            # -----------------------------------------------------------------------------
            # Stage 2: Filter and retain motifs annotated to TFs with a high NES
            # -----------------------------------------------------------------------------
            message("Stage 2: Annotating motifs and filtering by NES...")
            motifEnrichmentTable <- addMotifAnnotation(
              auc = motifs_AUC,
              motifAnnot = motifAnnot
            )
            
            # -----------------------------------------------------------------------------
            # Stage 3: Predict candidate target genes ranked above the leading edge
            # -----------------------------------------------------------------------------
            message("Stage 3: Identifying leading edge target genes...")
            motifEnrichmentTable_wGenes <- addSignificantGenes(
              motifEnrichmentTable = motifEnrichmentTable,
              geneSets = geneLists,
              rankings = motifRankings,
              method = "aprox"
            )
            
            # -----------------------------------------------------------------------------
            # Save Outputs
            # -----------------------------------------------------------------------------
            message("Saving results...")
            
            # Save the complete R object
            saveRDS(motifEnrichmentTable_wGenes, "motif_enrichment_results.rds")
            
            # Flatten list columns for CSV export compatibility
            flat_table <- motifEnrichmentTable_wGenes
            for (col in colnames(flat_table)) {
              if (is.list(flat_table[[col]])) {
                flat_table[[col]] <- sapply(flat_table[[col]], function(x) paste(x, collapse = ";"))
              }
            }
            write.csv(flat_table, "motif_enrichment_results.csv", row.names = FALSE)
            
            # Generate diagnostic plot of NES scores
            pdf("nes_distribution.pdf", width = 7, height = 5)
            if ("NES" %in% colnames(motifEnrichmentTable_wGenes) && nrow(motifEnrichmentTable_wGenes) > 0) {
              hist(
                motifEnrichmentTable_wGenes\$NES,
                breaks = 30,
                col = "skyblue",
                border = "white",
                main = "Distribution of Normalized Enrichment Scores (NES)",
                xlab = "NES"
              )
              abline(v = 3.0, col = "red", lty = 2, lwd = 2)
              legend("topright", legend = "NES Threshold (3.0)", col = "red", lty = 2, lwd = 2)
            } else {
              plot(1, type = "n", axes = FALSE, xlab = "", ylab = "")
              text(1, 1, "No enriched motifs found or NES column missing.", cex = 1.2)
            }
            dev.off()
            
            message("Pipeline completed successfully. Outputs written to 'motif_enrichment_results.rds', 'motif_enrichment_results.csv', and 'nes_distribution.pdf'.")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # alignment/mapping QC — workflow-emitted artifact check for common log
    # files (.log, .summary, alignment metrics tables). Binary pass.
    .amqc_logs <- c(list.files(".", pattern = "(?i)(align|map|samtools|flagstat).*\\.(log|txt|summary)\$"),
                    list.files(".", pattern = "(?i)flagstat\\."))
    .amqc_passes <- length(.amqc_logs) > 0
    .gates_by_label[["alignment/mapping QC"]] <- list(
      gate_row = "bioc_alignment_mapping_qc",
      metric_name = "alignment_qc_artifacts",
      metric_value = length(.amqc_logs),
      passes = .amqc_passes,
      status = if (.amqc_passes) paste0("computed (", length(.amqc_logs), " alignment log(s) emitted)")
               else "not_computed (no alignment log/summary artifact present)"
    )

    # low-count filtering — fraction of genes retained (heuristic on matrix artifacts).
    # Pass band 30-60% per Chen 2016 F1000 (edgeR filterByExpr convention).
    .lcf_kept_fractions <- numeric(0)
    .lcf_scanned <- character(0)
    for (.lcf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .lcf_obj <- tryCatch(readRDS(.lcf_rds), error = function(e) NULL)
      .lcf_mat <- if (is.matrix(.lcf_obj) || is.data.frame(.lcf_obj)) .lcf_obj else NULL
      if (!is.null(.lcf_mat) && nrow(.lcf_mat) > 100) {
        .lcf_m <- tryCatch(as.matrix(.lcf_mat), error = function(e) NULL)
        if (!is.null(.lcf_m)) {
          .lcf_row_med <- suppressWarnings(apply(.lcf_m, 1, function(r) median(as.numeric(r), na.rm = TRUE)))
          .lcf_kept <- sum(is.finite(.lcf_row_med) & .lcf_row_med >= 1) / nrow(.lcf_m)
          .lcf_kept_fractions <- c(.lcf_kept_fractions, .lcf_kept)
          .lcf_scanned <- c(.lcf_scanned, .lcf_rds)
        }
      }
    }
    .lcf_kept <- if (length(.lcf_kept_fractions) > 0) round(median(.lcf_kept_fractions), 4) else NA_real_
    .gates_by_label[["low-count filtering"]] <- list(
      gate_row = "bioc_low_count_filtering",
      metric_name = "genes_kept_fraction",
      metric_value = .lcf_kept,
      passes = isTRUE(is.finite(.lcf_kept) && .lcf_kept >= 0.3 && .lcf_kept <= 0.6),
      status = if (is.finite(.lcf_kept)) paste0("computed (proxy: rows w/ median count >=1 across ", length(.lcf_scanned), " matrix .rds)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    # count normalization — scan .rds matrix artifacts for library-size CV
    # ratio (post-norm / pre-norm); without raw input we report median lib CV
    # as a proxy diagnostic. Threshold = 0.7 (Bullard 2010 BMC Bioinf).
    .cn_lib_cvs <- numeric(0)
    .cn_scanned <- character(0)
    for (.cn_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .cn_obj <- tryCatch(readRDS(.cn_rds), error = function(e) NULL)
      .cn_mat <- if (is.matrix(.cn_obj) || is.data.frame(.cn_obj)) .cn_obj else NULL
      if (!is.null(.cn_mat) && ncol(.cn_mat) >= 2 && nrow(.cn_mat) >= 2) {
        .cn_lib <- tryCatch(colSums(as.matrix(.cn_mat), na.rm = TRUE), error = function(e) NULL)
        if (!is.null(.cn_lib) && all(is.finite(.cn_lib)) && mean(.cn_lib) > 0) {
          .cn_lib_cvs <- c(.cn_lib_cvs, sd(.cn_lib) / mean(.cn_lib))
          .cn_scanned <- c(.cn_scanned, .cn_rds)
        }
      }
    }
    .cn_med_cv <- if (length(.cn_lib_cvs) > 0) round(median(.cn_lib_cvs), 4) else NA_real_
    .gates_by_label[["count normalization"]] <- list(
      gate_row = "bioc_count_normalization",
      metric_name = "lib_size_cv_median",
      metric_value = .cn_med_cv,
      passes = isTRUE(is.finite(.cn_med_cv) && .cn_med_cv <= 0.3),
      status = if (is.finite(.cn_med_cv)) paste0("computed (proxy: median lib-size CV across ", length(.cn_scanned), " matrix .rds; raw-vs-norm ratio not measurable without paired input)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_RCISTARGET_TFBS_MOTIF_ENRICHMENT",
      domain  = "bioconductor",
      declared_qc_steps = c("alignment/mapping QC", "low-count filtering", "count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_RCISTARGET_TFBS_MOTIF_ENRICHMENT":',
        paste0('    RcisTarget: ', as.character(packageVersion('RcisTarget')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tfbs_motif_enrichment.csv versions.yml
    """
}

workflow BIOC_RCISTARGET_TFBS_MOTIF_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_list.txt, motif_rankings.db ] ]

    main:
    BIOC_RCISTARGET_TFBS_MOTIF_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_RCISTARGET_TFBS_MOTIF_ENRICHMENT.out.tables
    plots    = BIOC_RCISTARGET_TFBS_MOTIF_ENRICHMENT.out.plots
    objects  = BIOC_RCISTARGET_TFBS_MOTIF_ENRICHMENT.out.objects
    versions = BIOC_RCISTARGET_TFBS_MOTIF_ENRICHMENT.out.versions
}
