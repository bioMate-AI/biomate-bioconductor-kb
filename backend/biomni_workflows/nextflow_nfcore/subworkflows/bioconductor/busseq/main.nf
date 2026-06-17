#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BUSseq — scrna_seq_batch_correction_and_clustering
// Correct batch effects, cluster unknown cell types, identify intrinsic genes, and obtain batch-corrected expression data from multi-batch scRNA-seq count data.
// Input: raw_counts.csv, batch_metadata.csv
// Container: quay.io/biocontainers/bioconductor-busseq:1.16.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BUSseq, SingleCellExperiment
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read user input files
//  * 2. [Visualization & Output] Fit the BUSseq model using MCMC sampling
//  * 3. [Visualization & Output] Extract the imputed read counts, estimated cell types,
//  * 4. [Visualization & Output] Identify intrinsic genes that drive cell-type differences
//  * 5. [Visualization & Output] Compute and incorporate batch-corrected read counts
//  * 6. [Visualization & Output] Visualize the raw, imputed, and corrected expression data

nextflow.enable.dsl = 2

process BIOC_BUSSEQ_SCRNA_SEQ_BATCH_CORRECTION_AND_CLUSTERING {
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
    .bm_deps <- c("BUSseq", "SummarizedExperiment")
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
     library(SummarizedExperiment)
   library(BUSseq)
    
    # --- Read user input files ---
    CountData <- as.matrix(read.csv("raw_counts.csv", row.names = 1, check.names = FALSE))
    
    batch_meta <- read.csv("batch_metadata.csv", stringsAsFactors = FALSE)
    
    # Identify batch indicator column
    batch_col <- grep("batch", colnames(batch_meta), ignore.case = TRUE, value = TRUE)
    if (length(batch_col) > 0) {
      batch_ind <- batch_meta[[batch_col[1]]]
    } else {
      batch_ind <- batch_meta[, 1]
    }
    
    # Prepare the input data as a SingleCellExperiment object
    sce_input <- SingleCellExperiment(assays = list(counts = CountData),
                              colData = DataFrame(Batch_ind = factor(batch_ind)))
    
    # --- Fit the BUSseq model using MCMC sampling ---
    BUSseqfits_res <- BUSseq_MCMC(ObservedData = sce_input, 
                              seed = 1234, n.cores = 2,
                              n.celltypes = 4, n.iterations = 500)
    
    # --- Extract the imputed read counts, estimated cell types, ---
    Imputed_count <- assay(BUSseqfits_res, "imputed_data")
    write.csv(as.matrix(Imputed_count), "imputed_counts.csv")
    
    celltyes_est <- celltypes(BUSseqfits_res)
    write.csv(data.frame(Cell = colnames(sce_input), Estimated_Celltype = celltyes_est), "estimated_celltypes.csv", row.names = FALSE)
    
    location_batch_effects_est <- location_batch_effects(BUSseqfits_res)
    write.csv(location_batch_effects_est, "location_batch_effects.csv")
    
    overdispersion_est <- overdispersions(BUSseqfits_res)
    write.csv(overdispersion_est, "overdispersions.csv")
    
    cell_effects_est <- cell_effect_values(BUSseqfits_res)
    write.csv(data.frame(Cell = colnames(sce_input), Cell_Effect = cell_effects_est), "cell_effects.csv", row.names = FALSE)
    
    # Note: The documented code used BUSseqfits_example for celltype_mean_expression.
    # Since BUSseqfits_example is a bundled demo object (which is forbidden),
    # we adapt it to use our fitted object BUSseqfits_res.
    celltype_mean_expression_est <- celltype_mean_expression(BUSseqfits_res)
    write.csv(celltype_mean_expression_est, "celltype_mean_expression.csv")
    
    celltype_effects_est <- celltype_effects(BUSseqfits_res)
    write.csv(celltype_effects_est, "celltype_effects.csv")
    
    # --- Identify intrinsic genes that drive cell-type differences ---
    intrinsic_gene_indicators <- intrinsic_genes_BUSseq(BUSseqfits_res)
    write.csv(as.data.frame(intrinsic_gene_indicators), "intrinsic_genes.csv")
    
    # --- Compute and incorporate batch-corrected read counts ---
    BUSseqfits_res <- corrected_read_counts(BUSseqfits_res)
    corrected_counts <- assay(BUSseqfits_res, "corrected_data")
    write.csv(as.matrix(corrected_counts), "corrected_counts.csv")
    
    # Save the final SingleCellExperiment object
    saveRDS(BUSseqfits_res, "BUSseqfits_res.rds")
    
    # --- Visualize the raw, imputed, and corrected expression data ---
    dir.create("./heatmap", showWarnings = FALSE, recursive = TRUE)
    
    heatmap_data_BUSseq(BUSseqfits_res, data_type = "Raw", 
                            project_name = "BUSseq_raw_allgenes",
                            image_dir = "./heatmap")
    
    heatmap_data_BUSseq(BUSseqfits_res, data_type = "Imputed", 
                            project_name = "BUSseq_imputed_allgenes",
                            image_dir = "./heatmap")
    
    heatmap_data_BUSseq(BUSseqfits_res, data_type = "Corrected",
                            project_name = "BUSseq_corrected_allgenes",
                            image_dir = "./heatmap")
    # ── BIOC_QC_HARNESS — Phase 3c bulk adoption (missing-value handling) ───
    # Defensive scan: list every *.rds the workflow produced, load each one,
    # compute NA fraction across numeric cells where the artifact is a
    # matrix or data.frame. Report max NA fraction across artifacts.
    # Threshold from bioc_missing_value_handling: < 5% pass.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()
    .na_fracs <- numeric(0)
    .scanned_files <- character(0)
    for (.rds_file in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .obj <- tryCatch(readRDS(.rds_file), error = function(e) NULL)
      .mat <- if (is.matrix(.obj) || is.data.frame(.obj)) .obj else NULL
      if (!is.null(.mat)) {
        .vals <- suppressWarnings(as.numeric(as.matrix(.mat)))
        if (length(.vals) > 0) {
          .na_fracs <- c(.na_fracs, mean(is.na(.vals)))
          .scanned_files <- c(.scanned_files, .rds_file)
        }
      }
    }
    .na_max <- if (length(.na_fracs) > 0) round(max(.na_fracs), 4) else NA_real_
    .gates_by_label[["missing-value handling"]] <- list(
      gate_row = "bioc_missing_value_handling",
      metric_name = "na_fraction_remaining",
      metric_value = .na_max,
      passes = isTRUE(is.finite(.na_max) && .na_max < 0.05),
      status = if (is.finite(.na_max)) paste0("computed (scanned ", length(.scanned_files), " rds files)")
               else "not_computed (no matrix/data.frame .rds artifact present)"
    )
    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_BUSSEQ_SCRNA_SEQ_BATCH_CORRECTION_AND_CLUSTERING",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_BUSSEQ_SCRNA_SEQ_BATCH_CORRECTION_AND_CLUSTERING":',
        paste0('    BUSseq: ', as.character(packageVersion('BUSseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scrna_seq_batch_correction_and_clustering.csv versions.yml
    """
}

workflow BIOC_BUSSEQ_SCRNA_SEQ_BATCH_CORRECTION_AND_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_counts.csv, batch_metadata.csv ] ]

    main:
    BIOC_BUSSEQ_SCRNA_SEQ_BATCH_CORRECTION_AND_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_BUSSEQ_SCRNA_SEQ_BATCH_CORRECTION_AND_CLUSTERING.out.tables
    plots    = BIOC_BUSSEQ_SCRNA_SEQ_BATCH_CORRECTION_AND_CLUSTERING.out.plots
    objects  = BIOC_BUSSEQ_SCRNA_SEQ_BATCH_CORRECTION_AND_CLUSTERING.out.objects
    versions = BIOC_BUSSEQ_SCRNA_SEQ_BATCH_CORRECTION_AND_CLUSTERING.out.versions
}
