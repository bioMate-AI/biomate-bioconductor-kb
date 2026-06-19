#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mia — community_diversity_and_ordination
// Calculate alpha diversity indices and perform beta diversity ordination (MDS/PCoA) on microbiome profiles.
// Input: GlobalPatterns.RDS
// Container: quay.io/biocontainers/bioconductor-mia:1.18.0--r45ha27e39d_0
// R packages: ggplot2, mia, scater
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, mia, scater
// Visualizations: ordination plot, MDS plot
// QC: cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read the input TreeSummarizedExperiment object
//  * 2. [Core Analysis] Estimate sample-wise alpha diversity (Shannon index)
//  * 3. [Core Analysis] Agglomerate taxonomic ranks
//  * 4. [Core Analysis] Perform Multidimensional Scaling (MDS/PCoA) ordination on
//  * 5. [Core Analysis] Save meaningful results to output files

nextflow.enable.dsl = 2

process BIOC_MIA_COMMUNITY_DIVERSITY_AND_ORDINATION {
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
    .bm_deps <- c("ggplot2", "mia", "scater", "SummarizedExperiment")
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
    library(mia)
    library(SummarizedExperiment)
    library(scater)
    library(ggplot2)
    
    # --- Read the input TreeSummarizedExperiment object ---
    # The pipeline reads EXACTLY the declared user input file from the working directory.
    tse <- readRDS("GlobalPatterns.RDS")
    
    # --- Estimate sample-wise alpha diversity (Shannon index) ---
    # This appends the results directly to the sample metadata (colData).
    tse <- addAlpha(tse, index = "shannon")
    
    # --- Agglomerate taxonomic ranks ---
    # This creates alternative experiments for each taxonomic rank, including "Genus".
    tse <- agglomerateByRanks(tse)
    
    # --- Perform Multidimensional Scaling (MDS/PCoA) ordination on ---
    # This calculates inter-sample beta diversity dissimilarity (Bray-Curtis) and stores the reduced dimensions.
    altExp(tse, "Genus") <- runMDS(
        altExp(tse, "Genus"), 
        FUN = getDissimilarity,
        method = "bray",
        name = "BrayCurtis", 
        ncomponents = 5, 
        assay.type = "counts", 
        keep_dist = TRUE
    )
    
    # --- Save meaningful results to output files ---
    
    # Save the updated TreeSummarizedExperiment object
    saveRDS(tse, "tse_diversity_ordination.RDS")
    
    # Save alpha diversity and sample metadata as a CSV table
    alpha_df <- as.data.frame(colData(tse))
    write.csv(alpha_df, "alpha_diversity_metadata.csv", row.names = TRUE)
    
    # Save MDS ordination coordinates as a CSV table
    mds_coords <- as.data.frame(reducedDim(altExp(tse, "Genus"), "BrayCurtis"))
    write.csv(mds_coords, "mds_bray_curtis_coordinates.csv", row.names = TRUE)
    
    # Generate and save a PDF plot of the MDS ordination
    pdf("mds_ordination_plot.pdf", width = 8, height = 6)
    # Use scater's plotReducedDim to visualize the MDS, coloring by SampleType if available
    if ("SampleType" %in% colnames(colData(altExp(tse, "Genus")))) {
        p <- plotReducedDim(altExp(tse, "Genus"), dimred = "BrayCurtis", colour_by = "SampleType") +
            labs(title = "MDS Ordination (Bray-Curtis Distance at Genus Level)") +
            theme_minimal()
    } else {
        p <- plotReducedDim(altExp(tse, "Genus"), dimred = "BrayCurtis") +
            labs(title = "MDS Ordination (Bray-Curtis Distance at Genus Level)") +
            theme_minimal()
    }
    print(p)
    dev.off()
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
      process = "BIOC_MIA_COMMUNITY_DIVERSITY_AND_ORDINATION",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_MIA_COMMUNITY_DIVERSITY_AND_ORDINATION":',
        paste0('    mia: ', as.character(packageVersion('mia')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_community_diversity_and_ordination.csv versions.yml
    """
}

workflow BIOC_MIA_COMMUNITY_DIVERSITY_AND_ORDINATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ GlobalPatterns.RDS ] ]

    main:
    BIOC_MIA_COMMUNITY_DIVERSITY_AND_ORDINATION(ch_input)

    emit:
    tables   = BIOC_MIA_COMMUNITY_DIVERSITY_AND_ORDINATION.out.tables
    plots    = BIOC_MIA_COMMUNITY_DIVERSITY_AND_ORDINATION.out.plots
    objects  = BIOC_MIA_COMMUNITY_DIVERSITY_AND_ORDINATION.out.objects
    versions = BIOC_MIA_COMMUNITY_DIVERSITY_AND_ORDINATION.out.versions
}
