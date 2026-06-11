#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cafe — affy_cel_analysis
// Process raw Affymetrix CEL files to identify and visualize chromosomal and cytoband aberrations.
// Input: .CEL files
// Container: quay.io/biocontainers/bioconductor-cafe:1.46.0--r45hdfd78af_0
// R packages: CAFE, ggplot2
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CAFE_AFFY_CEL_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-cafe:1.46.0--r45hdfd78af_0"

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
    .bm_deps <- c("CAFE", "ggplot2")
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
    
    # 1. Load the CAFE library and set the working directory containing the CEL files.
    library(CAFE)
    library(ggplot2)
    
    # Use the current working directory where the user's CEL files are stored
    working_dir <- getwd()
    setwd(working_dir)
    
    # Verify that CEL files exist in the directory
    cel_files <- list.files(path = ".", pattern = "\\\\.[Cc][Ee][Ll]\$")
    if (length(cel_files) == 0) {
      stop("Error: No .CEL files found in the current working directory (", working_dir, "). Please place your Affymetrix CEL files here.")
    }
    
    message("Found ", length(cel_files), " CEL files. Processing...")
    
    # 2. Process raw CEL files to normalize, log2-transform, and filter probes.
    datalist <- ProcessCels()
    
    # Save the processed data list as an RDS object for reproducibility
    saveRDS(datalist, file = "processed_cafe_data.rds")
    
    # Determine available samples and dynamically set indices to avoid out-of-bounds errors
    sample_names <- names(datalist[[2]])
    n_samples <- length(sample_names)
    message("Successfully processed ", n_samples, " samples.")
    
    if (n_samples >= 3) {
      sam <- c(1, 3)
    } else {
      sam <- c(1)
    }
    
    if (n_samples >= 10) {
      plot_sam <- c(1, 3, 10)
    } else if (n_samples >= 3) {
      plot_sam <- c(1, 2, 3)
    } else {
      plot_sam <- seq_len(n_samples)
    }
    
    # 3. Perform chromosome-level statistical testing for gains or losses.
    message("Performing chromosome-level statistical testing...")
    
    tryCatch({
      stat_chr17_fisher <- chromosomeStats(datalist, chromNum=17, samples=sam, test="fisher", bonferroni=FALSE, enrichment="greater")
      write.csv(as.data.frame(stat_chr17_fisher), "chromosome_stats_chr17_fisher.csv")
    }, error = function(e) {
      message("Warning: chromosomeStats for Chr17 (Fisher) failed: ", e\$message)
    })
    
    tryCatch({
      stat_chr17_chisqr <- chromosomeStats(datalist, chromNum=17, samples=sam, test="chisqr", bonferroni=FALSE, enrichment="greater")
      write.csv(as.data.frame(stat_chr17_chisqr), "chromosome_stats_chr17_chisqr.csv")
    }, error = function(e) {
      message("Warning: chromosomeStats for Chr17 (Chi-sq) failed: ", e\$message)
    })
    
    tryCatch({
      stat_chrALL_fisher <- chromosomeStats(datalist, chromNum="ALL", samples=sam, test="fisher", bonferroni=TRUE, enrichment="greater")
      write.csv(as.data.frame(stat_chrALL_fisher), "chromosome_stats_all_fisher.csv")
    }, error = function(e) {
      message("Warning: chromosomeStats for ALL chromosomes failed: ", e\$message)
    })
    
    # 4. Perform cytoband-level statistical testing to identify specific aberrant bands.
    message("Performing cytoband-level statistical testing...")
    tryCatch({
      stat_band17_fisher <- bandStats(datalist, chromNum=17, samples=sam, test="fisher", bonferroni=TRUE, enrichment="greater")
      write.csv(as.data.frame(stat_band17_fisher), "band_stats_chr17_fisher.csv")
    }, error = function(e) {
      message("Warning: bandStats for Chr17 failed: ", e\$message)
    })
    
    # 5. Generate raw, sliding average, discontinuous (Potts filter), and genome-wide facet plots.
    message("Generating visualization plots...")
    pdf("cafe_visualization_plots.pdf", width = 11, height = 8.5)
    
    # Raw Plot
    tryCatch({
      p <- rawPlot(datalist, samples=plot_sam, chromNum=17)
      print(p)
    }, error = function(e) {
      message("Warning: rawPlot failed: ", e\$message)
    })
    
    # Sliding Plot
    tryCatch({
      p <- slidPlot(datalist, samples=plot_sam, chromNum=17, k=100)
      print(p)
    }, error = function(e) {
      message("Warning: slidPlot failed: ", e\$message)
    })
    
    # Discontinuous Plot
    tryCatch({
      p <- discontPlot(datalist, samples=plot_sam, chromNum=17, gamma=100)
      print(p)
    }, error = function(e) {
      message("Warning: discontPlot failed: ", e\$message)
    })
    
    # Facet Plot
    tryCatch({
      p <- facetPlot(datalist, samples=plot_sam, slid=TRUE, combine=TRUE, k=100)
      print(p)
    }, error = function(e) {
      message("Warning: facetPlot failed: ", e\$message)
    })
    
    dev.off()
    message("Pipeline complete. Outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_CAFE_AFFY_CEL_ANALYSIS":',
        paste0('        cafe: ', as.character(packageVersion("cafe")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_affy_cel_analysis.csv versions.yml
    """
}

workflow BIOC_CAFE_AFFY_CEL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ .CEL files ] ]

    main:
    BIOC_CAFE_AFFY_CEL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CAFE_AFFY_CEL_ANALYSIS.out.tables
    plots    = BIOC_CAFE_AFFY_CEL_ANALYSIS.out.plots
    objects  = BIOC_CAFE_AFFY_CEL_ANALYSIS.out.objects
    versions = BIOC_CAFE_AFFY_CEL_ANALYSIS.out.versions
}
