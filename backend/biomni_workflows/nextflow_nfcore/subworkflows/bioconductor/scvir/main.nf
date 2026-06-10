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

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
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
