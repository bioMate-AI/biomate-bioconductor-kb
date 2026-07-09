#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scviR — citeseq_totalvi_training
// Preprocess CITE-seq data, set up a MuData object, and train a TOTALVI model to obtain joint latent representations and denoised expressions.
// Input: HDP.h5
// Container: quay.io/biocontainers/bioconductor-scvir:1.10.0--r45hdfd78af_0
// R packages: ggplot2, pheatmap, reshape2, reticulate, scater, scuttle, scviR, SingleCellExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, pheatmap, reticulate, scater, scuttle, scviR
// Visualizations: plot (ggplot/base)
// QC: cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Acquire and cache CITE-seq data
//  * 2. [Input & Preparation] Load data into a MuData object
//  * 3. [Core Analysis] Preprocess RNA modality (normalize, log-transform, select highly variable genes)
//  * 4. [Core Analysis] Subset MuData to highly variable genes and convert matrices to dense format
//  * 5. [Input & Preparation] Set up MuData for TOTALVI
//  * 6. [Core Analysis] Initialize and train the TOTALVI model
//  * 7. [Core Analysis] Extract training history (ELBO)

nextflow.enable.dsl = 2

process BIOC_SCVIR_CITESEQ_TOTALVI_TRAINING {
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
    .bm_deps <- c("ggplot2", "pheatmap", "reshape2", "reticulate", "scater", "scuttle", "scviR", "SingleCellExperiment")
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
    library(scater)
    library(scviR)
    library(scuttle)
    library(reticulate)
    library(pheatmap)
    
    # 1. Load data into a MuData object
    if (file.exists("HDP.h5")) {
      HDP.h5 = "HDP.h5"
    } else {
      stop("Required input file 'HDP.h5' not found in the working directory.")
    }
    
    mdata1 = muonR()\$read_10x_h5(HDP.h5)
    mdata1\$mod["rna"]\$var_names_make_unique()
    reticulate::py_run_string('r.mdata1.mod["rna"].layers["counts"] = r.mdata1.mod["rna"].X.copy()')
    
    # 2. Preprocess RNA
    scr = scanpyR()
    scr\$pp\$normalize_total(mdata1\$mod["rna"])
    scr\$pp\$log1p(mdata1\$mod["rna"])
    
    # 3. Subset to highly variable genes
    scr\$pp\$highly_variable_genes(
      mdata1\$mod["rna"],
      n_top_genes = 4000L,
      flavor = "seurat_v3",
      layer = "counts"
    )
    
    reticulate::py_run_string('r.mdata1.mod["rna_subset"] = r.mdata1.mod["rna"][:, r.mdata1.mod["rna"].var["highly_variable"]].copy()')
    mdata1 = MuDataR()\$MuData(mdata1\$mod)
    
    reticulate::py_run_string('r.mdata1["prot"].X = r.mdata1["prot"].X.toarray()')
    reticulate::py_run_string('r.mdata1["rna_subset"].X = r.mdata1["rna_subset"].X.toarray()')
    reticulate::py_run_string('r.mdata1.mod["rna_subset"].layers["counts"] = r.mdata1.mod["rna_subset"].layers["counts"].toarray()')
    mdata1\$update()
    
    # 4. Train TOTALVI
    scviR()\$model\$TOTALVI\$setup_mudata(
      mdata1,
      rna_layer = "counts",
      protein_layer = reticulate::py_none(),
      modalities = list("rna_layer" = "rna_subset", "protein_layer" = "prot", "batch_key" = "rna_subset")
    )
    
    model = scviR()\$model\$TOTALVI(mdata1)
    
    n_epochs = 50L
    acc = "cpu"
    tchk = try(reticulate::import("torch"))
    if (!inherits(tchk, "try-error") && tchk\$backends\$mps\$is_available()) acc = "mps"
    if (!inherits(tchk, "try-error") && tchk\$cuda\$is_available()) acc = "gpu"
    
    runtim = system.time(model\$train(max_epochs = n_epochs, accelerator = acc))
    
    # 5. Save outputs
    pdf("elbo_plot.pdf", width = 7, height = 6)
    total_ep = n_epochs
    val_elbo = unlist(model\$history\$elbo_validation)
    tr_elbo = model\$history\$elbo_train\$elbo_train
    plot(1:total_ep, tr_elbo, type="l", xlab="epoch", ylab="ELBO", ylim=c(0, 7000))
    lines(1:total_ep, val_elbo, col="blue")
    legend(3, 6000, col=c("black", "blue"), lty=1, legend=c("train", "validate"))
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
      process = "BIOC_SCVIR_CITESEQ_TOTALVI_TRAINING",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SCVIR_CITESEQ_TOTALVI_TRAINING":',
        paste0('    scviR: ', as.character(packageVersion('scviR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_citeseq_totalvi_training.csv versions.yml
    """
}

workflow BIOC_SCVIR_CITESEQ_TOTALVI_TRAINING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ HDP.h5 ] ]

    main:
    BIOC_SCVIR_CITESEQ_TOTALVI_TRAINING(ch_input)

    emit:
    tables   = BIOC_SCVIR_CITESEQ_TOTALVI_TRAINING.out.tables
    plots    = BIOC_SCVIR_CITESEQ_TOTALVI_TRAINING.out.plots
    objects  = BIOC_SCVIR_CITESEQ_TOTALVI_TRAINING.out.objects
    versions = BIOC_SCVIR_CITESEQ_TOTALVI_TRAINING.out.versions
}
