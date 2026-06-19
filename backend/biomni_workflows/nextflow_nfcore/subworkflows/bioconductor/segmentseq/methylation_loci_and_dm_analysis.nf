#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: segmentseq — methylation_loci_and_dm_analysis
// Identify cytosine methylation loci from bisulphite sequencing data and perform differential methylation analysis.
// Input: short_18B_C24_C24_trim.fastq_CG_methCalls.gz, short_Sample_17A_trimmed.fastq_CG_methCalls.gz, short_13_C24_col_trim.fastq_CG_methCalls.gz, short_Sample_28_trimmed.fastq_CG_methCalls.gz
// Container: quay.io/biocontainers/bioconductor-segmentseq:2.44.0--r45hdfd78af_0
// R packages: segmentSeq
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_SEGMENTSEQ_METHYLATION_LOCI_AND_DM_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-segmentseq:2.44.0--r45hdfd78af_0"

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
    .bm_deps <- c("segmentSeq")
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
    library(segmentSeq)
    library(parallel)
    
    # Define cluster (using NULL as recommended for simplicity and stability, 
    # but can be replaced with a socket cluster if desired)
    cl <- NULL
    
    # Define input files in the current working directory
    datadir <- "."
    files <- c(
      "short_18B_C24_C24_trim.fastq_CG_methCalls.gz",
      "short_Sample_17A_trimmed.fastq_CG_methCalls.gz",
      "short_13_C24_col_trim.fastq_CG_methCalls.gz",
      "short_Sample_28_trimmed.fastq_CG_methCalls.gz"
    )
    
    # Verify that all required input files exist in the working directory
    for (f in files) {
      if (!file.exists(file.path(datadir, f))) {
        stop(paste("Required input file missing in working directory:", f))
      }
    }
    
    # --- Read methylation files using readMeths ---
    message("Reading methylation calls...")
    mD <- readMeths(
      files = files, 
      dir = datadir, 
      libnames = c("A1", "A2", "B1", "B2"), 
      replicates = c("A", "A", "B", "B"), 
      nonconversion = c(0.004777, 0.005903, 0.016514, 0.006134)
    )
    
    # --- Plot methylation distribution using plotMethDistribution ---
    message("Plotting methylation distributions...")
    pdf("methylation_distributions.pdf", width = 8, height = 10)
    par(mfrow = c(2, 1))
    dists <- plotMethDistribution(mD, main = "Distributions of methylation", chr = "Chr1")
    plotMethDistribution(
      mD, 
      subtract = rowMeans(sapply(dists, function(x) x[, 2])), 
      main = "Differences between distributions", 
      chr = "Chr1"
    )
    dev.off()
    
    # --- Process alignment data to find candidate loci using ---
    message("Processing alignment data to find candidate loci...")
    sD <- processAD(mD, cl = cl)
    
    # --- Perform heuristic segmentation using heuristicSeg ---
    message("Performing heuristic segmentation...")
    thresh <- 0.2
    hS <- heuristicSeg(sD = sD, aD = mD, prop = thresh, cl = cl, gap = 100, getLikes = FALSE)
    
    # --- Merge split loci using mergeMethSegs ---
    message("Merging split loci...")
    hS <- mergeMethSegs(hS, mD, gap = 5000, cl = cl)
    
    # --- Estimate posterior likelihoods on loci using ---
    message("Estimating posterior likelihoods on loci...")
    hSL <- lociLikelihoods(hS, mD, cl = cl)
    
    # --- Plot methylation loci using plotMeth ---
    message("Plotting methylation loci...")
    pdf("methylation_loci_plot.pdf", width = 10, height = 8)
    plotMeth(mD, hSL, chr = "Chr1", limits = c(1, 50000), cap = 10)
    dev.off()
    
    # --- Define experimental groups using groups ---
    message("Defining experimental groups...")
    groups(hSL) <- list(NDE = c(1, 1, 1, 1), DE = c("A", "A", "B", "B"))
    
    # --- Pre-calculate observables using methObservables ---
    message("Pre-calculating observables...")
    hSL <- methObservables(hSL)
    
    # --- Set density function to bbNCDist using densityFunction ---
    message("Setting density function...")
    densityFunction(hSL) <- bbNCDist
    
    # --- Estimate priors using getPriors ---
    message("Estimating priors...")
    hSL <- getPriors(hSL, cl = cl)
    
    # --- Estimate posterior likelihoods using getLikelihoods ---
    message("Estimating posterior likelihoods...")
    hSL <- getLikelihoods(hSL, cl = cl)
    
    # --- Retrieve top differentially methylated regions using ---
    message("Retrieving top differentially methylated regions...")
    de_loci <- topCounts(hSL, "DE")
    
    # Write outputs to files
    write.csv(de_loci, "differential_methylation_loci.csv", row.names = TRUE)
    saveRDS(hSL, "hSL_results.rds")
    
    # Clean up cluster if it was initialized
    if (!is.null(cl)) {
      stopCluster(cl)
    }
    
    message("Pipeline completed successfully. Outputs written to 'differential_methylation_loci.csv', 'hSL_results.rds', 'methylation_distributions.pdf', and 'methylation_loci_plot.pdf'.")

    writeLines(c(
        '"BIOC_SEGMENTSEQ_METHYLATION_LOCI_AND_DM_ANALYSIS":',
        paste0('        segmentseq: ', as.character(packageVersion("segmentseq")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methylation_loci_and_dm_analysis.csv versions.yml
    """
}

workflow BIOC_SEGMENTSEQ_METHYLATION_LOCI_AND_DM_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ short_18B_C24_C24_trim.fastq_CG_methCalls.gz, short_Sample_17A_trimmed.fastq_CG_methCalls.gz, short_13_C24_col_trim.fastq_CG_methCalls.gz, short_Sample_28_trimmed.fastq_CG_methCalls.gz ] ]

    main:
    BIOC_SEGMENTSEQ_METHYLATION_LOCI_AND_DM_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SEGMENTSEQ_METHYLATION_LOCI_AND_DM_ANALYSIS.out.tables
    plots    = BIOC_SEGMENTSEQ_METHYLATION_LOCI_AND_DM_ANALYSIS.out.plots
    objects  = BIOC_SEGMENTSEQ_METHYLATION_LOCI_AND_DM_ANALYSIS.out.objects
    versions = BIOC_SEGMENTSEQ_METHYLATION_LOCI_AND_DM_ANALYSIS.out.versions
}
