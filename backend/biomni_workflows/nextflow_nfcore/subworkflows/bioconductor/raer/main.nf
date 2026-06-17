#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: raer — single_cell_editing
// Quantify RNA editing sites in single-cell RNA-seq data (droplet or Smart-seq2) and calculate editing frequencies.
// Input: bamfile.bam, editing_sites.gr
// Container: quay.io/biocontainers/bioconductor-raer:1.8.0--r45h01b2380_2
// R packages: GenomicRanges, Rsamtools, AnnotationHub, ComplexHeatmap, raer, raerdata, scater, SingleCellExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, Rsamtools, SingleCellExperiment, raer
// QC: cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Format editing sites with REF and ALT metadata columns
//  * 2. [Core Analysis] Configure filtering parameters using FilterParam()
//  * 3. [Core Analysis] Quantify reference and alternate alleles per cell using pileup_cells()
//  * 4. [Core Analysis] Calculate editing frequencies using calc_edit_frequency()

nextflow.enable.dsl = 2

process BIOC_RAER_SINGLE_CELL_EDITING {
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
    .bm_deps <- c("GenomicRanges", "Rsamtools", "AnnotationHub", "ComplexHeatmap", "raer", "raerdata", "scater", "SingleCellExperiment", "SummarizedExperiment")
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
                    
    # Load required libr    library(SummarizedExperiment)
aries
    library(raer)
    library(GenomicRanges)
    library(Rsamtools)
    
    # Define input file paths
    bam_input <- "bamfile.bam"
    sites_input <- "editing_sites.gr"
    
    # Verify input files exist
    if (!file.exists(bam_input)) {
        stop(paste("Required input BAM file missing:", bam_input))
    }
    if (!file.exists(sites_input)) {
        stop(paste("Required input GRanges RDS file missing:", sites_input))
    }
    
    # 1. Read user input files
    message("Reading input editing sites...")
    editing_sites <- readRDS(sites_input)
    
    # 2. Format editing sites with REF and ALT metadata columns
    editing_sites\$REF <- Rle("A")
    editing_sites\$ALT <- Rle("G")
    
    # 3. Configure filtering parameters using FilterParam()
    params <- FilterParam(
        min_mapq = 255, # required alignment MAPQ score
        library_type = "fr-second-strand", # library type
        min_variant_reads = 1
    )
    
    # Create output directory for pileup results
    outdir <- "sc_edits_output"
    if (!dir.create(outdir, showWarnings = FALSE, recursive = TRUE)) {
        message("Output directory already exists or could not be created explicitly.")
    }
    
    # Extract cell barcodes from BAM file
    message("Extracting cell barcodes from BAM file...")
    sbp <- ScanBamParam(tag = "CB", what = character(0))
    bam_data <- scanBam(bam_input, param = sbp)
    cbs <- unique(bam_data[[1]]\$tag\$CB)
    cbs <- cbs[!is.na(cbs)]
    
    # 4. Quantify reference and alternate alleles per cell using pileup_cells()
    message("Running pileup_cells...")
    e_sce <- pileup_cells(
        bamfile = bam_input,
        sites = editing_sites,
        cell_barcodes = cbs,
        output_directory = outdir,
        cb_tag = "CB",
        umi_tag = "UB",
        param = params
    )
    
    # Filter to find sites with an editing event in at least 5 cells
    message("Filtering editing sites...")
    e_sce <- e_sce[rowSums(assays(e_sce)\$nAlt > 0) >= 5, ]
    
    # 5. Calculate editing frequencies using calc_edit_frequency()
    message("Calculating editing frequencies...")
    e_sce <- calc_edit_frequency(e_sce,
        edit_from = "Ref",
        edit_to = "Alt",
        replace_na = FALSE
    )
    
    # 6. Write named output files for the meaningful results
    message("Writing output files...")
    saveRDS(e_sce, file = "sc_editing_results.rds")
    
    message("Pipeline completed successfully. Outputs saved to 'sc_edits_output/' and current working directory.")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # cell QC metrics — defensive cell-count + per-cell summary from any
    # matrix artifact. Pass when columns (cells) ≥ 50 and rows (features) ≥ 200
    # (Luecken & Theis 2019 single-cell QC floor).
    .cqc_ncells <- NA_real_; .cqc_nfeats <- NA_real_; .cqc_files <- character(0)
    for (.cqc_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .cqc_obj <- tryCatch(readRDS(.cqc_rds), error = function(e) NULL)
      .cqc_mat <- if (is.matrix(.cqc_obj) || is.data.frame(.cqc_obj)) .cqc_obj else NULL
      if (!is.null(.cqc_mat) && nrow(.cqc_mat) > 100) {
        .cqc_ncells <- ncol(.cqc_mat); .cqc_nfeats <- nrow(.cqc_mat)
        .cqc_files <- c(.cqc_files, .cqc_rds); break
      }
    }
    .gates_by_label[["cell QC metrics"]] <- list(
      gate_row = "bioc_cell_qc_metrics",
      metric_name = "n_cells",
      metric_value = .cqc_ncells,
      passes = isTRUE(is.finite(.cqc_ncells) && .cqc_ncells >= 50 && .cqc_nfeats >= 200),
      status = if (is.finite(.cqc_ncells)) paste0("computed (cells=", .cqc_ncells, ", features=", .cqc_nfeats, "; proxy gate)")
               else "not_computed (no scRNA matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_RAER_SINGLE_CELL_EDITING",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_RAER_SINGLE_CELL_EDITING":',
        paste0('    raer: ', as.character(packageVersion('raer')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_cell_editing.csv versions.yml
    """
}

workflow BIOC_RAER_SINGLE_CELL_EDITING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bamfile.bam, editing_sites.gr ] ]

    main:
    BIOC_RAER_SINGLE_CELL_EDITING(ch_input)

    emit:
    tables   = BIOC_RAER_SINGLE_CELL_EDITING.out.tables
    plots    = BIOC_RAER_SINGLE_CELL_EDITING.out.plots
    objects  = BIOC_RAER_SINGLE_CELL_EDITING.out.objects
    versions = BIOC_RAER_SINGLE_CELL_EDITING.out.versions
}
