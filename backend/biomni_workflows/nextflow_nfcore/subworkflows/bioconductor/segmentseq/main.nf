#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: segmentseq — small_rna_loci_and_de_analysis
// Identify small RNA loci from alignment files and perform differential expression analysis across replicate groups.
// Input: SL9.txt, SL10.txt, SL26.txt, SL32.txt
// Container: quay.io/biocontainers/bioconductor-segmentseq:2.44.0--r45hdfd78af_0
// R packages: segmentSeq
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_SEGMENTSEQ_SMALL_RNA_LOCI_AND_DE_ANALYSIS {
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
    library(segmentSeq)
    library(parallel)
    
    # Set up cluster (NULL for non-parallel processing to ensure stability)
    cl <- NULL
    
    # Define input files and parameters
    datadir <- "."
    libfiles <- c("SL9.txt", "SL10.txt", "SL26.txt", "SL32.txt")
    libnames <- c("SL9", "SL10", "SL26", "SL32")
    replicates <- c("AGO6", "AGO6", "AGO4", "AGO4")
    
    # --- Read alignment files using readGeneric ---
    message("Reading generic alignment files...")
    aD <- readGeneric(files = libfiles, dir = datadir, replicates = replicates, libnames = libnames, polyLength = 10, header = TRUE, gap = 200)
    saveRDS(aD, "alignment_data.rds")
    
    # --- Process alignment data to find candidate loci using ---
    message("Processing alignment data...")
    sD <- processAD(aD, cl = cl)
    saveRDS(sD, "processed_alignment_data.rds")
    
    # --- Perform heuristic segmentation using heuristicSeg ---
    message("Running heuristic segmentation...")
    hS <- heuristicSeg(sD = sD, aD = aD, RKPM = 1000, largeness = 1e8, getLikes = TRUE, cl = cl)
    saveRDS(hS, "heuristic_segmentation.rds")
    
    # --- Perform empirical Bayesian segmentation using classifySeg ---
    message("Running empirical Bayesian classification...")
    cS <- classifySeg(sD = sD, aD = aD, cD = hS, cl = cl)
    saveRDS(cS, "classified_segmentation.rds")
    
    # --- Plot the segmented genome using plotGenome ---
    message("Plotting segmented genome...")
    pdf("segmented_genome_plots.pdf", width = 10, height = 8)
    par(mfrow = c(2,1), mar = c(2,6,2,2))
    plotGenome(aD, hS, chr = ">Chr1", limits = c(1, 1e5), showNumber = FALSE, cap = 50)
    plotGenome(aD, cS, chr = ">Chr1", limits = c(1, 1e5), showNumber = FALSE, cap = 50)
    dev.off()
    
    # --- Select high-confidence loci using selectLoci ---
    message("Selecting high-confidence loci...")
    loci <- selectLoci(cS, FDR = 0.05)
    saveRDS(loci, "selected_loci.rds")
    if (inherits(loci, "lociData") || inherits(loci, "GRanges")) {
      write.csv(as.data.frame(loci), "selected_loci.csv", row.names = FALSE)
    }
    
    # --- Define experimental groups using groups ---
    message("Defining experimental groups...")
    groups(cS) <- list(NDE = c(1,1,1,1), DE = c("AGO6", "AGO6", "AGO4", "AGO4"))
    
    # --- Estimate priors using getPriors ---
    message("Estimating priors...")
    cS <- getPriors(cS, cl = cl)
    
    # --- Estimate posterior likelihoods using getLikelihoods ---
    message("Estimating posterior likelihoods...")
    cS <- getLikelihoods(cS, nullData = TRUE, cl = cl)
    saveRDS(cS, "final_classified_seg_with_likelihoods.rds")
    
    # --- Retrieve top differentially expressed loci using topCounts ---
    message("Retrieving top counts and saving results...")
    top_null <- topCounts(cS, NULL, number = 3)
    top_nde <- topCounts(cS, "NDE", number = 3)
    top_de <- topCounts(cS, "DE", number = 3)
    
    write.csv(top_null, "top_null_loci.csv", row.names = TRUE)
    write.csv(top_nde, "top_nde_loci.csv", row.names = TRUE)
    write.csv(top_de, "top_de_loci.csv", row.names = TRUE)
    
    # Clean up cluster if it was initialized
    if(!is.null(cl)) {
      stopCluster(cl)
    }
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_SEGMENTSEQ_SMALL_RNA_LOCI_AND_DE_ANALYSIS":',
        paste0('        segmentseq: ', as.character(packageVersion("segmentseq")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_small_rna_loci_and_de_analysis.csv versions.yml
    """
}

workflow BIOC_SEGMENTSEQ_SMALL_RNA_LOCI_AND_DE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SL9.txt, SL10.txt, SL26.txt, SL32.txt ] ]

    main:
    BIOC_SEGMENTSEQ_SMALL_RNA_LOCI_AND_DE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SEGMENTSEQ_SMALL_RNA_LOCI_AND_DE_ANALYSIS.out.tables
    plots    = BIOC_SEGMENTSEQ_SMALL_RNA_LOCI_AND_DE_ANALYSIS.out.plots
    objects  = BIOC_SEGMENTSEQ_SMALL_RNA_LOCI_AND_DE_ANALYSIS.out.objects
    versions = BIOC_SEGMENTSEQ_SMALL_RNA_LOCI_AND_DE_ANALYSIS.out.versions
}
