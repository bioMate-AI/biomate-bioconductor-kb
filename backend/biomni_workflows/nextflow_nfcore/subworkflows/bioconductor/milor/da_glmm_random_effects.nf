#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: miloR — da_glmm_random_effects
// Perform differential abundance testing using a Generalized Linear Mixed Model (GLMM) to account for random effects and dependencies between observations.
// Input: pbmc.sce, pbmc.design
// Container: quay.io/biocontainers/bioconductor-milor:2.6.0--r45ha27e39d_0
// R packages: BiocParallel, SingleCellExperiment, dplyr, ggplot2, miloR, patchwork, scater, scran
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, SingleCellExperiment, dplyr, ggplot2, miloR, patchwork, scater, scran
// Visualizations: UMAP plot
// QC: cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create Milo object
//  * 2. [Input & Preparation] Build KNN graph
//  * 3. [Input & Preparation] Define representative neighbourhoods
//  * 4. [Core Analysis] Count cells in neighbourhoods
//  * 5. [Core Analysis] Check for perfect separation
//  * 6. [Core Analysis] Test for differential abundance using GLMM

nextflow.enable.dsl = 2

process BIOC_MILOR_DA_GLMM_RANDOM_EFFECTS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-single_cell:3.20-slim"

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
    .bm_deps <- c("BiocParallel", "SingleCellExperiment", "dplyr", "ggplot2", "miloR", "patchwork", "scater", "scran", "SummarizedExperiment")
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
        library(miloR)
        library(SummarizedExperiment)
        library(scater)
        library(scran)
        library(dplyr)
        library(patchwork)
        library(BiocParallel)
        library(ggplot2)
        
        # Set up parallel execution parameters
        bpparam <- SerialParam()
        
        # Read user input files from the working directory
        pbmc.sce <- readRDS("pbmc.sce")
        pbmc.design <- readRDS("pbmc.design")
        
        # Extract column names dynamically from pbmc.design
        sample_col <- colnames(pbmc.design)[1]
        fixed_col <- colnames(pbmc.design)[2]
        random_col <- colnames(pbmc.design)[3]
        
        # 1. Create Milo object
        pbmc.milo <- Milo(pbmc.sce)
        reducedDim(pbmc.milo, "UMAP") <- reducedDim(pbmc.sce, "UMAP")
        
        # 2. Build KNN graph
        pbmc.milo <- buildGraph(pbmc.milo, k = 60, d = 30)
        
        # 3. Define representative neighbourhoods
        pbmc.milo <- makeNhoods(pbmc.milo, prop = 0.05, k = 60, d=30, refined = TRUE, refinement_scheme="graph")
        
        # 4. Count cells in neighbourhoods
        pbmc.milo <- countCells(pbmc.milo, meta.data = data.frame(colData(pbmc.milo)), samples=sample_col)
        
        # Align rownames of pbmc.design with columns of nhoodCounts(pbmc.milo)
        rownames(pbmc.design) <- as.character(pbmc.design[[sample_col]])
        pbmc.design <- pbmc.design[colnames(nhoodCounts(pbmc.milo)), , drop=FALSE]
        
        # 5. Check for perfect separation
        separated_nhoods <- which(checkSeparation(pbmc.milo, design.df=pbmc.design, condition=fixed_col, min.val=10))
        write.csv(data.frame(Separated_Nhoods = separated_nhoods), "separated_nhoods.csv", row.names=FALSE)
        
        # 6. Test for differential abundance using GLMM
        design_formula <- as.formula(paste0("~ ", fixed_col, " + (1|", random_col, ")"))
        da_results <- testNhoods(pbmc.milo, design = design_formula, design.df = pbmc.design, fdr.weighting="graph-overlap", glmm.solver="Fisher", REML=TRUE, norm.method="TMM", BPPARAM = bpparam, fail.on.error=FALSE)
        
        # Save results to output files
        write.csv(da_results, "da_results.csv", row.names=TRUE)
        saveRDS(pbmc.milo, "pbmc_milo_results.rds")
        
        # Generate diagnostic plots
        pdf("nhood_size_histogram.pdf")
        print(plotNhoodSizeHist(pbmc.milo))
        dev.off()
        
        # Attempt to build neighbourhood graph and plot DA results on UMAP
        tryCatch({
          pbmc.milo <- buildNhoodGraph(pbmc.milo)
          pdf("nhood_da_umap.pdf")
          print(plotNhoodGraphDA(pbmc.milo, da_results, alpha=0.1))
          dev.off()
        }, error = function(e) {
          message("Skipping DA UMAP plot generation: ", e\$message)
        })
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # cell QC metrics — defensive cell-count + per-cell summary from any
    # matrix artifact. Pass when columns (cells) ≥ 50 and rows (features) ≥ 200
    # (Luecken & Theis 2019 single-cell QC floor).
    .cqc_ncells <- NA_real_; .cqc_nfeats <- NA_real_; .cqc_files <- character(0)
    for (.cqc_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
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
      process = "BIOC_MILOR_DA_GLMM_RANDOM_EFFECTS",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_MILOR_DA_GLMM_RANDOM_EFFECTS":',
        paste0('    miloR: ', as.character(packageVersion('miloR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_da_glmm_random_effects.csv versions.yml
    """
}

workflow BIOC_MILOR_DA_GLMM_RANDOM_EFFECTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pbmc.sce, pbmc.design ] ]

    main:
    BIOC_MILOR_DA_GLMM_RANDOM_EFFECTS(ch_input)

    emit:
    tables   = BIOC_MILOR_DA_GLMM_RANDOM_EFFECTS.out.tables
    plots    = BIOC_MILOR_DA_GLMM_RANDOM_EFFECTS.out.plots
    objects  = BIOC_MILOR_DA_GLMM_RANDOM_EFFECTS.out.objects
    versions = BIOC_MILOR_DA_GLMM_RANDOM_EFFECTS.out.versions
}
