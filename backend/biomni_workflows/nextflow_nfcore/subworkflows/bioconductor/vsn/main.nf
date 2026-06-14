#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: vsn — standard_microarray_normalization
// Calibrate and variance-stabilize microarray intensity data from ExpressionSet or matrix objects.
// Input: kidney, lymphoma
// Container: quay.io/biocontainers/bioconductor-vsn:3.78.1--r45h01b2380_0
// R packages: Biobase, affydata, ggplot2, limma, vsn
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, limma, vsn
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run one-step normalization with justvsn
//  * 2. [Core Analysis] Alternatively, run two-step normalization by fitting
//  * 3. [Core Analysis] Assess variance stabilization using meanSdPlot
//  * 4. [Core Analysis] Perform spike-in normalization or normalization without

nextflow.enable.dsl = 2

process BIOC_VSN_STANDARD_MICROARRAY_NORMALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
    .bm_deps <- c("Biobase", "affydata", "ggplot2", "limma", "vsn")
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
    
    # Load required Bioconductor and CRAN libraries
    library(vsn)
    library(Biobase)
    library(limma)
    
    # Read the declared USER INPUT files from the working directory.
    # We check for both extensionless filenames and '.rds' extensions.
    if (file.exists("kidney")) {
      kidney <- readRDS("kidney")
    } else if (file.exists("kidney.rds")) {
      kidney <- readRDS("kidney.rds")
    } else {
      stop("Error: 'kidney' input file not found in the working directory.")
    }
    
    if (file.exists("lymphoma")) {
      lymphoma <- readRDS("lymphoma")
    } else if (file.exists("lymphoma.rds")) {
      lymphoma <- readRDS("lymphoma.rds")
    } else {
      stop("Error: 'lymphoma' input file not found in the working directory.")
    }
    
    # --- Run one-step normalization with justvsn ---
    xnorm = justvsn(kidney)
    saveRDS(xnorm, "xnorm.rds")
    
    # Calculate generalized log-ratios
    M = exprs(xnorm)[,1] - exprs(xnorm)[,2]
    write.csv(data.frame(M = M), "M_log_ratios.csv", row.names = TRUE)
    
    # --- Alternatively, run two-step normalization by fitting ---
    fit = vsn2(kidney)
    saveRDS(fit, "fit.rds")
    
    ynorm = predict(fit, kidney)
    saveRDS(ynorm, "ynorm.rds")
    
    # --- Assess variance stabilization using meanSdPlot ---
    pdf("meanSdPlot_ranks_true.pdf")
    p1 = meanSdPlot(xnorm, ranks = TRUE)
    if (inherits(p1, "gg") || inherits(p1, "ggplot")) {
      print(p1)
    }
    dev.off()
    
    pdf("meanSdPlot_ranks_false.pdf")
    p2 = meanSdPlot(xnorm, ranks = FALSE)
    if (inherits(p2, "gg") || inherits(p2, "ggplot")) {
      print(p2)
    }
    dev.off()
    
    # --- Perform spike-in normalization or normalization without ---
    # Define spike-in indices (features 100 to 200 as documented in the vignette)
    # We ensure the indices do not exceed the number of rows in the kidney dataset
    max_spike <- min(200, nrow(kidney))
    spikeins = 100:max_spike
    
    spfit = vsn2(kidney[spikeins,], lts.quantile=1)
    saveRDS(spfit, "spfit.rds")
    
    nkid = predict(spfit, newdata=kidney)
    saveRDS(nkid, "nkid.rds")
    
    # Perform quantile normalization on lymphoma, then run VSN without calibration
    lym_q = normalizeQuantiles(exprs(lymphoma))
    lym_qvsn = vsn2(lym_q, calib="none")
    saveRDS(lym_qvsn, "lym_qvsn.rds")

    writeLines(c(
        '"BIOC_VSN_STANDARD_MICROARRAY_NORMALIZATION":',
        paste0('    vsn: ', as.character(packageVersion('vsn')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_microarray_normalization.csv versions.yml
    """
}

workflow BIOC_VSN_STANDARD_MICROARRAY_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ kidney, lymphoma ] ]

    main:
    BIOC_VSN_STANDARD_MICROARRAY_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_VSN_STANDARD_MICROARRAY_NORMALIZATION.out.tables
    plots    = BIOC_VSN_STANDARD_MICROARRAY_NORMALIZATION.out.plots
    objects  = BIOC_VSN_STANDARD_MICROARRAY_NORMALIZATION.out.objects
    versions = BIOC_VSN_STANDARD_MICROARRAY_NORMALIZATION.out.versions
}
