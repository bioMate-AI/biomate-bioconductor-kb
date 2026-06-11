#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: girafe — girafe_genome_intervals_pipeline
// Perform genome-level representation, reduction, and coverage analysis of aligned reads using the girafe package.
// Input: regions.bed, coldata.csv
// Container: 1.58.0--r44he5774e6_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, IRanges, S4Vectors, genomeIntervals, girafe, rtracklayer
// Visualizations: bar plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GIRAFE_GIRAFE_GENOME_INTERVALS_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("girafe", "genomeIntervals", "rtracklayer", "S4Vectors", "GenomicRanges")
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
    
    # --- Load Required Libraries ---
    library(girafe)
    library(genomeIntervals)
    library(rtracklayer)
    library(S4Vectors)
    library(GenomicRanges)
    
    # --- Import Input Data ---
    message("Stage 2: Importing input files...")
    if (!file.exists("regions.bed")) {
      stop("Required input file 'regions.bed' not found in the working directory.")
    }
    
    # Read genomic intervals from BED file
    gr <- rtracklayer::import("regions.bed")
    
    # Read optional metadata if present
    if (file.exists("coldata.csv")) {
      coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
      message("Successfully loaded coldata.csv metadata.")
    } else {
      message("Optional coldata.csv not found. Proceeding with default settings.")
    }
    
    # --- Construct AlignedGenomeIntervals Object ---
    message("Stage 3: Constructing AlignedGenomeIntervals object...")
    
    # Extract fields for GenomeIntervals construction
    chrom <- as.character(seqnames(gr))
    start <- start(gr)
    end <- end(gr)
    strand <- as.character(strand(gr))
    strand[strand == "*"] <- NA
    
    # Construct the base GenomeIntervals object
    gi <- GenomeIntervals(
      chromosome = chrom,
      left = as.integer(start),
      right = as.integer(end),
      strand = strand
    )
    
    # Extract read counts (scores) and read IDs (names) from GRanges
    reads <- as.integer(gr\$score)
    if (all(is.na(reads)) || all(reads <= 0)) {
      reads <- rep(1L, length(gr))
    } else {
      reads[is.na(reads) | reads < 0] <- 1L
    }
    
    char_id <- gr\$name
    if (is.null(char_id) || all(is.na(char_id))) {
      char_id <- paste0("read_", seq_along(gr))
    } else {
      char_id <- as.character(char_id)
    }
    
    # Construct the AlignedGenomeIntervals object
    agi <- new("AlignedGenomeIntervals",
               intervals = gi,
               reads = reads,
               char_id = char_id)
    
    # --- Quality Control & Filtering ---
    message("Stage 4: Filtering low-abundance intervals...")
    min_reads <- 1
    agi_filtered <- agi[reads(agi) >= min_reads]
    
    # --- Core Analysis - Interval Reduction & Merging ---
    message("Stage 5: Merging overlapping intervals and summing read counts...")
    agi_reduced <- reduce(agi_filtered)
    
    # Extract reduced intervals to data frame
    gi_red <- intervals(agi_reduced)
    chrom_red <- tryCatch(chromosome(gi_red), error = function(e) as.character(gi_red@annotation\$seqnames))
    left_red <- tryCatch(left(gi_red), error = function(e) gi_red@left)
    right_red <- tryCatch(right(gi_red), error = function(e) gi_red@right)
    strand_red <- tryCatch(as.character(strand(gi_red)), error = function(e) as.character(gi_red@annotation\$strand))
    reads_red <- reads(agi_reduced)
    
    reduced_df <- data.frame(
      chromosome = chrom_red,
      start = left_red,
      end = right_red,
      strand = strand_red,
      reads = reads_red,
      stringsAsFactors = FALSE
    )
    write.csv(reduced_df, "reduced_intervals.csv", row.names = FALSE)
    message("Saved reduced intervals to 'reduced_intervals.csv'.")
    
    # --- Coverage Calculation & Export ---
    message("Stage 6: Calculating genome-wide coverage...")
    cov <- coverage(agi_filtered)
    
    # Convert coverage RleList to GRanges safely
    cov_gr <- tryCatch({
      as(cov, "GRanges")
    }, error = function(e) {
      # Fallback manual construction if direct coercion fails
      gr_list <- lapply(names(cov), function(chr) {
        rle <- cov[[chr]]
        if (length(rle) == 0) return(NULL)
        runs <- runLength(rle)
        vals <- runValue(rle)
        ends <- cumsum(runs)
        starts <- ends - runs + 1
        nz <- vals > 0
        if (!any(nz)) return(NULL)
        GRanges(seqnames = chr, ranges = IRanges(start = starts[nz], end = ends[nz]), score = vals[nz])
      })
      gr_list <- gr_list[!sapply(gr_list, is.null)]
      if (length(gr_list) > 0) do.call(c, gr_list) else GRanges()
    })
    
    # Filter out zero-coverage regions to optimize file size
    if (length(cov_gr) > 0) {
      cov_gr <- cov_gr[cov_gr\$score > 0]
      rtracklayer::export.bedGraph(cov_gr, "coverage.bedGraph")
      message("Saved coverage track to 'coverage.bedGraph'.")
    } else {
      writeLines("# No coverage data", "coverage.bedGraph")
      message("No coverage detected. Created empty 'coverage.bedGraph'.")
    }
    
    # --- Diagnostics & Visualization ---
    message("Stage 7: Generating diagnostic plots...")
    pdf("analysis_plots.pdf", width = 8, height = 10)
    par(mfrow = c(3, 1))
    
    # Plot 1: Histogram of read counts
    hist(reads(agi), breaks = 50, col = "skyblue", main = "Distribution of Read Counts",
         xlab = "Read Count per Interval", ylab = "Frequency")
    
    # Plot 2: Total reads per chromosome
    chrom_reads <- tapply(reads(agi), chrom, sum)
    barplot(chrom_reads, col = "coral", main = "Total Reads per Chromosome",
            xlab = "Chromosome", ylab = "Total Reads", las = 2)
    
    # Plot 3: Coverage along the highest-coverage chromosome
    top_chrom <- names(which.max(sapply(cov, function(x) sum(as.numeric(x)))))
    if (!is.null(top_chrom) && length(top_chrom) > 0) {
      cov_chrom <- cov[[top_chrom]]
      max_len <- min(length(cov_chrom), 500000)
      cov_vals <- as.numeric(cov_chrom[1:max_len])
      plot(cov_vals, type = "l", col = "darkgreen", main = paste("Coverage along", top_chrom, "(First 500kb)"),
           xlab = "Genomic Position", ylab = "Coverage")
    } else {
      plot(1, type = "n", axes = FALSE, xlab = "", ylab = "", main = "No coverage data to plot")
    }
    
    dev.off()
    message("Saved diagnostic plots to 'analysis_plots.pdf'.")
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_GIRAFE_GIRAFE_GENOME_INTERVALS_PIPELINE":',
        paste0('    girafe: ', as.character(packageVersion('girafe')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_girafe_genome_intervals_pipeline.csv versions.yml
    """
}

workflow BIOC_GIRAFE_GIRAFE_GENOME_INTERVALS_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_GIRAFE_GIRAFE_GENOME_INTERVALS_PIPELINE(ch_input)

    emit:
    tables   = BIOC_GIRAFE_GIRAFE_GENOME_INTERVALS_PIPELINE.out.tables
    plots    = BIOC_GIRAFE_GIRAFE_GENOME_INTERVALS_PIPELINE.out.plots
    objects  = BIOC_GIRAFE_GIRAFE_GENOME_INTERVALS_PIPELINE.out.objects
    versions = BIOC_GIRAFE_GIRAFE_GENOME_INTERVALS_PIPELINE.out.versions
}
