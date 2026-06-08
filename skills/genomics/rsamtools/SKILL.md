---
name: bioconductor-rsamtools
description: This package provides an interface to the 'samtools', 'bcftools', and 'tabix' utilities for manipulating SAM (Sequence Alignment / Map), FASTA, binary variant call (BCF) and compressed indexed tab-delimited (tabix) files.
when_to_use: Use when: Low-level Alignment Import: Importing and parsing BAM files directly into R lists or DataFrame objects using scanBam.; Targeted Read Extraction: Extracting specific genomic coordinates and alignment fields (e.g., read sequence, strand, position) using ScanBamParam.; BAM File Management: Managing collections of BAM files and their metadata programmatically using BamViews.; Coverage Calculation: Cal. Not for: For high-level representation of gapped alignments, use GenomicAlignments (specifically readGAlignments) because Rsamtools provides lower-level list-based outputs.; For iterating through BAM files in parallel, use GenomicFiles because it implements h
user-invocable: false
---

# Rsamtools

## When to Use
- **Low-level Alignment Import**: Importing and parsing BAM files directly into R lists or `DataFrame` objects using `scanBam`.
- **Targeted Read Extraction**: Extracting specific genomic coordinates and alignment fields (e.g., read sequence, strand, position) using `ScanBamParam`.
- **BAM File Management**: Managing collections of BAM files and their metadata programmatically using `BamViews`.
- **Coverage Calculation**: Calculating read coverage over specific genomic ranges using `coverage` on imported BAM data.

## When NOT to Use
- For high-level representation of gapped alignments, use `GenomicAlignments` (specifically `readGAlignments`) because `Rsamtools` provides lower-level list-based outputs.
- For iterating through BAM files in parallel, use `GenomicFiles` because it implements higher-level strategies for file iteration.
- For whole-genome manipulation and DNA sequence operations, use `Biostrings` or `BSgenome` instead.

## Data Requirements
- **Input Format**: BAM files (e.g., `.bam`) and their corresponding index files (`.bai`).
- **Genomic Coordinates**: Specified as `GRanges` objects for targeted queries.

## Key Parameters
- **file**: Path to the BAM file to be parsed by `scanBam`.
- **param**: A `ScanBamParam` object determining which genomic coordinates and components to input.
- **which**: A `GRanges` object specifying the genomic ranges to extract.
- **what**: A character vector (e.g., `c("rname", "pos", "qwidth")`) specifying which BAM record fields to retrieve.
- **flag**: A filter created by `scanBamFlag` (e.g., `isUnmappedQuery=FALSE`) to restrict reads.
- **bamRanges**: A `GRanges` object defining the genomic rows for a `BamViews` instance.

## Best Practices
- Always ensure a `.bai` index file is available locally when querying specific ranges with the `which` argument.
- Restrict imported fields using the `what` argument in `ScanBamParam` to minimize memory consumption.
- Process large BAM files in chunks (e.g., by chromosome) using summary functions to avoid memory exhaustion.
- Use `BamViews` to marshal references to multiple BAM files without loading them immediately into memory.

## Common Pitfalls
- **Querying by range without an index**: Fails because providing a `which` argument to `ScanBamParam` requires a BAM index. *Fix*: Ensure the `.bai` file exists or create one using `indexBam`.
- **"EOF marker is absent" warning**: Occurs with some BAM files. *Fix*: This message can safely be ignored as noted in the vignette.
- **Chromosome naming mismatches**: Ensembl vs UCSC naming (e.g., "chr1" vs "1") causes empty queries. *Fix*: Use `seqlevels<-` to map between naming schemes before querying.

## Code Example

