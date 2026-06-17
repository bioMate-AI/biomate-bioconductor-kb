#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: made4 — supervised_and_unsupervised_ordination
// Perform unsupervised ordination (Correspondence Analysis/PCA) and supervised Between Group Analysis (BGA) to identify discriminating genes and classify samples 
// Input: counts.csv, coldata.csv
// Container: 1.84.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ade4, made4, scatterplot3d
// Visualizations: heat plot, ordination plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MADE4_SUPERVISED_AND_UNSUPERVISED_ORDINATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("made4", "ade4", "scatterplot3d")
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
    library(made4)
    library(ade4)
    library(scatterplot3d)
    
    # ---------------------------------------------------------
    # --- Load and Preprocess Data ---
    # ---------------------------------------------------------
    # Read expression matrix (probe/gene-by-sample) and sample metadata
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Align samples between expression matrix and metadata
    common_samples <- intersect(colnames(counts), coldata\$sample)
    if (length(common_samples) == 0) {
        stop("Error: No matching samples found between counts.csv and coldata.csv")
    }
    counts <- counts[, common_samples, drop = FALSE]
    coldata <- coldata[match(common_samples, coldata\$sample), ]
    
    # Convert condition to factor for classification
    classvec <- as.factor(coldata\$condition)
    
    # Convert expression data to a data frame suitable for made4/ade4
    counts_df <- made4::asDataFrame(counts)
    
    # Determine appropriate ordination type: Correspondence Analysis (COA) 
    # requires non-negative values. Fall back to PCA if negative values exist.
    ord_type <- "pca"
    if (all(counts_df >= 0)) {
        ord_type <- "coa"
    }
    message(paste("Using ordination type:", ord_type))
    
    # ---------------------------------------------------------
    # --- Diagnostic Overview (QC) ---
    # ---------------------------------------------------------
    pdf("overview_plot.pdf", width = 8, height = 6)
    tryCatch({
        made4::overview(counts_df, classvec = classvec, labels = classvec)
    }, error = function(e) {
        warning("Overview plot failed: ", e\$message)
        plot.new()
        text(0.5, 0.5, "Overview Plot Failed", cex = 1.5)
    })
    dev.off()
    
    # ---------------------------------------------------------
    # --- Unsupervised Ordination ---
    # ---------------------------------------------------------
    k.coa <- made4::ord(counts_df, type = ord_type)
    
    pdf("ordination_plot.pdf", width = 8, height = 8)
    tryCatch({
        plot(k.coa, classvec = classvec)
    }, error = function(e) {
        warning("Ordination plot failed: ", e\$message)
        plot.new()
        text(0.5, 0.5, "Ordination Plot Failed", cex = 1.5)
    })
    dev.off()
    
    # Extract top discriminating genes from unsupervised ordination
    top_neg <- tryCatch(made4::topgenes(k.coa, axis = 1, n = 10, end = "neg"), error = function(e) NULL)
    top_pos <- tryCatch(made4::topgenes(k.coa, axis = 1, n = 10, end = "pos"), error = function(e) NULL)
    
    top_df <- data.frame(
        Direction = c(rep("Negative", length(top_neg)), rep("Positive", length(top_pos))),
        Gene = c(top_neg, top_pos)
    )
    write.csv(top_df, "top_genes.csv", row.names = FALSE)
    
    # ---------------------------------------------------------
    # --- Supervised Between Group Analysis (BGA) ---
    # ---------------------------------------------------------
    k.bga <- made4::bga(counts_df, type = ord_type, classvec = classvec)
    
    pdf("bga_plot.pdf", width = 8, height = 8)
    tryCatch({
        plot(k.bga)
    }, error = function(e) {
        warning("BGA plot failed: ", e\$message)
        plot.new()
        text(0.5, 0.5, "BGA Plot Failed", cex = 1.5)
    })
    
    tryCatch({
        made4::between.graph(k.bga, ax = 1)
    }, error = function(e) {
        warning("Between graph failed: ", e\$message)
    })
    dev.off()
    
    # Run Jackknife cross-validation for BGA
    jack_res <- tryCatch({
        made4::bga.jackknife(counts_df, classvec = classvec, type = ord_type)
    }, error = function(e) {
        NULL
    })
    
    if (!is.null(jack_res)) {
        sink("jackknife_results.txt")
        print(jack_res)
        sink()
    } else {
        writeLines("Jackknife cross-validation could not be computed (possibly due to small sample size).", "jackknife_results.txt")
    }
    
    # ---------------------------------------------------------
    # --- Heatmap and 3D Visualizations ---
    # ---------------------------------------------------------
    pdf("heatplot.pdf", width = 8, height = 8)
    tryCatch({
        made4::heatplot(counts_df, classvec = classvec)
    }, error = function(e) {
        warning("Heatplot failed: ", e\$message)
        plot.new()
        text(0.5, 0.5, "Heatplot Failed", cex = 1.5)
    })
    dev.off()
    
    pdf("do3d_plot.pdf", width = 8, height = 8)
    tryCatch({
        made4::do3d(k.coa\$ord\$co, classvec = classvec, cex.symbols = 2)
    }, error = function(e) {
        warning("do3d failed: ", e\$message)
        plot.new()
        text(0.5, 0.5, "3D Plot Failed", cex = 1.5)
    })
    dev.off()
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_MADE4_SUPERVISED_AND_UNSUPERVISED_ORDINATION":',
        paste0('    made4: ', as.character(packageVersion('made4')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_supervised_and_unsupervised_ordination.csv versions.yml
    """
}

workflow BIOC_MADE4_SUPERVISED_AND_UNSUPERVISED_ORDINATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_MADE4_SUPERVISED_AND_UNSUPERVISED_ORDINATION(ch_input)

    emit:
    tables   = BIOC_MADE4_SUPERVISED_AND_UNSUPERVISED_ORDINATION.out.tables
    plots    = BIOC_MADE4_SUPERVISED_AND_UNSUPERVISED_ORDINATION.out.plots
    objects  = BIOC_MADE4_SUPERVISED_AND_UNSUPERVISED_ORDINATION.out.objects
    versions = BIOC_MADE4_SUPERVISED_AND_UNSUPERVISED_ORDINATION.out.versions
}
