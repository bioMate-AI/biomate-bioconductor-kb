#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ribosomeprofilingqc — floss_analysis
// Compare the distribution of read lengths to a reference background (e.g., protein-coding genes) to identify translation-like patterns.
// Input: pc, danrer10.annotations$protein, CDS
// Container: quay.io/biocontainers/bioconductor-ribosomeprofilingqc:1.22.0--r45hdfd78af_0
// R packages: ribosomeProfilingQC
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RIBOSOMEPROFILINGQC_FLOSS_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-ribosomeprofilingqc:1.22.0--r45hdfd78af_0"

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
    .bm_deps <- c("ribosomeProfilingQC")
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
    library(ribosomeProfilingQC)
    
    # Verify that the required user input files exist in the working directory
    required_files <- c("pc.rds", "danrer10.annotations.rds", "CDS.rds")
    missing_files <- required_files[!file.exists(required_files)]
    if (length(missing_files) > 0) {
      stop(paste("The following required input files are missing from the working directory:",
                 paste(missing_files, collapse = ", ")))
    }
    
    # Load user input files
    pc <- readRDS("pc.rds")
    danrer10.annotations <- readRDS("danrer10.annotations.rds")
    CDS <- readRDS("CDS.rds")
    
    # Define the read lengths to analyze (typically 20 to 34 nucleotides for ribosome profiling)
    readsLengths <- 20:34
    
    # 1. Calculate FLOSS scores using FLOSS
    fl <- FLOSS(pc, 
                ref = danrer10.annotations\$protein, 
                CDS = CDS, 
                readLengths = readsLengths, 
                level = "gene", 
                draw = FALSE)
    
    # Save the complete FLOSS results table
    write.csv(as.data.frame(fl), "floss_analysis_results.csv", row.names = TRUE)
    saveRDS(fl, "floss_analysis_results.rds")
    
    # 2. Extract and plot the gene with the maximum Cook's distance against the reference
    fl.max <- t(fl[c(1, which.max(fl\$cooks.distance)), as.character(readsLengths)])
    
    # Save the plot to a PDF file
    pdf("floss_max_cooks_distance_plot.pdf", width = 7, height = 7)
    matplot(fl.max, 
            type = "l", 
            x = readsLengths, 
            xlab = "Fragment Length", 
            ylab = "Fraction of Reads", 
            col = c("gray", "red"), 
            lwd = 2, 
            lty = 1)
    legend("topright", 
           legend = c("ref", "selected gene"), 
           col = c("gray", "red"), 
           lwd = 2, 
           lty = 1, 
           cex = 0.8)
    dev.off()
    
    # Save the extracted maximum Cook's distance data
    write.csv(as.data.frame(fl.max), "floss_max_gene_fractions.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_RIBOSOMEPROFILINGQC_FLOSS_ANALYSIS":',
        paste0('        ribosomeprofilingqc: ', as.character(packageVersion("ribosomeprofilingqc")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_floss_analysis.csv versions.yml
    """
}

workflow BIOC_RIBOSOMEPROFILINGQC_FLOSS_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pc, danrer10.annotations$protein, CDS ] ]

    main:
    BIOC_RIBOSOMEPROFILINGQC_FLOSS_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_RIBOSOMEPROFILINGQC_FLOSS_ANALYSIS.out.tables
    plots    = BIOC_RIBOSOMEPROFILINGQC_FLOSS_ANALYSIS.out.plots
    objects  = BIOC_RIBOSOMEPROFILINGQC_FLOSS_ANALYSIS.out.objects
    versions = BIOC_RIBOSOMEPROFILINGQC_FLOSS_ANALYSIS.out.versions
}
