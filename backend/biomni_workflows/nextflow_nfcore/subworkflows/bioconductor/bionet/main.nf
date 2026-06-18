#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BioNet — heuristic_module_detection
// Identify active functional modules from aggregated p-values and a PPI network using a fast heuristic approach without requiring CPLEX.
// Input: pvals_matrix.txt, ppi_network.sif
// Container: quay.io/biocontainers/bioconductor-bionet:1.70.0--r45hdfd78af_0
// R packages: ALL, BioNet, dlbcl, genefilter, graph, impute, limma
// Bioconductor: 3.20 | R: 4.4
// Requires: BioNet, graph
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Aggregate multiple p-values using aggrPvals
//  * 2. [Core Analysis] Extract a subnetwork of the PPI network using subNetwork and remove self-loops with rmSelfLoops
//  * 3. [Core Analysis] Fit a Beta-uniform mixture (BUM) model to the aggregated p-values using fitBumModel
//  * 4. [Core Analysis] Score the nodes of the subnetwork using scoreNodes with a specified FDR
//  * 5. [Core Analysis] Run the fast heuristic module detection using runFastHeinz
//  * 6. [Visualization & Output] Plot the resulting module using plotModule

nextflow.enable.dsl = 2

process BIOC_BIONET_HEURISTIC_MODULE_DETECTION {
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
    .bm_deps <- c("ALL", "BioNet", "dlbcl", "genefilter", "graph", "impute", "limma")
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
    library(BioNet)
    library(graph)
    
    # ==========================================
    # 1. READ USER INPUT FILES
    # ==========================================
    
    # Read the PPI network from SIF format
    interactome <- loadNetwork.sif("ppi_network.sif")
    
    # Read the p-values and differential expression matrix
    pvals_df <- read.table("pvals_matrix.txt", header=TRUE, sep="\t", row.names=1, check.names=FALSE)
    
    # Extract differential expression if present, and isolate p-values
    if ("diff" %in% colnames(pvals_df)) {
      logFC <- pvals_df\$diff
      pvals <- as.matrix(pvals_df[, colnames(pvals_df) != "diff", drop=FALSE])
    } else {
      logFC <- rep(0, nrow(pvals_df))
      pvals <- as.matrix(pvals_df)
    }
    names(logFC) <- rownames(pvals_df)
    
    # ==========================================
    # 2. RUN DOCUMENTED WORKFLOW
    # ==========================================
    
    pval <- aggrPvals(pvals, order=2, plot=FALSE)
    subnet <- subNetwork(rownames(pvals_df), interactome)
    subnet <- rmSelfLoops(subnet)
    fb <- fitBumModel(pval, plot=FALSE)
    scores <- scoreNodes(subnet, fb, fdr=0.001)
    module <- runFastHeinz(subnet, scores)
    
    # Save the plot to a PDF file
    pdf("heuristic_module_plot.pdf", width=10, height=10)
    plotModule(module, scores=scores, diff.expr=logFC)
    dev.off()
    
    # ==========================================
    # 3. WRITE OUTPUT FILES
    # ==========================================
    
    # Save the identified module as an RDS object
    saveRDS(module, "heuristic_module.rds")
    
    # Save the module in XGMML format for Cytoscape visualization
    saveNetwork(module, file="heuristic_module", type="XGMML")
    
    # Save the node scores and differential expression values of the module
    module_nodes <- nodes(module)
    module_results <- data.frame(
      Node = module_nodes,
      Score = scores[module_nodes],
      DiffExpr = logFC[module_nodes],
      stringsAsFactors = FALSE
    )
    write.csv(module_results, "heuristic_module_nodes.csv", row.names=FALSE)
    
    # Save BUM model summary
    sink("bum_model_summary.txt")
    print(fb)
    sink()
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
      process = "BIOC_BIONET_HEURISTIC_MODULE_DETECTION",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_BIONET_HEURISTIC_MODULE_DETECTION":',
        paste0('    BioNet: ', as.character(packageVersion('BioNet')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_heuristic_module_detection.csv versions.yml
    """
}

workflow BIOC_BIONET_HEURISTIC_MODULE_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pvals_matrix.txt, ppi_network.sif ] ]

    main:
    BIOC_BIONET_HEURISTIC_MODULE_DETECTION(ch_input)

    emit:
    tables   = BIOC_BIONET_HEURISTIC_MODULE_DETECTION.out.tables
    plots    = BIOC_BIONET_HEURISTIC_MODULE_DETECTION.out.plots
    objects  = BIOC_BIONET_HEURISTIC_MODULE_DETECTION.out.objects
    versions = BIOC_BIONET_HEURISTIC_MODULE_DETECTION.out.versions
}
