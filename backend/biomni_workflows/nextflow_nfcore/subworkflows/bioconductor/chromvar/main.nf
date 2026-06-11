#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chromVAR — chromvar_analysis_workflow
// Perform a complete chromatin accessibility variation analysis from peak and alignment files to identify motif-driven accessibility deviations across single cell
// Input: peaks.bed, alignments.bam, genome_sequence
// Container: quay.io/biocontainers/bioconductor-chromvar:1.32.0--r45ha27e39d_0
// R packages: BiocParallel, chromVAR, genome_package, Matrix, motifmatchr, SummarizedExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, Matrix, SummarizedExperiment, chromVAR, motifmatchr
// Visualizations: t-SNE plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read genomic peaks using getPeaks
//  * 2. [Visualization & Output] Read fragment counts from BAM files using getCounts to create a SummarizedExperiment
//  * 3. [Core Analysis] Add GC content bias to peaks using addGCBias
//  * 4. [Core Analysis] Filter low-quality samples using filterSamples and filter/resolve overlapping peaks using filterPeaks
//  * 5. [Core Analysis] Retrieve motif position weight matrices using getJasparMotifs and match them to peaks using matchMotifs
//  * 6. [Core Analysis] (Optional) Compute background peaks using getBackgroundPeaks
//  * 7. [Core Analysis] Compute bias-corrected deviations and Z-scores using computeDeviations
//  * 8. [Visualization & Output] Compute and plot annotation variability using computeVariability and plotVariability
//  * 9. [Visualization & Output] Project and visualize deviations in 2D space using deviationsTsne and plotDeviationsTsne

nextflow.enable.dsl = 2

