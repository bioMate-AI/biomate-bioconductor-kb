#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: strandcheckr — dna_contamination_analysis_and_filtering
// Quantify strand-specificity across sliding windows, intersect with transcript annotations, plot diagnostics, and filter out double-stranded DNA contamination fr
// Input: file.bam, file.bam.bai, annotation.gr
// Container: quay.io/biocontainers/bioconductor-strandcheckr:1.28.0--r45hdfd78af_0
// R packages: Rsamtools, ggplot2, strandCheckR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_STRANDCHECKR_DNA_CONTAMINATION_ANALYSIS_AND_FILTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-strandcheckr:1.28.0--r45hdfd78af_0"

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
    .bm_deps <- c("Rsamtools", "ggplot2", "strandCheckR")
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
    library(strandCheckR)
    library(Rsamtools)
    library(ggplot2)
    
    # Define input files
    bam_file <- "file.bam"
    annot_file <- "annotation.gr"
    
    # Verify input files exist
    if (!file.exists(bam_file)) {
        stop("Error: Input BAM file 'file.bam' not found.")
    }
    if (!file.exists(annot_file)) {
        stop("Error: Input annotation file 'annotation.gr' not found.")
    }
    
    # Read the GRanges annotation object
    annot <- readRDS(annot_file)
    
    # Extract sequence names from the BAM file header to scan
    bam_header <- scanBamHeader(bam_file)
    seq_names <- names(bam_header[[1]]\$targets)
    # Clean sequence names (remove 'chr' prefix if present, as getStrandFromBamFile expects)
    seq_names_clean <- gsub("^chr", "", seq_names)
    
    # --- Calculate strand-specific read counts and coverage across ---
    # We duplicate the bam_file in the vector so that files[2] is valid and points to our BAM,
    # matching the vignette's indexing style.
    files <- c(bam_file, bam_file)
    
    win <- getStrandFromBamFile(files, sequences = seq_names_clean)
    # shorten the file name
    win\$File <- basename(as.character(win\$File))
    
    # Write raw window stats
    write.csv(as.data.frame(win), "windows_raw.csv", row.names = FALSE)
    
    # Display windows with highest read counts
    high_cov <- head(win[order((win\$NbPos+win\$NbNeg),decreasing=TRUE),])
    write.csv(as.data.frame(high_cov), "highest_coverage_windows.csv", row.names = FALSE)
    
    # For the paired-end demonstration, we use the same input BAM file
    fileP <- bam_file
    winP <- getStrandFromBamFile(fileP, sequences = seq_names_clean)
    winP\$File <- basename(as.character(winP\$File)) #shorten file name
    
    # --- Intersect sliding windows with genomic annotations ---
    # Ensure sequence names are consistent (add 'chr' prefix)
    win\$Seq <- gsub("^chr", "", win\$Seq)
    win\$Seq <- paste0("chr",win\$Seq) 
    
    win <- intersectWithFeature(
        windows = win, annotation = annot, overlapCol = "OverlapTranscript"
        )
    
    # Save intersected windows
    write.csv(as.data.frame(win), "windows_intersected.csv", row.names = FALSE)
    saveRDS(win, "windows_intersected.rds")
    
    # --- Plot diagnostic plots ---
    pdf("diagnostic_plots.pdf", width = 10, height = 8)
    
    # Plot histogram of positive proportion
    p1 <- plotHist(
        windows = win, groupBy = c("File","OverlapTranscript"), 
        normalizeBy = "File", scales = "free_y"
        )
    print(p1)
    
    # Plot histogram for paired-end representation
    p2 <- plotHist(
        windows = winP, groupBy = "Type", normalizeBy = "Type", scales = "free_y"
        )
    print(p2)
    
    # Heatmap representation
    p3 <- plotHist(
        windows = win, groupBy = c("File","OverlapTranscript"), 
        normalizeBy = "File", heatmap = TRUE
        )
    print(p3)
    
    # Plot win (read count vs positive proportion)
    p4 <- plotWin(win, groupBy = "File")
    print(p4)
    
    dev.off()
    
    # --- Filter out double-stranded DNA contamination from the BAM ---
    filtered_bam <- "filtered.bam"
    win2 <- filterDNA(
        file = files[2], sequences = seq_names_clean, destination = filtered_bam, 
        threshold = 0.7, getWin = TRUE
        )
    
    win2\$File <- basename(as.character(win2\$File))
    
    # --- Compare window distributions before and after filtering ---
    original_name <- basename(files[2])
    win2\$File <- factor(win2\$File, levels = c(original_name, filtered_bam))
    
    pdf("filtering_comparison.pdf", width = 10, height = 8)
    p_comp <- plotHist(win2, groupBy = "File", normalizeBy = "File", scales = "free_y") +
        ggtitle("Histogram of positive proportions over all sliding windows before \nand after filtering reads coming from double strand DNA")
    print(p_comp)
    dev.off()
    
    # Save final window comparison data
    write.csv(as.data.frame(win2), "filtering_comparison_windows.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_STRANDCHECKR_DNA_CONTAMINATION_ANALYSIS_AND_FILTERING":',
        paste0('        strandcheckr: ', as.character(packageVersion("strandcheckr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dna_contamination_analysis_and_filtering.csv versions.yml
    """
}

workflow BIOC_STRANDCHECKR_DNA_CONTAMINATION_ANALYSIS_AND_FILTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ file.bam, file.bam.bai, annotation.gr ] ]

    main:
    BIOC_STRANDCHECKR_DNA_CONTAMINATION_ANALYSIS_AND_FILTERING(ch_input)

    emit:
    tables   = BIOC_STRANDCHECKR_DNA_CONTAMINATION_ANALYSIS_AND_FILTERING.out.tables
    plots    = BIOC_STRANDCHECKR_DNA_CONTAMINATION_ANALYSIS_AND_FILTERING.out.plots
    objects  = BIOC_STRANDCHECKR_DNA_CONTAMINATION_ANALYSIS_AND_FILTERING.out.objects
    versions = BIOC_STRANDCHECKR_DNA_CONTAMINATION_ANALYSIS_AND_FILTERING.out.versions
}
