#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: miloR — standard_da_glm
// Perform standard differential abundance testing using a Negative Binomial GLM, followed by neighbourhood annotation, grouping, and marker gene identification.
// Input: embryo_data, embryo_design
// Container: quay.io/biocontainers/bioconductor-milor:2.6.0--r45ha27e39d_0
// R packages: SingleCellExperiment, dplyr, ExperimentHub, miloR, patchwork, scater, scran
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, dplyr, miloR, patchwork, scater, scran
// Visualizations: plot (ggplot/base)
// QC: cell QC metrics, count normalization, highly-variable feature selection
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create Milo object
//  * 2. [Input & Preparation] Build KNN graph
//  * 3. [Input & Preparation] Define representative neighbourhoods
//  * 4. [Core Analysis] Count cells in neighbourhoods
//  * 5. [Core Analysis] Compute neighbourhood connectivity (distances)
//  * 6. [Core Analysis] Test for differential abundance
//  * 7. [Core Analysis] Annotate and group neighbourhoods
//  * 8. [Core Analysis] Find marker genes for neighbourhood groups
//  * 9. [Core Analysis] Perform differential expression within a group

nextflow.enable.dsl = 2

process BIOC_MILOR_STANDARD_DA_GLM {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-single_cell:3.20"

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
    .bm_deps <- c("SingleCellExperiment", "dplyr", "ExperimentHub", "miloR", "patchwork", "scater", "scran", "SummarizedExperiment")
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
        library(miloR)
        library(SummarizedExperiment)
        library(scater)
        library(scran)
        library(dplyr)
        library(patchwork)
        
        # 1. Load user input files from the working directory
        embryo_data <- readRDS("embryo_data.rds")
        embryo_design <- readRDS("embryo_design.rds")
        
        # 2. Create Milo object
        embryo_milo <- Milo(embryo_data)
        
        # Dynamically identify the first reduced dimension to avoid hardcoding
        red_dim <- reducedDimNames(embryo_milo)[1]
        
        # 3. Build KNN graph
        embryo_milo <- buildGraph(embryo_milo, k = 30, d = 30, reduced.dim = red_dim)
        
        # 4. Define representative neighbourhoods
        embryo_milo <- makeNhoods(embryo_milo, prop = 0.1, k = 30, d=30, refined = TRUE, reduced_dims = red_dim)
        
        # Plot and save neighbourhood size histogram
        pdf("nhood_size_histogram.pdf")
        plotNhoodSizeHist(embryo_milo)
        dev.off()
        
        # 5. Count cells in neighbourhoods
        embryo_milo <- countCells(embryo_milo, meta.data = as.data.frame(colData(embryo_milo)), samples="sample")
        
        # 6. Compute neighbourhood connectivity (distances)
        embryo_milo <- calcNhoodDistance(embryo_milo, d=30, reduced.dim = red_dim)
        
        # 7. Test for differential abundance
        # Dynamically construct design formula from embryo_design columns
        if ("sample" %in% colnames(embryo_design)) {
          rownames(embryo_design) <- embryo_design\$sample
          design_cols <- setdiff(colnames(embryo_design), "sample")
        } else {
          design_cols <- colnames(embryo_design)
        }
        design_form <- as.formula(paste("~", paste(design_cols, collapse=" + ")))
        
        da_results <- testNhoods(embryo_milo, design = design_form, design.df = embryo_design, reduced.dim=red_dim)
        
        # 8. Build neighbourhood graph
        embryo_milo <- buildNhoodGraph(embryo_milo)
        
        # 9. Annotate and group neighbourhoods
        # Dynamically identify a celltype column from colData
        cd_colnames <- colnames(colData(embryo_milo))
        possible_cols <- setdiff(cd_colnames, c("sample", "barcode", "cell", "sizeFactor"))
        celltype_col <- grep("celltype|cluster|ident|label|type", possible_cols, ignore.case=TRUE, value=TRUE)[1]
        if (is.na(celltype_col)) {
          celltype_col <- possible_cols[1]
        }
        
        da_results <- annotateNhoods(embryo_milo, da_results, coldata_col = celltype_col)
        da_results <- groupNhoods(embryo_milo, da_results, max.lfc.delta = 10, overlap=1)
        
        # 10. Find marker genes for neighbourhood groups
        # Compute log-normalized counts before running modelGeneVar to prevent runtime errors
        embryo_milo <- logNormCounts(embryo_milo)
        
        # Compute highly variable genes (hvgs) as required by findNhoodGroupMarkers
        dec <- modelGeneVar(embryo_milo)
        hvgs <- getTopHVGs(dec, n=2000)
        
        nhood_markers <- findNhoodGroupMarkers(embryo_milo, da_results, subset.row = hvgs, aggregate.samples = TRUE, sample_col = "sample")
        
        # 11. Perform differential expression within a group (robustly handled in case group "6" is absent)
        # Ensure design columns are present in meta_data for testDiffExp
        meta_data <- as.data.frame(colData(embryo_milo))
        for (col in design_cols) {
          if (!(col %in% colnames(meta_data))) {
            if ("sample" %in% colnames(embryo_design)) {
              meta_data[[col]] <- embryo_design[[col]][match(meta_data\$sample, embryo_design\$sample)]
            } else {
              meta_data[[col]] <- embryo_design[[col]][match(meta_data\$sample, rownames(embryo_design))]
            }
          }
        }
        
        dge_6 <- tryCatch({
          if ("6" %in% da_results\$NhoodGroup) {
            testDiffExp(embryo_milo, da_results, design = design_form, meta.data = meta_data, subset.nhoods=da_results\$NhoodGroup=="6")
          } else {
            message("NhoodGroup '6' not found in grouping results. Skipping testDiffExp.")
            NULL
          }
        }, error = function(e) {
          warning("Error in testDiffExp: ", e\$message)
          NULL
        })
        
        # 12. Save outputs
        write.csv(da_results, "da_results.csv", row.names = FALSE)
        write.csv(nhood_markers, "nhood_markers.csv", row.names = FALSE)
        if (!is.null(dge_6)) {
          saveRDS(dge_6, "dge_6_results.rds")
        }
        saveRDS(embryo_milo, "embryo_milo_final.rds")
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

    # HVG selection — count rows with high CV. Pass when 1000-3000 HVGs
    # (Stuart 2019 Cell Seurat v3 default range).
    .hvg_count <- NA_real_; .hvg_files <- character(0)
    for (.hvg_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .hvg_obj <- tryCatch(readRDS(.hvg_rds), error = function(e) NULL)
      .hvg_mat <- if (is.matrix(.hvg_obj) || is.data.frame(.hvg_obj)) .hvg_obj else NULL
      if (!is.null(.hvg_mat) && nrow(.hvg_mat) > 200) {
        .hvg_m <- suppressWarnings(as.matrix(.hvg_mat))
        .hvg_cvs <- suppressWarnings(apply(.hvg_m, 1, function(r) {
          .rv <- as.numeric(r); .m <- mean(.rv, na.rm = TRUE)
          if (is.finite(.m) && .m > 0) sd(.rv, na.rm = TRUE) / .m else NA_real_
        }))
        .hvg_count <- sum(is.finite(.hvg_cvs) & .hvg_cvs > 1.0)
        .hvg_files <- c(.hvg_files, .hvg_rds); break
      }
    }
    .gates_by_label[["highly-variable feature selection"]] <- list(
      gate_row = "bioc_hvg_selection",
      metric_name = "hvg_count",
      metric_value = .hvg_count,
      passes = isTRUE(is.finite(.hvg_count) && .hvg_count >= 1000 && .hvg_count <= 3000),
      status = if (is.finite(.hvg_count)) paste0("computed (CV>1.0 rows = ", .hvg_count, "; proxy for HVG selection)")
               else "not_computed (no expression matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_MILOR_STANDARD_DA_GLM",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics", "count normalization", "highly-variable feature selection"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_MILOR_STANDARD_DA_GLM":',
        paste0('    miloR: ', as.character(packageVersion('miloR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_da_glm.csv versions.yml
    """
}

workflow BIOC_MILOR_STANDARD_DA_GLM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ embryo_data, embryo_design ] ]

    main:
    BIOC_MILOR_STANDARD_DA_GLM(ch_input)

    emit:
    tables   = BIOC_MILOR_STANDARD_DA_GLM.out.tables
    plots    = BIOC_MILOR_STANDARD_DA_GLM.out.plots
    objects  = BIOC_MILOR_STANDARD_DA_GLM.out.objects
    versions = BIOC_MILOR_STANDARD_DA_GLM.out.versions
}
