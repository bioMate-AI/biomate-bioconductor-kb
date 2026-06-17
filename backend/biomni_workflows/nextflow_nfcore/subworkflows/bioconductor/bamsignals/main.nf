#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: bamsignals — bamsignals_profiling_pipeline
// Extract high-resolution read counts, strand-specific profiles, and coverage signals from BAM files across genomic regions of interest.
// Input: regions.bed, coldata.csv
// Container: 1.42.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, Rsamtools, bamsignals, rtracklayer
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BAMSIGNALS_BAMSIGNALS_PROFILING_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("GenomicRanges", "Rsamtools", "bamsignals", "rtracklayer")
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
    library(GenomicRanges)
    library(Rsamtools)
    library(bamsignals)
    library(rtracklayer)
    
    # ==========================================
    # --- Load Input Data and Metadata ---
    # ==========================================
    message("Stage 1: Loading input regions and sample metadata...")
    
    if (!file.exists("regions.bed")) {
        stop("Required input file 'regions.bed' is missing.")
    }
    
    # Import genomic intervals
    regions <- rtracklayer::import.bed("regions.bed")
    message(paste("Loaded", length(regions), "regions from regions.bed"))
    
    # Load metadata
    if (file.exists("coldata.csv")) {
        coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
        message("Loaded coldata.csv metadata.")
    } else {
        message("coldata.csv not found. Scanning current directory for BAM files...")
        bam_files <- list.files(pattern = "\\\\.bam\$")
        if (length(bam_files) == 0) {
            stop("No BAM files found in the working directory and coldata.csv is missing.")
        }
        coldata <- data.frame(
            sample_id = paste0("sample_", seq_along(bam_files)),
            bam_path = bam_files,
            paired_end = FALSE,
            stringsAsFactors = FALSE
        )
    }
    
    # Validate BAM files and ensure they are indexed
    for (i in seq_len(nrow(coldata))) {
        bam <- coldata\$bam_path[i]
        if (!file.exists(bam)) {
            stop(paste("BAM file does not exist:", bam))
        }
        # bamsignals requires the index to have the ".bam.bai" suffix
        bai <- paste0(bam, ".bai")
        if (!file.exists(bai)) {
            message(paste("Index missing. Indexing BAM file:", bam))
            Rsamtools::indexBam(bam)
        }
    }
    
    # ==========================================
    # --- Basic and Strand-Specific Counting ---
    # ==========================================
    message("Stage 2: Computing read counts across regions...")
    
    counts_list <- list()
    ss_counts_list <- list()
    
    for (i in seq_len(nrow(coldata))) {
        bam <- coldata\$bam_path[i]
        sample_id <- coldata\$sample_id[i]
        
        # Determine paired-end handling strategy
        pe_mode <- "ignore"
        if ("paired_end" %in% colnames(coldata)) {
            val <- coldata\$paired_end[i]
            if (is.logical(val)) {
                pe_mode <- if (val) "filter" else "ignore"
            } else if (is.character(val)) {
                pe_mode <- val
            }
        }
        
        # Determine fragment length filter if specified
        tlen_filter <- NULL
        if ("tlen_min" %in% colnames(coldata) && "tlen_max" %in% colnames(coldata)) {
            tlen_filter <- c(coldata\$tlen_min[i], coldata\$tlen_max[i])
        }
    
        # 1. Basic counting (5' end of reads)
        counts_list[[sample_id]] <- bamCount(
            bam,
            regions,
            mapq = 20,
            paired.end = pe_mode,
            tlenFilter = tlen_filter,
            verbose = FALSE
        )
        
        # 2. Strand-specific counting
        ss_counts <- bamCount(
            bam,
            regions,
            mapq = 20,
            paired.end = pe_mode,
            tlenFilter = tlen_filter,
            ss = TRUE,
            verbose = FALSE
        )
        
        ss_counts_list[[paste0(sample_id, "_sense")]] <- ss_counts["sense", ]
        ss_counts_list[[paste0(sample_id, "_antisense")]] <- ss_counts["antisense", ]
    }
    
    # Save count matrices
    counts_df <- as.data.frame(counts_list)
    if (!is.null(regions\$name) && length(regions\$name) == nrow(counts_df)) {
        rownames(counts_df) <- regions\$name
    } else {
        rownames(counts_df) <- paste0("region_", seq_len(nrow(counts_df)))
    }
    write.csv(counts_df, "region_counts.csv", row.names = TRUE)
    
    ss_counts_df <- as.data.frame(ss_counts_list)
    rownames(ss_counts_df) <- rownames(counts_df)
    write.csv(ss_counts_df, "region_strand_counts.csv", row.names = TRUE)
    
    # ==========================================
    # --- High-Resolution Profiling & Alignment ---
    # ==========================================
    message("Stage 3: Generating high-resolution profiles...")
    
    # Standardize regions to a fixed width around their center to allow alignment
    fixed_width <- 200
    fixed_regions <- GenomicRanges::resize(regions, width = fixed_width, fix = "center")
    
    # Open PDF for diagnostic plots
    pdf("signal_profiles.pdf", width = 10, height = 8)
    
    binned_profiles_list <- list()
    
    for (i in seq_len(nrow(coldata))) {
        bam <- coldata\$bam_path[i]
        sample_id <- coldata\$sample_id[i]
        
        pe_mode <- "ignore"
        if ("paired_end" %in% colnames(coldata)) {
            val <- coldata\$paired_end[i]
            if (is.logical(val)) {
                pe_mode <- if (val) "filter" else "ignore"
            } else if (is.character(val)) {
                pe_mode <- val
            }
        }
        
        tlen_filter <- NULL
        if ("tlen_min" %in% colnames(coldata) && "tlen_max" %in% colnames(coldata)) {
            tlen_filter <- c(coldata\$tlen_min[i], coldata\$tlen_max[i])
        }
    
        # 1. Extract strand-specific profiles
        sigs <- bamProfile(
            bam,
            fixed_regions,
            ss = TRUE,
            paired.end = pe_mode,
            tlenFilter = tlen_filter,
            verbose = FALSE
        )
        
        # Align signals to get a 3D array [strand, base_pair, region]
        sigs_arr <- alignSignals(sigs)
        
        # Extract and average across all regions
        sense_mat <- sigs_arr["sense", , , drop = TRUE]
        antisense_mat <- sigs_arr["antisense", , , drop = TRUE]
        
        avg_sense <- rowMeans(sense_mat)
        avg_antisense <- rowMeans(antisense_mat)
        avg_total <- avg_sense + avg_antisense
        
        # Plot average read profile
        xs <- seq(-fixed_width/2, (fixed_width/2) - 1)
        plot(xs, avg_total, type = "l", col = "black", lwd = 2,
             xlab = "Distance from Center (bp)",
             ylab = "Average Counts per Base Pair",
             main = paste("Read Profile:", sample_id),
             ylim = c(0, max(avg_total, 1) * 1.2))
        lines(xs, avg_sense, col = "blue", lty = 2)
        lines(xs, avg_antisense, col = "red", lty = 2)
        legend("topright", legend = c("Total", "Sense", "Antisense"),
               col = c("black", "blue", "red"), lty = c(1, 2, 2), lwd = c(2, 1, 1))
        
        # 2. Extract full coverage profiles
        cov_pe_mode <- if (pe_mode %in% c("filter", "midpoint", "extend")) "extend" else "ignore"
        cov_sigs <- bamCoverage(
            bam,
            fixed_regions,
            paired.end = cov_pe_mode,
            tlenFilter = tlen_filter,
            verbose = FALSE
        )
        
        cov_mat <- alignSignals(cov_sigs)
        avg_cov <- rowMeans(cov_mat)
        
        # Plot average coverage profile
        plot(xs, avg_cov, type = "l", col = "darkgreen", lwd = 2,
             xlab = "Distance from Center (bp)",
             ylab = "Average Coverage",
             main = paste("Coverage Profile:", sample_id))
             
        # 3. Extract binned profiles for downstream analysis
        binsize <- 10
        binned_sigs <- bamProfile(
            bam,
            fixed_regions,
            binsize = binsize,
            paired.end = pe_mode,
            tlenFilter = tlen_filter,
            verbose = FALSE
        )
        binned_mat <- alignSignals(binned_sigs)
        binned_profiles_list[[sample_id]] <- rowMeans(binned_mat)
    }
    
    dev.off()
    
    # Save binned profiles
    binned_df <- as.data.frame(binned_profiles_list)
    rownames(binned_df) <- paste0("bin_", seq_len(nrow(binned_df)))
    write.csv(binned_df, "binned_profiles.csv", row.names = TRUE)
    
    message("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_BAMSIGNALS_BAMSIGNALS_PROFILING_PIPELINE":',
        paste0('    bamsignals: ', as.character(packageVersion('bamsignals')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bamsignals_profiling_pipeline.csv versions.yml
    """
}

workflow BIOC_BAMSIGNALS_BAMSIGNALS_PROFILING_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_BAMSIGNALS_BAMSIGNALS_PROFILING_PIPELINE(ch_input)

    emit:
    tables   = BIOC_BAMSIGNALS_BAMSIGNALS_PROFILING_PIPELINE.out.tables
    plots    = BIOC_BAMSIGNALS_BAMSIGNALS_PROFILING_PIPELINE.out.plots
    objects  = BIOC_BAMSIGNALS_BAMSIGNALS_PROFILING_PIPELINE.out.objects
    versions = BIOC_BAMSIGNALS_BAMSIGNALS_PROFILING_PIPELINE.out.versions
}
