#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GenomicFeatures — genomic_features_annotation
// Annotate user-defined genomic regions with transcript, exon, intron, CDS, and promoter context, map them to transcript-relative coordinates, and calculate trans
// Input: regions.bed, coldata.csv
// Container: 1.62.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicFeatures, GenomicRanges, IRanges, S4Vectors, TxDb.Hsapiens.UCSC.hg19.knownGene
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENOMICFEATURES_GENOMIC_FEATURES_ANNOTATION {
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
    .bm_deps <- c("GenomicFeatures", "GenomicRanges", "S4Vectors", "TxDb.Hsapiens.UCSC.hg19.knownGene")
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
    
    # Load required Bioconductor libraries
    library(GenomicFeatures)
    library(GenomicRanges)
    library(S4Vectors)
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    
    # ==========================================
    # --- Import User Regions (BED format) ---
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
    # --- Load and Configure TxDb Annotation ---
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
    # --- Extract Genomic Features ---
    # ==========================================
    message("Stage 3: Extracting genomic features from TxDb...")
    tx <- transcripts(txdb)
    ex <- exons(txdb)
    cds_regions <- cds(txdb)
    proms <- promoters(txdb, upstream=2000, downstream=400)
    
    # ==========================================
    # --- Annotate User Regions with Overlaps ---
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
    # --- Map Regions to Transcript Coordinates ---
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
    # --- Compute Coverage by Transcript ---
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

    writeLines(c(
        '"BIOC_GENOMICFEATURES_GENOMIC_FEATURES_ANNOTATION":',
        paste0('    GenomicFeatures: ', as.character(packageVersion('GenomicFeatures')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomic_features_annotation.csv versions.yml
    """
}

workflow BIOC_GENOMICFEATURES_GENOMIC_FEATURES_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_GENOMICFEATURES_GENOMIC_FEATURES_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_GENOMICFEATURES_GENOMIC_FEATURES_ANNOTATION.out.tables
    plots    = BIOC_GENOMICFEATURES_GENOMIC_FEATURES_ANNOTATION.out.plots
    objects  = BIOC_GENOMICFEATURES_GENOMIC_FEATURES_ANNOTATION.out.objects
    versions = BIOC_GENOMICFEATURES_GENOMIC_FEATURES_ANNOTATION.out.versions
}
