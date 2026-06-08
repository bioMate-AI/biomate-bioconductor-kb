---
name: bioconductor-genomicfeatures
description: Extract the genomic locations of genes, transcripts, exons, introns, and CDS, for the gene models stored in a TxDb object. A TxDb object is a small database that contains the gene models of a given organism/assembly. Bioconductor provides a
when_to_use: Use when: Extract genomic coordinates for exons, transcripts, or coding sequences as GRanges objects using transcripts, exons, or cds.; Group genomic features by gene or transcript into a GRangesList using transcriptsBy or exonsBy.; Retrieve actual sequence data by pairing a TxDb with a BSgenome package and using extractTranscriptSeqs.. Not for: For extracting actual sequence data without a BSgenome package (use BSgenome directly instead because GenomicFeatures only stores coordinates).; For finding overlaps between alignments and features without first extracting the features (use findOverl
user-invocable: false
---

# GenomicFeatures

## When to Use
- Extract genomic coordinates for exons, transcripts, or coding sequences as `GRanges` objects using `transcripts`, `exons`, or `cds`.
- Group genomic features by gene or transcript into a `GRangesList` using `transcriptsBy` or `exonsBy`.
- Retrieve actual sequence data by pairing a `TxDb` with a `BSgenome` package and using `extractTranscriptSeqs`.

## When NOT to Use
- For extracting actual sequence data without a `BSgenome` package (use `BSgenome` directly instead because `GenomicFeatures` only stores coordinates).
- For finding overlaps between alignments and features without first extracting the features (use `findOverlaps` on the extracted `GRangesList` instead).

## Data Requirements
- Requires a `TxDb` object (loaded via `loadDb` or an annotation package like `TxDb.Hsapiens.UCSC.hg19.knownGene`).
- Sequence extraction requires an appropriate `BSgenome` package (e.g., `BSgenome.Hsapiens.UCSC.hg19`).

## Key Parameters
- **keys** (default): A vector of identifiers to look up when using `select`.
- **columns** (default): The columns to retrieve when using `select`.
- **keytype** (default): The type of key being passed to `select`.
- **filter** (default): A list (e.g., `tx_chrom`, `tx_strand`) to subset results in `transcripts`.
- **upstream** (default): Number of bases upstream from the transcription start site for `promoters`.
- **downstream** (default): Number of bases downstream from the transcription start site for `promoters`.
- **by** (default): The feature to group by (e.g., "gene", "tx") in `transcriptsBy` or `exonsBy`.
- **use.names** (default): Logical to retain sequence names in `extractTranscriptSeqs`.

## Best Practices
- Check active chromosomes using `seqlevels` before extracting features to limit the data returned.
- Use `select` to map between different identifiers (e.g., `TXNAME` to `GENEID`) within the `TxDb` object.
- Group features into a `GRangesList` (e.g., using `exonsBy`) before using `findOverlaps` to contextualize high-throughput sequencing alignments.

## Common Pitfalls
- Extracting sequences for all transcribed regions instead of just coding regions. Fix: Use `cdsBy` to subset coding regions before calling `extractTranscriptSeqs`.
- Translating non-coding sequences resulting in meaningless translations. Fix: Ensure you extract sequences using `cdsBy` before passing them to `translate`.
- Forgetting which chromosomes are active after filtering. Fix: Use `seqlevels0` to reset to the original chromosomes stored in the database.

## Code Example

```r
#!/usr/bin/env Rscript
    
    # Load required Bioconductor libraries
    library(GenomicFeatures)
    library(GenomicRanges)
    library(IRanges)
    library(S4Vectors)
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    
    # ==========================================
    # STAGE 1: Import User Regions (BED format)
    # ==========================================
    message("Stage 1: Importing user regions from regions.bed...")
    
    if (!file.exists("regions.bed")) {
        stop("Input file 'regions.bed' not found in the working directory.")
    }
    
    # Read BED file robustly, ignoring comment lines
    bed_data <- read.table("regions.bed", header=FALSE, sep="\t", stringsAsFactors=FALSE, comment.char="#")
    
    if (ncol(bed_data) < 3) {
        stop("regions.bed must have at least 3 columns (chrom, start, end)")
    }
    
    colnames(bed_data)[1:3] <- c("chrom", "start", "end")
    
    # Handle optional BED columns (name, score, strand)
    name <- if (ncol(bed_data) >= 4) bed_data[,4] else paste0("region_", seq_len(nrow(bed_data)))
    score <- if (ncol(bed_data) >= 5) bed_data[,5] else rep(0, nrow(bed_data))
    strand <- if (ncol(bed_data) >= 6) bed_data[,6] else rep("*", nrow(bed_data))
    
    # Construct GRanges object (BED is 0-based, so start coordinate is incremented by 1)
    user_gr <- GRanges(
        seqnames = bed_data\$chrom,
        ranges = IRanges(start = bed_data\$start + 1, end = bed_data\$end),
        strand = strand,
        name = name,
        score = score
    )
    
    # ==========================================
    # STAGE 2: Load and Configure TxDb Annotation
    # ==========================================
    message("Stage 2: Loading TxDb annotation database...")
    txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene
    
    # Align seqlevels styles to avoid mismatch warnings/errors
    seqlevelsStyle(user_gr) <- seqlevelsStyle(txdb)
    
    # Restrict TxDb active chromosomes to those present in user data to optimize performance
    active_chrs <- intersect(seqlevels(txdb), unique(as.character(seqnames(user_gr))))
    if (length(active_chrs) > 0) {
        seqlevels(txdb) <- active_chrs
    } else {
        warning("No overlapping chromosomes found between input regions and TxDb. Resetting to default seqlevels.")
        seqlevels(txdb) <- seqlevels0(txdb)
    }
    
    # ==========================================
    # STAGE 3: Extract Genomic Features
    # ==========================================
    message("Stage 3: Extracting genomic features from TxDb...")
    tx <- transcripts(txdb)
    ex <- exons(txdb)
    cds_regions <- cds(txdb)
    proms <- promoters(txdb, upstream=2000, downstream=400)
    
    # ==========================================
    # STAGE 4: Annotate User Regions with Overlaps
    # ==========================================
    message("Stage 4: Annotating user regions with genomic context...")
    user_gr\$overlap_transcript <- countOverlaps(user_gr, tx) > 0
    user_gr\$overlap_exon <- countOverlaps(user_gr, ex) > 0
    user_gr\$overlap_cds <- countOverlaps(user_gr, cds_regions) > 0
    user_gr\$overlap_promoter <- countOverlaps(user_gr, proms) > 0
    user_gr\$overlap_intron <- user_gr\$overlap_transcript & !user_gr\$overlap_exon
    
    # Find nearest transcript and calculate distance
    nearest_tx_idx <- nearest(user_gr, tx)
    valid_idx <- !is.na(nearest_tx_idx)
    
    user_gr\$nearest_tx_id <- NA
    user_gr\$distance_to_nearest_tx <- NA
    
    if (any(valid_idx)) {
        user_gr\$nearest_tx_id[valid_idx] <- tx\$tx_name[nearest_tx_idx[valid_idx]]
        user_gr\$distance_to_nearest_tx[valid_idx] <- distance(user_gr[valid_idx], tx[nearest_tx_idx[valid_idx]])
    }
    
    # Export annotated regions to CSV
    annotated_df <- as.data.frame(user_gr)
    write.csv(annotated_df, "annotated_regions.csv", row.names=FALSE)
    message("Saved annotated regions to 'annotated_regions.csv'")
    
    # ==========================================
    # STAGE 5: Map Regions to Transcript Coordinates
    # ==========================================
    message("Stage 5: Mapping genomic regions to transcript-relative coordinates...")
    ex_by_tx <- exonsBy(txdb, by="tx")
    
    mapped_tx <- tryCatch({
        mapToTranscripts(user_gr, ex_by_tx)
    }, error = function(e) {
        message("Warning: mapToTranscripts failed: ", e\$message)
        NULL
    })
    
    if (!is.null(mapped_tx) && length(mapped_tx) > 0) {
        mapped_df <- as.data.frame(mapped_tx)
        # Link back to original region names using query hits (xHits)
        mapped_df\$original_region_name <- user_gr\$name[mapped_df\$xHits]
        
        # Map internal transcript IDs to standard transcript names
        tx_names <- select(txdb, keys=as.character(mapped_df\$seqnames), columns="TXNAME", keytype="TXID")
        mapped_df\$tx_name <- tx_names\$TXNAME[match(mapped_df\$seqnames, tx_names\$TXID)]
        
        write.csv(mapped_df, "transcript_mapping.csv", row.names=FALSE)
        message("Saved transcript-relative mapping to 'transcript_mapping.csv'")
    } else {
        write.csv(data.frame(Message="No regions mapped to transcripts"), "transcript_mapping.csv", row.names=FALSE)
        message("No transcript mappings found; wrote fallback 'transcript_mapping.csv'")
    }
    
    # ==========================================
    # STAGE 6: Compute Coverage by Transcript
    # ==========================================
    message("Stage 6: Computing coverage across transcripts...")
    cov_by_tx <- tryCatch({
        coverageByTranscript(user_gr, txdb)
    }, error = function(e) {
        message("Warning: coverageByTranscript failed: ", e\$message)
        NULL
    })
    
    if (!is.null(cov_by_tx)) {
        cov_sums <- sum(cov_by_tx)
        active_cov <- cov_sums[cov_sums > 0]
        
        if (length(active_cov) > 0) {
            cov_df <- data.frame(
                tx_id = names(active_cov),
                total_coverage_bases = as.numeric(active_cov)
            )
            # Map internal transcript IDs to standard transcript names
            tx_names_cov <- select(txdb, keys=as.character(cov_df\$tx_id), columns="TXNAME", keytype="TXID")
            cov_df\$tx_name <- tx_names_cov\$TXNAME[match(cov_df\$tx_id, tx_names_cov\$TXID)]
            
            write.csv(cov_df, "transcript_coverage.csv", row.names=FALSE)
            message("Saved transcript coverage summary to 'transcript_coverage.csv'")
        } else {
            write.csv(data.frame(Message="No coverage detected on any transcripts"), "transcript_coverage.csv", row.names=FALSE)
            message("No coverage detected; wrote fallback 'transcript_coverage.csv'")
        }
    } else {
        write.csv(data.frame(Message="Coverage computation skipped or failed"), "transcript_coverage.csv", row.names=FALSE)
    }
    
    message("GenomicFeatures pipeline completed successfully!")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_GENOMICFEATURES_GENOMIC_FEATURES_ANNOTATION":
        GenomicFeatures: \$(Rscript -e 'cat(as.character(packageVersion("GenomicFeatures")))')
    END_VERSIONS
```

## Alternatives
- `txdbmaker`: For making `TxDb` objects from genomic annotations (UCSC, Ensembl, GFF) rather than querying existing ones.
- `BSgenome`: For working directly with full genome sequences rather than transcript-specific metadata.
- `GenomicRanges`: For general manipulation of `GRanges` objects rather than extracting them from a database.

## Citations
- Carlson M, Aboyoun P, Pagès H, Falcon S, Morgan M (2026). "Obtaining and Utilizing TxDb Objects." Bioconductor Vignette.

## References
- Homepage: bioconductor.org/packages/GenomicFeatures
- Vignette: vignette_0_d47eae8b.txt