process BIOC_CHROMVAR_CHROMVAR_ANALYSIS_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("BiocParallel", "chromVAR", "genome_package", "Matrix", "motifmatchr", "SummarizedExperiment")
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
        library(chromVAR)
        library(motifmatchr)
        library(Matrix)
        library(BiocParallel)
        
        # Set seed for reproducibility
        set.seed(2017)
        
        # Configure multiprocessing based on OS
        if (.Platform\$OS.type == "windows") {
          register(SnowParam(workers = 1, type = "SOCK"))
        } else {
          register(MulticoreParam(8))
        }
        
        # -----------------------------------------------------------------------------
        # 1. Read Genome Sequence Package
        # -----------------------------------------------------------------------------
        genome_file <- "genome_sequence"
        if (file.exists(genome_file)) {
          genome_package <- trimws(readLines(genome_file, n = 1))
          message("Loading genome package: ", genome_package)
          library(genome_package, character.only = TRUE)
          genome_obj <- get(genome_package)
        } else {
          stop("Required 'genome_sequence' file containing the BSgenome package name is missing.")
        }
        
        # -----------------------------------------------------------------------------
        # 2. Read Genomic Peaks
        # -----------------------------------------------------------------------------
        peakfile <- "peaks.bed"
        if (!file.exists(peakfile)) {
          stop("Required 'peaks.bed' file is missing.")
        }
        peaks <- getPeaks(peakfile, sort_peaks = TRUE)
        
        # -----------------------------------------------------------------------------
        # 3. Read Fragment Counts from BAM
        # -----------------------------------------------------------------------------
        bamfile <- "alignments.bam"
        if (!file.exists(bamfile)) {
          stop("Required 'alignments.bam' file is missing.")
        }
        
        fragment_counts <- getCounts(bamfile, 
                                     peaks, 
                                     paired = TRUE, 
                                     by_rg = TRUE, 
                                     format = "bam", 
                                     colData = DataFrame(celltype = "GM"))
        
        # Adapt the read object to match the vignette's variable name 'example_counts'
        example_counts <- fragment_counts
        
        # Ensure 'Cell_Type' column exists in colData for downstream plotting compatibility
        colData(example_counts)\$Cell_Type <- "GM"
        
        # -----------------------------------------------------------------------------
        # 4. Add GC Content Bias
        # -----------------------------------------------------------------------------
        example_counts <- addGCBias(example_counts, genome = genome_obj)
        
        # -----------------------------------------------------------------------------
        # 5. Filter Samples and Peaks
        # -----------------------------------------------------------------------------
        # Filter low-quality samples
        counts_filtered <- filterSamples(example_counts, shiny = FALSE)
        
        # Generate filtering plot
        filtering_plot <- filterSamplesPlot(example_counts, use_plotly = FALSE)
        
        # Save filtering plot
        pdf("filtering_plot.pdf")
        print(filtering_plot)
        dev.off()
        
        # Get indices of samples to keep
        ix <- filterSamples(example_counts, ix_return = TRUE, shiny = FALSE)
        
        # Filter and resolve overlapping peaks
        counts_filtered <- filterPeaks(counts_filtered, non_overlapping = TRUE)
        
        # -----------------------------------------------------------------------------
        # 6. Retrieve Motifs and Match to Peaks
        # -----------------------------------------------------------------------------
        motifs <- getJasparMotifs()
        
        motif_ix <- matchMotifs(motifs, counts_filtered, genome = genome_obj)
        
        kmer_ix <- matchKmers(6, counts_filtered, genome = genome_obj)
        
        # -----------------------------------------------------------------------------
        # 7. Compute Deviations and Background Peaks
        # -----------------------------------------------------------------------------
        # Compute initial deviations
        dev <- computeDeviations(object = counts_filtered, annotations = motif_ix)
        
        # Get background peaks
        bg <- getBackgroundPeaks(object = counts_filtered)
        
        # Compute deviations with background peaks
        dev <- computeDeviations(object = counts_filtered, annotations = motif_ix,
                                 background_peaks = bg)
        
        # Save deviations object
        saveRDS(dev, "deviations.rds")
        saveRDS(counts_filtered, "counts_filtered.rds")
        
        # -----------------------------------------------------------------------------
        # 8. Compute and Plot Variability
        # -----------------------------------------------------------------------------
        variability <- computeVariability(dev)
        write.csv(variability, "variability.csv", row.names = TRUE)
        
        pdf("variability_plot.pdf")
        print(plotVariability(variability, use_plotly = FALSE))
        dev.off()
        
        # -----------------------------------------------------------------------------
        # 9. Project and Visualize Deviations (t-SNE)
        # -----------------------------------------------------------------------------
        # Wrap t-SNE in tryCatch as it requires a minimum number of samples for perplexity=10
        tryCatch({
          tsne_results <- deviationsTsne(dev, threshold = 1.5, perplexity = 10)
          
          # Check if "TEAD3" motif is present in the annotations, otherwise fallback to the first available
          target_annotation <- "TEAD3"
          if (!(target_annotation %in% rowData(dev)\$name)) {
            target_annotation <- rowData(dev)\$name[1]
            message("TEAD3 motif not found. Falling back to first available motif: ", target_annotation)
          }
          
          tsne_plots <- plotDeviationsTsne(dev, tsne_results, 
                                           annotation_name = target_annotation, 
                                           sample_column = "Cell_Type", 
                                           shiny = FALSE)
          
          pdf("tsne_plots.pdf")
          print(tsne_plots[[1]])
          print(tsne_plots[[2]])
          dev.off()
        }, error = function(e) {
          warning("t-SNE projection/plotting skipped: ", e\$message)
        })
        
        message("chromVAR analysis workflow completed successfully.")

    writeLines(c(
        '"BIOC_CHROMVAR_CHROMVAR_ANALYSIS_WORKFLOW":',
        paste0('    chromVAR: ', as.character(packageVersion('chromVAR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chromvar_analysis_workflow.csv versions.yml
    """
}

workflow BIOC_CHROMVAR_CHROMVAR_ANALYSIS_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peaks.bed, alignments.bam, genome_sequence ] ]

    main:
    BIOC_CHROMVAR_CHROMVAR_ANALYSIS_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_CHROMVAR_CHROMVAR_ANALYSIS_WORKFLOW.out.tables
    plots    = BIOC_CHROMVAR_CHROMVAR_ANALYSIS_WORKFLOW.out.plots
    objects  = BIOC_CHROMVAR_CHROMVAR_ANALYSIS_WORKFLOW.out.objects
    versions = BIOC_CHROMVAR_CHROMVAR_ANALYSIS_WORKFLOW.out.versions
}
