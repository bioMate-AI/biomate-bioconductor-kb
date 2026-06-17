#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: HiCDOC — hic_compartment_analysis_pipeline
// Import Hi-C data, filter out low-quality regions/replicates, normalize technical and biological biases, predict A/B compartments, detect significant changes bet
// Input: data.tsv, condition-1.replicate-1.cool, condition-1.replicate-1.hic, condition-1.replicate-1.matrix, condition-1.replicate-1.bed
// Container: quay.io/biocontainers/bioconductor-hicdoc:1.12.0--r45ha27e39d_0
// R packages: GenomicRanges, InteractionSet, HiCDOC
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, HiCDOC, InteractionSet
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Import Hi-C Data from Various Formats
//  * 2. [Visualization & Output] Filtering Data
//  * 3. [Visualization & Output] Normalizing Biases
//  * 4. [Visualization & Output] Predicting Compartments and Differences
//  * 5. [Visualization & Output] Extracting Results
//  * 6. [Visualization & Output] Visualizing Results

nextflow.enable.dsl = 2

process BIOC_HICDOC_HIC_COMPARTMENT_ANALYSIS_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("GenomicRanges", "InteractionSet", "HiCDOC")
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
        library(HiCDOC)
        library(GenomicRanges)
        library(InteractionSet)
        
        # ==========================================
        # --- Import Hi-C Data from Various Formats ---
        # ==========================================
        
        # Tabular import (Primary dataset for the pipeline)
        message("Importing tabular data...")
        hic.experiment <- HiCDOCDataSetFromTabular('data.tsv')
        
        # Cooler import (Demonstrating import with the single provided file)
        message("Importing Cooler data...")
        tryCatch({
            paths = c('condition-1.replicate-1.cool')
            replicates <- c(1)
            conditions <- c(1)
            binSize = 500000
            hic.experiment.cool <- HiCDOCDataSetFromCool(
                paths,
                replicates = replicates,
                conditions = conditions,
                binSize = binSize
            )
        }, error = function(e) {
            message("Cooler import skipped or failed: ", e\$message)
        })
        
        # Juicer import (Demonstrating import with the single provided file)
        message("Importing Juicer data...")
        tryCatch({
            paths = c('condition-1.replicate-1.hic')
            replicates <- c(1)
            conditions <- c(1)
            binSize <- 500000
            hic.experiment.hic <- HiCDOCDataSetFromHiC(
                paths,
                replicates = replicates,
                conditions = conditions,
                binSize = binSize
            )
        }, error = function(e) {
            message("Juicer import skipped or failed: ", e\$message)
        })
        
        # HiC-Pro import (Demonstrating import with the single provided files)
        message("Importing HiC-Pro data...")
        tryCatch({
            matrixPaths = c('condition-1.replicate-1.matrix')
            bedPaths = c('condition-1.replicate-1.bed')
            replicates <- c(1)
            conditions <- c(1)
            hic.experiment.hicpro <- HiCDOCDataSetFromHiCPro(
                matrixPaths = matrixPaths,
                bedPaths = bedPaths,
                replicates = replicates,
                conditions = conditions
            )
        }, error = function(e) {
            message("HiC-Pro import skipped or failed: ", e\$message)
        })
        
        
        # ==========================================
        # --- Filtering Data ---
        # ==========================================
        message("Filtering small chromosomes...")
        hic.experiment <- filterSmallChromosomes(hic.experiment, threshold = 100)
        
        message("Filtering sparse replicates...")
        hic.experiment <- filterSparseReplicates(hic.experiment, threshold = 0.3)
        
        message("Filtering weak positions...")
        hic.experiment <- filterWeakPositions(hic.experiment, threshold = 1)
        
        
        # ==========================================
        # --- Normalizing Biases ---
        # ==========================================
        message("Normalizing technical biases...")
        suppressWarnings(hic.experiment <- normalizeTechnicalBiases(hic.experiment))
        
        message("Normalizing biological biases...")
        hic.experiment <- normalizeBiologicalBiases(hic.experiment)
        
        message("Normalizing distance effect...")
        hic.experiment <- normalizeDistanceEffect(hic.experiment, loessSampleSize = 20000)
        
        
        # ==========================================
        # --- Predicting Compartments and Differences ---
        # ==========================================
        message("Predicting compartments and detecting differences...")
        hic.experiment <- detectCompartments(hic.experiment)
        
        # Save the processed experiment object
        saveRDS(hic.experiment, "hic_experiment_processed.rds")
        
        
        # ==========================================
        # --- Extracting Results ---
        # ==========================================
        message("Extracting and saving tabular results...")
        
        tryCatch({
            comp <- compartments(hic.experiment)
            write.csv(as.data.frame(comp), "compartments.csv", row.names = FALSE)
        }, error = function(e) {
            message("Could not extract compartments: ", e\$message)
        })
        
        tryCatch({
            conc <- concordances(hic.experiment)
            write.csv(as.data.frame(conc), "concordances.csv", row.names = FALSE)
        }, error = function(e) {
            message("Could not extract concordances: ", e\$message)
        })
        
        tryCatch({
            diffs <- differences(hic.experiment)
            write.csv(as.data.frame(diffs), "differences.csv", row.names = FALSE)
        }, error = function(e) {
            message("Could not extract differences: ", e\$message)
        })
        
        
        # ==========================================
        # --- Visualizing Results ---
        # ==========================================
        message("Generating visualization plots...")
        
        # Determine a valid chromosome for plotting
        plot_chrom <- "Y"
        tryCatch({
            comp_obj <- compartments(hic.experiment)
            if (length(comp_obj) > 0) {
                plot_chrom <- as.character(unique(seqnames(comp_obj)))[1]
            }
        }, error = function(e) {
            message("Could not determine chromosome for plotting, defaulting to 'Y'")
        })
        
        # Plot Interactions
        tryCatch({
            pdf(paste0("plot_interactions_", plot_chrom, ".pdf"))
            p <- plotInteractions(hic.experiment, chromosome = plot_chrom)
            print(p)
            dev.off()
        }, error = function(e) {
            if (dev.cur() > 1) dev.off()
            message("Failed to plot interactions: ", e\$message)
        })
        
        # Plot Distance Effect
        tryCatch({
            pdf("plot_distance_effect.pdf")
            p <- plotDistanceEffect(hic.experiment)
            print(p)
            dev.off()
        }, error = function(e) {
            if (dev.cur() > 1) dev.off()
            message("Failed to plot distance effect: ", e\$message)
        })
        
        # Plot Compartment Changes
        tryCatch({
            pdf(paste0("plot_compartment_changes_", plot_chrom, ".pdf"))
            p <- plotCompartmentChanges(hic.experiment, chromosome = plot_chrom)
            print(p)
            dev.off()
        }, error = function(e) {
            if (dev.cur() > 1) dev.off()
            message("Failed to plot compartment changes: ", e\$message)
        })
        
        # Plot Concordance Differences
        tryCatch({
            pdf("plot_concordance_differences.pdf")
            p <- plotConcordanceDifferences(hic.experiment)
            print(p)
            dev.off()
        }, error = function(e) {
            if (dev.cur() > 1) dev.off()
            message("Failed to plot concordance differences: ", e\$message)
        })
        
        # Plot Centroids
        tryCatch({
            pdf(paste0("plot_centroids_", plot_chrom, ".pdf"))
            p <- plotCentroids(hic.experiment, chromosome = plot_chrom)
            print(p)
            dev.off()
        }, error = function(e) {
            if (dev.cur() > 1) dev.off()
            message("Failed to plot centroids: ", e\$message)
        })
        
        # Plot Self-Interaction Ratios
        tryCatch({
            pdf(paste0("plot_self_interaction_ratios_", plot_chrom, ".pdf"))
            p <- plotSelfInteractionRatios(hic.experiment, chromosome = plot_chrom)
            print(p)
            dev.off()
        }, error = function(e) {
            if (dev.cur() > 1) dev.off()
            message("Failed to plot self-interaction ratios: ", e\$message)
        })
        
        message("Pipeline run completed successfully.")

    writeLines(c(
        '"BIOC_HICDOC_HIC_COMPARTMENT_ANALYSIS_PIPELINE":',
        paste0('    HiCDOC: ', as.character(packageVersion('HiCDOC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hic_compartment_analysis_pipeline.csv versions.yml
    """
}

workflow BIOC_HICDOC_HIC_COMPARTMENT_ANALYSIS_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data.tsv, condition-1.replicate-1.cool, condition-1.replicate-1.hic, condition-1.replicate-1.matrix, condition-1.replicate-1.bed ] ]

    main:
    BIOC_HICDOC_HIC_COMPARTMENT_ANALYSIS_PIPELINE(ch_input)

    emit:
    tables   = BIOC_HICDOC_HIC_COMPARTMENT_ANALYSIS_PIPELINE.out.tables
    plots    = BIOC_HICDOC_HIC_COMPARTMENT_ANALYSIS_PIPELINE.out.plots
    objects  = BIOC_HICDOC_HIC_COMPARTMENT_ANALYSIS_PIPELINE.out.objects
    versions = BIOC_HICDOC_HIC_COMPARTMENT_ANALYSIS_PIPELINE.out.versions
}
