#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: genomeIntervals — genomic_interval_analysis
// Perform a comprehensive genomic interval analysis including standardization, set operations (union/complement), overlap detection, and distance-to-nearest calcu
// Input: regions.bed, coldata.csv
// Container: 1.66.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, genomeIntervals, rtracklayer
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENOMEINTERVALS_GENOMIC_INTERVAL_ANALYSIS {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(genomeIntervals)
    library(rtracklayer)
    library(GenomicRanges)
    
    # ==========================================
    # --- Import Data & Construct Objects ---
    # ==========================================
    message("Stage 1: Importing BED intervals and metadata...")
    
    if (!file.exists("regions.bed")) {
      stop("Required input file 'regions.bed' is missing.")
    }
    
    # Import BED file using rtracklayer
    gr <- rtracklayer::import("regions.bed")
    
    # Extract coordinates and core attributes
    chroms <- as.character(seqnames(gr))
    starts <- start(gr)
    ends <- end(gr)
    strands <- as.character(strand(gr))
    
    # genomeIntervals requires explicit "+" or "-" strands for stranded classes
    strands[strands == "*"] <- "+" 
    
    # Build the core annotation data frame
    annot <- data.frame(
      seq_name = factor(chroms),
      inter_base = FALSE,
      strand = factor(strands, levels = c("+", "-")),
      stringsAsFactors = FALSE
    )
    
    # Add name and score from BED if available
    if (!is.null(gr\$name)) {
      annot\$name <- gr\$name
    } else {
      annot\$name <- paste0("interval_", seq_along(gr))
    }
    if (!is.null(gr\$score)) {
      annot\$score <- gr\$score
    }
    
    # Merge optional metadata if coldata.csv exists
    if (file.exists("coldata.csv")) {
      message("Merging optional metadata from coldata.csv...")
      coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
      if (nrow(coldata) == nrow(annot)) {
        annot <- cbind(annot, coldata)
      } else {
        warning("coldata.csv row count does not match regions.bed. Skipping metadata merge.")
      }
    }
    
    # Construct the Genome_intervals_stranded object
    gi <- new(
      "Genome_intervals_stranded",
      matrix(c(starts, ends), ncol = 2),
      closed = TRUE,
      annotation = annot
    )
    rownames(gi) <- annot\$name
    
    # ==========================================
    # --- Standardization & Size Calculation ---
    # ==========================================
    message("Stage 2: Standardizing intervals and calculating sizes...")
    
    # Adjust representation to closed intervals
    gi_closed <- close_intervals(gi)
    
    # Calculate size (number of bases) for each interval
    sizes <- size(gi_closed)
    annotation(gi_closed)\$size <- sizes
    
    # ==========================================
    # --- Set Operations (Union & Complement) ---
    # ==========================================
    message("Stage 3: Performing set operations (Union and Complement)...")
    
    # Compute the union of all intervals (by chromosome and strand)
    gi_union <- interval_union(gi_closed)
    annotation(gi_union)\$source <- "genomeIntervals_pipeline"
    annotation(gi_union)\$type <- "union_interval"
    
    # Compute the complement (gaps) of the intervals
    gi_complement <- interval_complement(gi_closed)
    annotation(gi_complement)\$source <- "genomeIntervals_pipeline"
    annotation(gi_complement)\$type <- "complement_interval"
    
    # ==========================================
    # --- Overlap & Distance Analysis ---
    # ==========================================
    message("Stage 4: Analyzing overlaps and nearest-neighbor distances...")
    
    # Split intervals by strand to calculate cross-strand distances/overlaps
    gi_plus <- gi_closed[strand(gi_closed) == "+", ]
    gi_minus <- gi_closed[strand(gi_closed) == "-", ]
    
    dist_to_minus <- rep(NA, nrow(gi_closed))
    overlap_minus <- rep(NA, nrow(gi_closed))
    
    if (nrow(gi_plus) > 0 && nrow(gi_minus) > 0) {
      # Calculate distance from positive strand intervals to nearest negative strand intervals
      dists <- distance_to_nearest(gi_plus, gi_minus)
      
      # Find overlapping negative strand intervals for each positive strand interval
      overlaps <- interval_overlap(from = gi_plus, to = gi_minus)
      overlaps_str <- sapply(overlaps, function(x) {
        if (length(x) == 0) "none" else paste(rownames(gi_minus)[x], collapse = ";")
      })
      
      # Map results back to the full dataset
      plus_indices <- which(strand(gi_closed) == "+")
      dist_to_minus[plus_indices] <- dists
      overlap_minus[plus_indices] <- overlaps_str
    }
    
    # Build comprehensive summary table
    summary_df <- data.frame(
      interval_id = rownames(gi_closed),
      chromosome = as.character(seqnames(gi_closed)),
      start = gi_closed[, 1],
      end = gi_closed[, 2],
      strand = as.character(strand(gi_closed)),
      size = sizes,
      distance_to_nearest_minus_strand = dist_to_minus,
      overlapping_minus_intervals = overlap_minus,
      stringsAsFactors = FALSE
    )
    
    # Append any extra user-defined metadata columns
    extra_cols <- setdiff(colnames(annotation(gi_closed)), c("seq_name", "inter_base", "strand", "size"))
    if (length(extra_cols) > 0) {
      summary_df <- cbind(summary_df, annotation(gi_closed)[, extra_cols, drop = FALSE])
    }
    
    # ==========================================
    # --- Exporting Results ---
    # ==========================================
    message("Stage 5: Writing output files...")
    
    # Write summary CSV
    write.csv(summary_df, "interval_analysis_summary.csv", row.names = FALSE)
    
    # Write Union and Complement intervals to GFF3 format
    writeGff3(gi_union, "union_regions.gff3")
    writeGff3(gi_complement, "complement_regions.gff3")
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_GENOMEINTERVALS_GENOMIC_INTERVAL_ANALYSIS":',
        paste0('    genomeIntervals: ', as.character(packageVersion('genomeIntervals')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomic_interval_analysis.csv versions.yml
    """
}

workflow BIOC_GENOMEINTERVALS_GENOMIC_INTERVAL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_GENOMEINTERVALS_GENOMIC_INTERVAL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GENOMEINTERVALS_GENOMIC_INTERVAL_ANALYSIS.out.tables
    plots    = BIOC_GENOMEINTERVALS_GENOMIC_INTERVAL_ANALYSIS.out.plots
    objects  = BIOC_GENOMEINTERVALS_GENOMIC_INTERVAL_ANALYSIS.out.objects
    versions = BIOC_GENOMEINTERVALS_GENOMIC_INTERVAL_ANALYSIS.out.versions
}
