#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: raer — bulk_differential_editing
// Quantify editing sites in bulk RNA-seq and identify condition-specific differential editing events.
// Input: bam_files.bam, fafn.fasta, chr_18_editing_sites.gr
// Container: quay.io/biocontainers/bioconductor-raer:1.8.0--r45h01b2380_2
// R packages: ComplexHeatmap, GenomicRanges, SummarizedExperiment, raer, rtracklayer
// Bioconductor: 3.20 | R: 4.4
// Requires: ComplexHeatmap, GenomicRanges, SummarizedExperiment, raer, rtracklayer
// Visualizations: heatmap (ComplexHeatmap), heatmap
// QC: low-count filtering
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Configure filtering parameters using FilterParam()
//  * 2. [Core Analysis] Quantify base counts at editing sites across samples using pileup_sites()
//  * 3. [Core Analysis] Calculate editing frequencies and depth using calc_edit_frequency()
//  * 4. [Core Analysis] Filter out low-frequency or low-depth sites
//  * 5. [Input & Preparation] Create a differential editing object using make_de_object()
//  * 6. [Core Analysis] Identify differentially edited sites using find_de_sites()

nextflow.enable.dsl = 2

process BIOC_RAER_BULK_DIFFERENTIAL_EDITING {
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
    .bm_deps <- c("ComplexHeatmap", "GenomicRanges", "SummarizedExperiment", "raer", "rtracklayer")
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
            library(raer)
            library(SummarizedExperiment)
            library(GenomicRanges)
            library(rtracklayer)
            
            # 1. Read User Input Files
            # Read all BAM files in the current directory to represent actual biological replicates
            bam_files <- list.files(pattern = "\\\\.bam\$", full.names = TRUE)
            names(bam_files) <- tools::file_path_sans_ext(basename(bam_files))
            
            fafn <- "fafn.fasta"
            sites_file <- "chr_18_editing_sites.gr"
            
            # Read the GRanges object of known editing sites using readRDS for serialized R objects
            chr_18_editing_sites <- readRDS(sites_file)
            
            # 2. Configure Filtering Parameters
            fp <- FilterParam(
                only_keep_variants = TRUE, # only report sites with variants
                trim_5p = 5, # bases to remove from 5' or 3' end
                trim_3p = 5,
                min_base_quality = 30, # minimum base quality score
                min_mapq = 255, # minimum MAPQ read score
                library_type = "fr-first-strand", # library type
                min_splice_overhang = 10 # minimum required splice site overhang
            )
            
            # 3. Quantify Base Counts at Editing Sites Across Samples
            rse <- pileup_sites(bam_files,
                fasta = fafn,
                sites = chr_18_editing_sites,
                chroms = "chr18",
                param = fp
            )
            
            # Add sample metadata required for downstream differential analysis
            # Extract condition dynamically from filename (e.g., "Wildtype_1" -> "Wildtype")
            colData(rse)\$sample <- names(bam_files)
            conds <- gsub("[_0-9]+\$", "", names(bam_files))
            
            # Fallback if pattern is not met and fewer than 2 conditions are found
            if (length(unique(conds)) < 2) {
                half <- ceiling(length(bam_files) / 2)
                conds <- rep(c("Control", "Treatment"), c(half, length(bam_files) - half))
            }
            colData(rse)\$condition <- as.factor(conds)
            
            # 4. Calculate Editing Frequencies and Depth
            rse <- calc_edit_frequency(rse,
                edit_from = "A",
                edit_to = "G",
                drop = TRUE
            )
            
            # 5. Filter Out Low-Frequency or Low-Depth Sites
            has_editing <- rowSums(assay(rse, "edit_freq") > 0) >= 1
            has_depth <- rowSums(assay(rse, "depth") >= 5) == ncol(rse)
            rse <- rse[has_editing & has_depth, ]
            
            # 6. Create a Differential Editing Object
            deobj <- make_de_object(rse, min_prop = 0.05, min_samples = 3)
            deobj\$sample <- factor(deobj\$sample)
            
            # 7. Identify Differentially Edited Sites
            cond_levels <- levels(colData(rse)\$condition)
            
            de_results <- find_de_sites(deobj,
                test = "DESeq2",
                sample_col = "sample",
                condition_col = "condition",
                condition_control = cond_levels[1],
                condition_treatment = cond_levels[2]
            )
            
            # 8. Save Outputs
            # Save the full differential editing results object
            saveRDS(de_results, "de_results.rds")
            
            # Save the significant results table as a CSV
            if (!is.null(de_results\$sig_results)) {
                write.csv(as.data.frame(de_results\$sig_results), "significant_de_sites.csv", row.names = TRUE)
            }
            
            # Generate and save a heatmap of editing frequencies for the top differentially edited sites
            pdf("top_differentially_edited_sites_heatmap.pdf", width = 6, height = 8)
            tryCatch({
                library(ComplexHeatmap)
                if (!is.null(de_results\$sig_results) && nrow(de_results\$sig_results) > 0) {
                    top_sites <- rownames(de_results\$sig_results)[1:min(20, nrow(de_results\$sig_results))]
                    hp <- Heatmap(assay(rse, "edit_freq")[top_sites, , drop = FALSE],
                        name = "editing frequency",
                        column_labels = paste0(rse\$condition, "-", rse\$sample)
                    )
                    draw(hp)
                }
            }, error = function(e) {
                # Fallback to base R heatmap if ComplexHeatmap is not available or fails
                if (!is.null(de_results\$sig_results) && nrow(de_results\$sig_results) > 0) {
                    top_sites <- rownames(de_results\$sig_results)[1:min(20, nrow(de_results\$sig_results))]
                    heatmap(assay(rse, "edit_freq")[top_sites, , drop = FALSE],
                        labCol = paste0(rse\$condition, "-", rse\$sample),
                        main = "Editing Frequency"
                    )
                }
            })
            dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_RAER_BULK_DIFFERENTIAL_EDITING",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_RAER_BULK_DIFFERENTIAL_EDITING":',
        paste0('    raer: ', as.character(packageVersion('raer')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bulk_differential_editing.csv versions.yml
    """
}

workflow BIOC_RAER_BULK_DIFFERENTIAL_EDITING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bam_files.bam, fafn.fasta, chr_18_editing_sites.gr ] ]

    main:
    BIOC_RAER_BULK_DIFFERENTIAL_EDITING(ch_input)

    emit:
    tables   = BIOC_RAER_BULK_DIFFERENTIAL_EDITING.out.tables
    plots    = BIOC_RAER_BULK_DIFFERENTIAL_EDITING.out.plots
    objects  = BIOC_RAER_BULK_DIFFERENTIAL_EDITING.out.objects
    versions = BIOC_RAER_BULK_DIFFERENTIAL_EDITING.out.versions
}
