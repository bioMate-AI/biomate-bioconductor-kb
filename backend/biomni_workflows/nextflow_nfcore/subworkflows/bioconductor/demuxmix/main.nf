#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: demuxmix — standard_hto_demultiplexing
// Demultiplex pooled single-cell samples labeled with multiple hashtag oligonucleotides (HTOs) using regression or naive mixture models.
// Input: hto, rna
// Container: quay.io/biocontainers/bioconductor-demuxmix:1.12.0--r45hdfd78af_0
// R packages: biocmanager, cowplot, demuxmix, DropletUtils, ggplot2, reshape2
// Bioconductor: 3.20 | R: 4.4
// Requires: demuxmix, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit mixture models using demuxmix
//  * 2. [Visualization & Output] Summarize model fit and error rates using summary
//  * 3. [Core Analysis] Classify droplets into singlets, multiplets, negatives, or uncertain using dmmClassify
//  * 4. [Visualization & Output] Perform quality control using plotDmmHistogram, dmmOverlap, plotDmmPosteriorP, and plotDmmScatter
//  * 5. [Core Analysis] Adjust classification confidence threshold using pAcpt if necessary

nextflow.enable.dsl = 2

process BIOC_DEMUXMIX_STANDARD_HTO_DEMULTIPLEXING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-single_cell:3.20"

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
    .bm_deps <- c("biocmanager", "cowplot", "demuxmix", "DropletUtils", "ggplot2", "reshape2")
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
    library(demuxmix)
    library(ggplot2)
    
    # ----------------------------------------------------------------------
    # 1. Read User Input Files
    # ----------------------------------------------------------------------
    # The pipeline expects 'hto' (matrix of raw HTO counts, HTOs x cells)
    # and 'rna' (vector of the number of detected genes per droplet)
    # in the working directory.
    
    if (file.exists("hto.rds")) {
      hto <- readRDS("hto.rds")
    } else if (file.exists("hto.csv")) {
      hto <- as.matrix(read.csv("hto.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("hto.tsv")) {
      hto <- as.matrix(read.delim("hto.tsv", row.names = 1, check.names = FALSE))
    } else {
      stop("Error: HTO input file (hto.rds, hto.csv, or hto.tsv) not found in the working directory.")
    }
    
    if (file.exists("rna.rds")) {
      rna <- readRDS("rna.rds")
    } else if (file.exists("rna.csv")) {
      rna_df <- read.csv("rna.csv", header = FALSE)
      if (ncol(rna_df) > 1) {
        rna <- as.numeric(rna_df[, 2])
        names(rna) <- rna_df[, 1]
      } else {
        rna <- as.numeric(rna_df[, 1])
      }
    } else if (file.exists("rna.txt")) {
      rna <- as.numeric(readLines("rna.txt"))
    } else {
      stop("Error: RNA input file (rna.rds, rna.csv, or rna.txt) not found in the working directory.")
    }
    
    # Ensure rna vector is aligned with hto columns
    if (length(rna) != ncol(hto)) {
      stop(sprintf("Error: Number of elements in 'rna' (%d) does not match number of columns in 'hto' (%d).", length(rna), ncol(hto)))
    }
    if (!is.null(colnames(hto)) && is.null(names(rna))) {
      names(rna) <- colnames(hto)
    }
    
    # ----------------------------------------------------------------------
    # 2. Execute Documented Workflow
    # ----------------------------------------------------------------------
    
    # Fit regression mixture model (default)
    dmm <- demuxmix(hto, rna = rna)
    
    # Summarize model fit and error rates
    dmm_summary_initial <- summary(dmm)
    write.csv(dmm_summary_initial, "summary_dmm_regression_initial.csv", row.names = FALSE)
    
    # Classify droplets into singlets, multiplets, negatives, or uncertain
    classes <- dmmClassify(dmm)
    write.csv(classes, "classification_regression.csv", row.names = TRUE)
    
    # Table of classifications
    class_table <- table(classes\$HTO)
    write.table(as.data.frame(class_table), "classification_table_regression.txt", sep = "\t", row.names = FALSE)
    
    # Set up PDF for quality control plots
    pdf("demuxmix_qc_plots.pdf", width = 10, height = 8)
    
    # Plot 1: Density histograms overlayed with mixture probability mass function
    p_hist <- plotDmmHistogram(dmm)
    if (inherits(p_hist, "ggplot") || inherits(p_hist, "gg")) {
      print(p_hist)
    }
    
    # Fit naive mixture model (does not use RNA data)
    dmmNaive <- demuxmix(hto, model = "naive")
    
    # Classify using naive model
    classLabelsNaive <- dmmClassify(dmmNaive)
    write.csv(classLabelsNaive, "classification_naive.csv", row.names = TRUE)
    
    # Summarize naive model fit
    dmm_summary_naive <- summary(dmmNaive)
    write.csv(dmm_summary_naive, "summary_dmm_naive.csv", row.names = FALSE)
    
    # Adjust classification confidence threshold using pAcpt
    p_acpt_initial <- pAcpt(dmm)
    writeLines(as.character(p_acpt_initial), "pAcpt_initial.txt")
    
    pAcpt(dmm) <- 0.95
    
    dmm_summary_adj <- summary(dmm)
    write.csv(dmm_summary_adj, "summary_dmm_regression_adjusted.csv", row.names = FALSE)
    
    # Calculate overlap between components
    overlap_vals <- dmmOverlap(dmm)
    write.csv(as.data.frame(t(overlap_vals)), "dmm_overlap.csv", row.names = FALSE)
    
    # Plot 2: Histograms of posterior probabilities
    p_post <- plotDmmPosteriorP(dmm)
    if (inherits(p_post, "ggplot") || inherits(p_post, "gg")) {
      print(p_post)
    }
    
    # Plot 3: Decision boundary (only available for regression mixture models)
    p_scatter <- tryCatch({
      plotDmmScatter(dmm)
    }, error = function(e) {
      message("Could not plot decision boundary: ", e\$message)
      NULL
    })
    if (!is.null(p_scatter) && (inherits(p_scatter, "ggplot") || inherits(p_scatter, "gg"))) {
      print(p_scatter)
    }
    
    dev.off()
    
    # Save fitted model objects for downstream analysis
    saveRDS(dmm, "dmm_regression_model.rds")
    saveRDS(dmmNaive, "dmm_naive_model.rds")
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_DEMUXMIX_STANDARD_HTO_DEMULTIPLEXING":',
        paste0('    demuxmix: ', as.character(packageVersion('demuxmix')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_hto_demultiplexing.csv versions.yml
    """
}

workflow BIOC_DEMUXMIX_STANDARD_HTO_DEMULTIPLEXING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hto, rna ] ]

    main:
    BIOC_DEMUXMIX_STANDARD_HTO_DEMULTIPLEXING(ch_input)

    emit:
    tables   = BIOC_DEMUXMIX_STANDARD_HTO_DEMULTIPLEXING.out.tables
    plots    = BIOC_DEMUXMIX_STANDARD_HTO_DEMULTIPLEXING.out.plots
    objects  = BIOC_DEMUXMIX_STANDARD_HTO_DEMULTIPLEXING.out.objects
    versions = BIOC_DEMUXMIX_STANDARD_HTO_DEMULTIPLEXING.out.versions
}
