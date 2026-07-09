#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: StabMap — direct_mosaic_integration
// Integrate two single-cell datasets with partially overlapping features into a joint embedding, followed by cell type classification and feature imputation.
// Input: assay_list, referenceLabels
// Container: quay.io/biocontainers/bioconductor-stabmap:1.4.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: StabMap, magrittr
// Visualizations: mosaic plot
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Inspect shared features using mosaicDataUpSet
//  * 2. [Visualization & Output] Build and plot the mosaic data topology using mosaicDataTopology
//  * 3. [Core Analysis] Generate a joint embedding using stabMap
//  * 4. [Core Analysis] Impute missing features for query cells using imputeEmbedding
//  * 5. [Core Analysis] Classify query cells using classifyEmbedding

nextflow.enable.dsl = 2

process BIOC_STABMAP_DIRECT_MOSAIC_INTEGRATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("StabMap", "magrittr")
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
    library(StabMap)
    library(magrittr)
    
    # Read user inputs from the working directory
    # The pipeline expects 'assay_list.rds' (a list of log-normalized expression/accessibility matrices)
    # and 'referenceLabels.rds' (a named character vector of cell type annotations for the reference cells)
    assay_list <- readRDS("assay_list.rds")
    referenceLabels <- readRDS("referenceLabels.rds")
    
    # Identify reference and query datasets dynamically based on referenceLabels
    ref_dataset_names <- names(assay_list)[sapply(assay_list, function(x) any(colnames(x) %in% names(referenceLabels)))]
    query_dataset_names <- setdiff(names(assay_list), ref_dataset_names)
    
    ref_cells <- unlist(lapply(assay_list[ref_dataset_names], colnames), use.names = FALSE)
    query_cells <- unlist(lapply(assay_list[query_dataset_names], colnames), use.names = FALSE)
    
    # 1. Inspect shared features using mosaicDataUpSet
    upset_res <- mosaicDataUpSet(assay_list, plot = FALSE)
    saveRDS(upset_res, "mosaic_upset_results.rds")
    
    # 2. Build and plot the mosaic data topology using mosaicDataTopology
    mdt <- mosaicDataTopology(assay_list)
    saveRDS(mdt, "mosaic_data_topology.rds")
    
    pdf("mosaic_data_topology.pdf")
    plot(mdt)
    dev.off()
    
    # 3. Generate a joint embedding using stabMap
    stab <- stabMap(assay_list,
      reference_list = ref_dataset_names,
      plot = FALSE
    )
    saveRDS(stab, "stab_embedding.rds")
    write.csv(as.data.frame(stab), "stab_embedding.csv", row.names = TRUE)
    
    # 4. Impute missing features for query cells using imputeEmbedding
    imp <- imputeEmbedding(
      assay_list,
      stab,
      reference = ref_cells,
      query = query_cells
    )
    saveRDS(imp, "imputed_features.rds")
    
    # 5. Classify query cells using classifyEmbedding
    knn_out <- classifyEmbedding(
      stab,
      referenceLabels
    )
    write.csv(as.data.frame(knn_out), "classification_results.csv", row.names = TRUE)
    # ── BIOC_QC_HARNESS — Phase 3c bulk adoption (missing-value handling) ───
    # Defensive scan: list every *.rds the workflow produced, load each one,
    # compute NA fraction across numeric cells where the artifact is a
    # matrix or data.frame. Report max NA fraction across artifacts.
    # Threshold from bioc_missing_value_handling: < 5% pass.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()
    .na_fracs <- numeric(0)
    .scanned_files <- character(0)
    for (.rds_file in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
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
      process = "BIOC_STABMAP_DIRECT_MOSAIC_INTEGRATION",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_STABMAP_DIRECT_MOSAIC_INTEGRATION":',
        paste0('    StabMap: ', as.character(packageVersion('StabMap')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_direct_mosaic_integration.csv versions.yml
    """
}

workflow BIOC_STABMAP_DIRECT_MOSAIC_INTEGRATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ assay_list, referenceLabels ] ]

    main:
    BIOC_STABMAP_DIRECT_MOSAIC_INTEGRATION(ch_input)

    emit:
    tables   = BIOC_STABMAP_DIRECT_MOSAIC_INTEGRATION.out.tables
    plots    = BIOC_STABMAP_DIRECT_MOSAIC_INTEGRATION.out.plots
    objects  = BIOC_STABMAP_DIRECT_MOSAIC_INTEGRATION.out.objects
    versions = BIOC_STABMAP_DIRECT_MOSAIC_INTEGRATION.out.versions
}
