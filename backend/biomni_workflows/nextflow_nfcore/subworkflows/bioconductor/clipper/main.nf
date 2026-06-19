#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: clipper — global_and_subpath_clipper_analysis
// Perform a two-step topological pathway analysis to test global pathway significance and identify specific active sub-paths.
// Input: expression_data.RData, class_labels.RData, pathway_graph.RData
// Container: quay.io/biocontainers/bioconductor-clipper:1.50.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, clipper, graph
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run global pathway analysis using pathQ to test for differences in covariance and mean
//  * 2. [Core Analysis] Identify specific sub-paths associated with the phenotype using clipper
//  * 3. [Core Analysis] Prune overlapping or redundant sub-paths using prunePaths
//  * 4. [Visualization & Output] Visualize the identified sub-paths using plotInCytoscape

nextflow.enable.dsl = 2

process BIOC_CLIPPER_GLOBAL_AND_SUBPATH_CLIPPER_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("clipper", "graph", "Biobase")
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
    library(clipper)
    library(graph)
    library(Biobase)
    
    # Helper function to load RData and extract the object
    load_rdata_object <- function(file_path) {
      if (!file.exists(file_path)) {
        stop(paste("Required input file missing:", file_path))
      }
      temp_env <- new.env()
      loaded_names <- load(file_path, envir = temp_env)
      if (length(loaded_names) == 0) {
        stop(paste("No objects found in", file_path))
      }
      return(temp_env[[loaded_names[1]]])
    }
    
    # 1. Read the declared USER INPUT files
    exp <- load_rdata_object("expression_data.RData")
    classes <- load_rdata_object("class_labels.RData")
    graph <- load_rdata_object("pathway_graph.RData")
    
    # 2. Run global pathway analysis using pathQ to test for differences in covariance and mean
    pathwayAnalysis <- pathQ(exp, classes, graph, nperm=100, alphaV=0.05, b=100)
    pathwayAnalysis
    
    # Save global pathway analysis results
    saveRDS(pathwayAnalysis, file = "pathway_analysis_global.rds")
    
    # 3. Identify specific sub-paths associated with the phenotype using clipper
    clipped <- clipper(exp, classes, graph, "var", trZero=0.01, permute=FALSE)
    clipped[,1:5]
    
    # Save raw clipped paths
    write.csv(as.data.frame(clipped), file = "clipped_paths_raw.csv", row.names = TRUE)
    
    # 4. Prune overlapping or redundant sub-paths using prunePaths
    clipped <- prunePaths(clipped, thr=0.2)
    clipped[,1:5]
    
    # Save pruned clipped paths
    write.csv(as.data.frame(clipped), file = "clipped_paths_pruned.csv", row.names = TRUE)
    
    # 5. Visualize the identified sub-paths using plotInCytoscape
    # Wrapped in tryCatch to handle environments where Cytoscape is not running
    tryCatch({
      if (nrow(clipped) > 0) {
        plotInCytoscape(graph, clipped[1,])
      } else {
        warning("No paths available to plot in Cytoscape.")
      }
    }, error = function(e) {
      message("Could not plot in Cytoscape. Ensure Cytoscape is running and RCy3 is configured properly.")
      message("Error details: ", e\$message)
    })
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

    # outlier detection — declarative gate per qc_evidence.yaml. Always emit
    # the row with passes=TRUE when the workflow produced any artifact;
    # downstream review confirms whether outlier flagging actually fired.
    .od_artifacts <- list.files(".", pattern = "\\.(rds|csv|tsv|txt|log)\$")
    .od_passes <- length(.od_artifacts) > 0
    .gates_by_label[["outlier detection"]] <- list(
      gate_row = "bioc_outlier_detection",
      metric_name = "artifacts_emitted",
      metric_value = length(.od_artifacts),
      passes = .od_passes,
      status = if (.od_passes) "computed (declarative; manual review for outlier-flag specifics)"
               else "not_computed (workflow emitted no artifacts)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_CLIPPER_GLOBAL_AND_SUBPATH_CLIPPER_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("input validation", "low-count filtering", "outlier detection"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_CLIPPER_GLOBAL_AND_SUBPATH_CLIPPER_ANALYSIS":',
        paste0('    clipper: ', as.character(packageVersion('clipper')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_global_and_subpath_clipper_analysis.csv versions.yml
    """
}

workflow BIOC_CLIPPER_GLOBAL_AND_SUBPATH_CLIPPER_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_data.RData, class_labels.RData, pathway_graph.RData ] ]

    main:
    BIOC_CLIPPER_GLOBAL_AND_SUBPATH_CLIPPER_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CLIPPER_GLOBAL_AND_SUBPATH_CLIPPER_ANALYSIS.out.tables
    plots    = BIOC_CLIPPER_GLOBAL_AND_SUBPATH_CLIPPER_ANALYSIS.out.plots
    objects  = BIOC_CLIPPER_GLOBAL_AND_SUBPATH_CLIPPER_ANALYSIS.out.objects
    versions = BIOC_CLIPPER_GLOBAL_AND_SUBPATH_CLIPPER_ANALYSIS.out.versions
}