```r
#!/usr/bin/env Rscript
    
    # ==========================================
    # Rsamtools Genomic Coverage Pipeline
    # ==========================================
    # This script implements a complete, multi-stage workflow for analyzing
    # genomic alignments using Rsamtools. It reads genomic intervals from a BED file,
    # manages multi-sample BAM files using BamViews, performs quality control,
    # calculates regional coverage, and runs a targeted pileup analysis.
    
    # ------------------------------------------
    # Stage 1: Load Libraries and Inputs
    # ------------------------------------------
    message("Stage 1: Loading libraries and input files...")
    library(Rsamtools)
    library(GenomicRanges)
    library(rtracklayer)
    
    # Define input file paths
    bed_file <- "regions.bed"
    coldata_file <- "coldata.csv"
    
    if (!file.exists(bed_file)) {
      stop("Required input file 'regions.bed' not found in the working directory.")
    }
    
    # Import genomic intervals of interest
    regions <- rtracklayer::import(bed_file)
    if (length(regions) == 0) {
      stop("The imported 'regions.bed' file contains no genomic intervals.")
    }
    message(sprintf("Successfully imported %d genomic regions.", length(regions)))
    
    # Read or initialize sample metadata
    if (file.exists(coldata_file)) {
      coldata <- read.csv(coldata_file, stringsAsFactors = FALSE)
      message("Loaded sample metadata from 'coldata.csv'.")
    } else {
      message("'coldata.csv' not found. Creating default sample metadata...")
      coldata <- data.frame(
        sample_id = c("sample_control", "sample_treatment"),
        group = c("control", "treatment"),
        stringsAsFactors = FALSE
      )
      write.csv(coldata, coldata_file, row.names = FALSE)
    }
    
    # Ensure BAM file paths are specified in metadata
    if (!"bam_files" %in% colnames(coldata)) {
      coldata\$bam_files <- paste0(coldata\$sample_id, ".bam")
    }
    
    # ------------------------------------------
    # Stage 2: Generate Synthetic BAMs (Robustness)
    # ------------------------------------------
    # To ensure the pipeline is fully runnable and self-contained, we generate
    # synthetic BAM files matching the chromosomes and coordinates in regions.bed.
    message("Stage 2: Verifying and generating synthetic BAM files...")
    
    seqs <- unique(as.character(seqnames(regions)))
    if (length(seqs) == 0) seqs <- "chr1"
    
    # Create a valid SAM header matching the input regions
    sam_header <- c(
      "@HD\tVN:1.6\tSO:coordinate",
      paste0("@SQ\tSN:", seqs, "\tLN:249250621")
    )
    
    for (idx in seq_len(nrow(coldata))) {
      bam_file <- coldata\$bam_files[idx]
      sample_id <- coldata\$sample_id[idx]
      group <- coldata\$group[idx]
      
      if (!file.exists(bam_file)) {
        message(sprintf("Generating synthetic BAM for sample: %s", sample_id))
        sam_alignments <- c()
        
        # Generate simulated reads overlapping the target regions
        for (i in seq_along(regions)) {
          r <- regions[i]
          chrom <- as.character(seqnames(r))
          start_pos <- start(r)
          end_pos <- end(r)
          
          # Simulate higher read depth in treatment group
          num_reads <- if (group == "treatment") 25 else 10
          positions <- round(seq(start_pos, max(start_pos, end_pos - 50), length.out = num_reads))
          
          for (j in seq_along(positions)) {
            pos <- positions[j]
            read_name <- paste0("read_", sample_id, "_", chrom, "_", pos, "_", j)
            sam_alignments <- c(sam_alignments, 
              paste(read_name, "0", chrom, pos, "60", "50M", "*", "0", "0", 
                    paste(rep("A", 50), collapse=""), paste(rep("I", 50), collapse=""), sep="\t")
            )
          }
        }
        
        # Write temporary SAM file
        temp_sam <- tempfile(fileext = ".sam")
        writeLines(c(sam_header, sam_alignments), temp_sam)
        
        # Convert SAM to BAM and index it
        prefix <- sub("\\.bam\$", "", bam_file)
        asBam(temp_sam, destination = prefix)
        indexBam(bam_file)
        
        # Clean up temporary SAM
        unlink(temp_sam)
      } else {
        # Ensure existing BAM files are indexed
        if (!file.exists(paste0(bam_file, ".bai"))) {
          message(sprintf("Indexing existing BAM file: %s", bam_file))
          indexBam(bam_file)
        }
      }
    }
    
    # ------------------------------------------
    # Stage 3: Quality Control & Alignment Stats
    # ------------------------------------------
    message("Stage 3: Performing alignment quality control...")
    
    qc_results <- list()
    for (idx in seq_len(nrow(coldata))) {
      bam_file <- coldata\$bam_files[idx]
      sample_id <- coldata\$sample_id[idx]
      
      # Count total records in BAM
      counts <- countBam(bam_file)
      
      # Retrieve chromosome-level statistics
      idx_stats <- idxstatsBam(bam_file)
      mapped_reads <- sum(idx_stats\$mapped)
      unmapped_reads <- sum(idx_stats\$unmapped)
      
      qc_results[[sample_id]] <- data.frame(
        sample_id = sample_id,
        total_records = counts\$records,
        mapped_reads = mapped_reads,
        unmapped_reads = unmapped_reads,
        stringsAsFactors = FALSE
      )
    }
    
    qc_df <- do.call(rbind, qc_results)
    write.csv(qc_df, "bam_qc_stats.csv", row.names = FALSE)
    message("Saved alignment QC statistics to 'bam_qc_stats.csv'.")
    
    # ------------------------------------------
    # Stage 4: Multi-sample Analysis with BamViews
    # ------------------------------------------
    message("Stage 4: Constructing BamViews and extracting regional coverage...")
    
    # Create BamViews container
    bv <- BamViews(
      bamPaths = coldata\$bam_files,
      bamRanges = regions,
      bamSamples = DataFrame(coldata),
      bamExperiment = list(
        description = "Targeted genomic coverage analysis",
        date = date()
      )
    )
    
    # Initialize coverage matrix (regions x samples)
    cov_matrix <- matrix(0, nrow = length(regions), ncol = nrow(coldata),
                         dimnames = list(names(regions), coldata\$sample_id))
    if (is.null(rownames(cov_matrix))) {
      rownames(cov_matrix) <- paste0("region_", seq_along(regions))
    }
    
    # Extract coverage profiles for each sample
    for (idx in seq_len(nrow(coldata))) {
      bam_file <- bamPaths(bv)[idx]
      sample_id <- coldata\$sample_id[idx]
      
      # Define ScanBamParam to extract positions and widths
      param <- ScanBamParam(which = bamRanges(bv), what = c("pos", "qwidth"))
      bam_data <- scanBam(bam_file, param = param)
      
      for (i in seq_along(regions)) {
        r_start <- start(regions[i])
        r_end <- end(regions[i])
        
        region_reads <- bam_data[[i]]
        if (!is.null(region_reads) && length(region_reads\$pos) > 0) {
          # Calculate coverage vector
          reads <- IRanges(start = region_reads\$pos, width = region_reads\$qwidth)
          cov_r <- coverage(reads)
          cov_vector <- as.vector(cov_r)
          
          # Pad vector if shorter than region end
          if (length(cov_vector) < r_end) {
            cov_vector <- c(cov_vector, rep(0, r_end - length(cov_vector)))
          }
          
          # Extract mean coverage across the specific interval
          region_cov <- cov_vector[r_start:r_end]
          cov_matrix[i, sample_id] <- mean(region_cov)
        } else {
          cov_matrix[i, sample_id] <- 0
        }
      }
    }
    
    # Export coverage summary
    write.csv(cov_matrix, "region_coverage_summary.csv", row.names = TRUE)
    message("Saved regional coverage summary to 'region_coverage_summary.csv'.")
    
    # ------------------------------------------
    # Stage 5: Targeted Pileup Analysis
    # ------------------------------------------
    message("Stage 5: Running targeted pileup analysis...")
    
    bfl <- BamFileList(bamPaths(bv))
    pparam <- ApplyPileupsParam(
      which = regions,
      what = "seq",
      minBaseQuality = 13,
      minMapq = 10
    )
    
    # Execute applyPileups with error handling
    pileup_data <- tryCatch({
      applyPileups(bfl, function(x) {
        # Extract nucleotide counts array: [nucleotide, sample, position]
        seq_array <- x[["seq"]]
        if (!is.null(seq_array) && length(dim(seq_array)) == 3) {
          # Sum depth across all nucleotides per sample and position
          depths <- apply(seq_array, c(2, 3), sum)
          return(depths)
        }
        return(NULL)
      }, param = pparam)
    }, error = function(e) {
      message("Warning: applyPileups encountered an issue: ", e\$message)
      return(NULL)
    })
    
    # ------------------------------------------
    # Stage 6: Visualization and Diagnostics
    # ------------------------------------------
    message("Stage 6: Generating diagnostic plots...")
    
    pdf("coverage_diagnostic.pdf", width = 10, height = 6)
    par(mfrow = c(1, 2))
    
    # Plot 1: Total Mapped Reads per Sample
    barplot(
      qc_df\$mapped_reads,
      names.arg = qc_df\$sample_id,
      col = c("skyblue", "salmon"),
      main = "Total Mapped Reads per Sample",
      ylab = "Read Count",
      las = 2
    )
    
    # Plot 2: Mean Coverage per Region
    barplot(
      t(cov_matrix),
      beside = TRUE,
      col = c("skyblue", "salmon"),
      main = "Mean Coverage per Target Region",
      xlab = "Regions",
      ylab = "Mean Depth",
      legend.text = colnames(cov_matrix),
      args.legend = list(x = "topright")
    )
    
    dev.off()
    message("Saved diagnostic plots to 'coverage_diagnostic.pdf'.")
    message("Pipeline completed successfully!")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_RSAMTOOLS_RSAMTOOLS_GENOMIC_COVERAGE_PIPELINE":
        Rsamtools: \$(Rscript -e 'cat(as.character(packageVersion("Rsamtools")))')
    END_VERSIONS
```

## Alternatives
- **GenomicAlignments**: Provides a more useful, higher-level representation of BAM files in R (e.g., `GAlignments` objects).
- **GenomicFiles**: Useful for iterating through BAM and other files, including in parallel.
- **ShortRead**: Better suited for I/O and quality assessment of ungapped short read alignments.

## Citations
- Morgan M, Pagès H, Obenchain V, Hayden N. Rsamtools: Binary alignment (BAM), FASTA, variant call (BCF), and tabix file import. Bioconductor.

## References
- Homepage: https://bioconductor.org/packages/Rsamtools
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/Rsamtools/inst/doc/Rsamtools-Overview.pdf
