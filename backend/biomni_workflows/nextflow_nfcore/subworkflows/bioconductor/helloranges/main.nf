#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: HelloRanges — helloranges_genomic_intervals_analysis
// Perform a comprehensive genomic interval analysis including merging, coverage calculation, complement (gaps) identification, and Jaccard similarity comparison u
// Input: regions.bed, coldata.csv
// Container: 1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, HelloRanges, rtracklayer
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HELLORANGES_HELLORANGES_GENOMIC_INTERVALS_ANALYSIS {
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
    .bm_deps <- c("HelloRanges", "rtracklayer", "GenomicRanges")
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
    library(HelloRanges)
    library(rtracklayer)
    library(GenomicRanges)
    
    # ==========================================
    # --- Import and Preprocess Input Data ---
    # ==========================================
    message("Stage 1: Importing regions.bed...")
    gr <- rtracklayer::import("regions.bed")
    
    # Ensure seqinfo has valid chromosome lengths for downstream genome-wide operations
    si <- seqinfo(gr)
    if (any(is.na(seqlengths(si)))) {
        message("Warning: Missing chromosome lengths. Estimating from interval coordinates...")
        # Calculate max end coordinate per chromosome as a fallback
        max_ends <- tapply(end(gr), seqnames(gr), max)
        # Assign estimated lengths with a buffer
        seqlengths(si)[names(max_ends)] <- max_ends + 100000
        seqinfo(gr) <- si
    }
    
    # Write a temporary genome file required by some HelloRanges/bedtools commands
    genome_df <- data.frame(chr = names(seqlengths(si)), len = seqlengths(si))
    genome_file <- "temp.genome"
    write.table(genome_df, file = genome_file, sep = "\t", col.names = FALSE, row.names = FALSE, quote = FALSE)
    
    # ==========================================
    # --- Merge Overlapping Intervals ---
    # ==========================================
    message("Stage 2: Merging overlapping intervals...")
    merged_gr <- tryCatch({
        do_bedtools_merge("regions.bed")
    }, error = function(e) {
        message("Error in merging: ", e\$message)
        # Fallback to standard reduce
        reduce(gr, ignore.strand = TRUE)
    })
    
    # Export merged intervals
    rtracklayer::export(merged_gr, "merged_regions.bed", format = "bed")
    
    # ==========================================
    # --- Compute Genomic Coverage ---
    # ==========================================
    message("Stage 3: Computing genomic coverage...")
    cov_gr <- tryCatch({
        do_bedtools_genomecov("regions.bed", g = genome_file, bg = TRUE)
    }, error = function(e) {
        message("Error in genomecov: ", e\$message)
        # Fallback using standard coverage
        cov <- coverage(gr)
        as(cov, "GRanges")
    })
    
    # Export coverage as BedGraph
    rtracklayer::export(cov_gr, "genomic_coverage.bedgraph", format = "bedGraph")
    
    # Plot coverage distribution
    pdf("coverage_distribution.pdf", width = 7, height = 5)
    if (length(cov_gr) > 0 && "score" %in% colnames(mcols(cov_gr))) {
        hist(cov_gr\$score, breaks = 50, col = "skyblue", main = "Genomic Coverage Distribution",
             xlab = "Coverage Score", ylab = "Frequency")
    } else {
        plot.new()
        text(0.5, 0.5, "No coverage data to plot")
    }
    dev.off()
    
    # ==========================================
    # --- Identify Genomic Gaps (Complement) ---
    # ==========================================
    message("Stage 4: Finding genomic gaps (complement)...")
    gaps_gr <- tryCatch({
        do_bedtools_complement("regions.bed", g = genome_file)
    }, error = function(e) {
        message("Error in complement: ", e\$message)
        # Fallback using setdiff
        setdiff(as(seqinfo(gr), "GRanges"), unstrand(gr))
    })
    
    # Export gaps
    rtracklayer::export(gaps_gr, "genomic_gaps.bed", format = "bed")
    
    # ==========================================
    # --- Split Comparison & Jaccard Similarity ---
    # ==========================================
    message("Stage 5: Calculating Jaccard similarity between split sets...")
    
    # Split the GRanges into two subsets (e.g., by strand or index)
    if (any(strand(gr) == "+") && any(strand(gr) == "-")) {
        gr_a <- gr[strand(gr) == "+" | strand(gr) == "*"]
        gr_b <- gr[strand(gr) == "-"]
    } else {
        # Fallback: split by odd/even indices if unstranded
        gr_a <- gr[seq_along(gr) %% 2 == 1]
        gr_b <- gr[seq_along(gr) %% 2 == 0]
    }
    
    jaccard_df <- tryCatch({
        # Compute Jaccard statistic using HelloRanges
        do_bedtools_jaccard(gr_a, gr_b)
    }, error = function(e) {
        message("Error in Jaccard calculation: ", e\$message)
        # Fallback manual calculation
        intersection_width <- sum(width(intersect(gr_a, gr_b, ignore.strand = TRUE)))
        union_width <- sum(width(union(gr_a, gr_b, ignore.strand = TRUE)))
        data.frame(
            intersection = intersection_width,
            union = union_width,
            jaccard = if (union_width > 0) intersection_width / union_width else 0,
            n_intersections = length(intersect(gr_a, gr_b, ignore.strand = TRUE))
        )
    })
    
    # Write Jaccard results
    write.csv(as.data.frame(jaccard_df), "jaccard_similarity.csv", row.names = FALSE)
    
    # Clean up temporary files
    if (file.exists(genome_file)) {
        file.remove(genome_file)
    }
    
    message("Analysis pipeline completed successfully!")

    writeLines(c(
        '"BIOC_HELLORANGES_HELLORANGES_GENOMIC_INTERVALS_ANALYSIS":',
        paste0('    HelloRanges: ', as.character(packageVersion('HelloRanges')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_helloranges_genomic_intervals_analysis.csv versions.yml
    """
}

workflow BIOC_HELLORANGES_HELLORANGES_GENOMIC_INTERVALS_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_HELLORANGES_HELLORANGES_GENOMIC_INTERVALS_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_HELLORANGES_HELLORANGES_GENOMIC_INTERVALS_ANALYSIS.out.tables
    plots    = BIOC_HELLORANGES_HELLORANGES_GENOMIC_INTERVALS_ANALYSIS.out.plots
    objects  = BIOC_HELLORANGES_HELLORANGES_GENOMIC_INTERVALS_ANALYSIS.out.objects
    versions = BIOC_HELLORANGES_HELLORANGES_GENOMIC_INTERVALS_ANALYSIS.out.versions
}
