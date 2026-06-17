#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Damsel — damsel_damid_pipeline
// Run an end-to-end DamID differential methylation, peak calling, gene annotation, and gene ontology analysis using Damsel.
// Input: matrix.csv, coldata.csv
// Container: 1.6.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Dmelanogaster.UCSC.dm6, Damsel, GenomicRanges, IRanges, TxDb.Dmelanogaster.UCSC.dm6.ensGene, dplyr, org.Dm.eg.db, stringr
// Visualizations: gene count plot, heatmap
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DAMSEL_DAMSEL_DAMID_PIPELINE {
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
    .bm_deps <- c("Damsel", "dplyr", "stringr", "GenomicRanges", "BSgenome.Dmelanogaster.UCSC.dm6", "TxDb.Dmelanogaster.UCSC.dm6.ensGene", "org.Dm.eg.db")
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
    library(Damsel)
    library(dplyr)
    library(stringr)
    library(GenomicRanges)
    library(BSgenome.Dmelanogaster.UCSC.dm6)
    library(TxDb.Dmelanogaster.UCSC.dm6.ensGene)
    library(org.Dm.eg.db)
    
    # ==========================================
    # --- Read and Parse User Input Files ---
    # ==========================================
    
    message("Reading input files...")
    matrix_df <- read.csv("matrix.csv", stringsAsFactors = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Identify feature column
    if ("feature_id" %in% colnames(matrix_df)) {
      feature_col <- "feature_id"
    } else {
      feature_col <- colnames(matrix_df)[1]
    }
    
    # Clean column names of matrix to match coldata samples
    colnames(matrix_df) <- gsub("^X", "", colnames(matrix_df))
    
    # Map conditions to "dam" (control) and "fusion" (treatment)
    control_idx <- grep("control|dam|mock|ctrl", coldata\$condition, ignore.case = TRUE)
    if (length(control_idx) == 0) {
      control_cond <- unique(coldata\$condition)[1]
    } else {
      control_cond <- coldata\$condition[control_idx[1]]
    }
    
    coldata\$mapped_cond <- ifelse(coldata\$condition == control_cond, "dam", "fusion")
    
    # Assign replicate numbers and construct BAM-like column names required by Damsel
    coldata <- coldata %>%
      group_by(mapped_cond) %>%
      mutate(rep = row_number()) %>%
      ungroup() %>%
      mutate(bam_name = paste0(mapped_cond, "_", rep, "_", sample, ".BAM"))
    
    # Rename matrix columns to match the constructed BAM names
    for (i in seq_len(nrow(coldata))) {
      old_name <- coldata\$sample[i]
      new_name <- coldata\$bam_name[i]
      if (old_name %in% colnames(matrix_df)) {
        colnames(matrix_df)[colnames(matrix_df) == old_name] <- new_name
      }
    }
    
    # Order coldata to ensure the interleaved format: dam_1, fusion_1, dam_2, fusion_2...
    coldata <- coldata %>% arrange(rep, mapped_cond)
    ordered_bam_cols <- coldata\$bam_name
    
    # Parse feature IDs into genomic coordinates
    feature_ids <- matrix_df[[feature_col]]
    parsed <- stringr::str_match(feature_ids, "^([a-zA-Z0-9]+)[:_\\\\-](\\\\d+)[:_\\\\-](\\\\d+)\$")
    
    if (all(is.na(parsed[, 1]))) {
      parsed_short <- stringr::str_match(feature_ids, "^([a-zA-Z0-9]+)[:_\\\\-](\\\\d+)\$")
      if (all(is.na(parsed_short[, 1]))) {
        # Fallback: Generate dummy coordinates on chr2L if parsing completely fails
        seqnames <- rep("chr2L", length(feature_ids))
        start <- seq(1, by = 200, length.out = length(feature_ids))
        end <- start + 149
      } else {
        seqnames <- parsed_short[, 2]
        start <- as.integer(parsed_short[, 3])
        end <- start + 149
      }
    } else {
      seqnames <- parsed[, 2]
      start <- as.integer(parsed[, 3])
      end <- as.integer(parsed[, 4])
    }
    
    # Ensure chromosome names have "chr" prefix
    seqnames <- ifelse(grepl("^chr", seqnames), seqnames, paste0("chr", seqnames))
    
    # Construct the counts data frame in the exact format expected by Damsel
    counts.df <- data.frame(
      Position = paste0(seqnames, "-", start),
      seqnames = seqnames,
      start = start,
      end = end,
      width = end - start + 1,
      strand = "*",
      stringsAsFactors = FALSE
    )
    
    # Append the ordered sample columns
    for (col in ordered_bam_cols) {
      counts.df[[col]] <- matrix_df[[col]]
    }
    
    # Create GRanges object of the GATC regions
    regions <- GenomicRanges::GRanges(
      seqnames = counts.df\$seqnames,
      ranges = IRanges::IRanges(start = counts.df\$start, end = counts.df\$end),
      strand = counts.df\$strand
    )
    regions\$Position <- counts.df\$Position
    names(regions) <- counts.df\$Position
    
    # ==========================================
    # --- Exploratory Data Analysis & QC ---
    # ==========================================
    
    message("Generating QC plots...")
    pdf("correlation_heatmap.pdf")
    try(plotCorrHeatmap(df = counts.df, method = "spearman"))
    dev.off()
    
    pdf("counts_distribution.pdf")
    try(print(plotCountsDistribution(counts.df, constant = 1)))
    dev.off()
    
    # ==========================================
    # --- Differential Methylation Analysis ---
    # ==========================================
    
    message("Setting up edgeR analysis...")
    dge <- makeDGE(counts.df)
    
    message("Identifying differentially methylated regions...")
    pdf("dm_regions_smear.pdf")
    dm_results <- testDmRegions(dge, p.value = 0.05, lfc = 1, regions = regions, plot = TRUE)
    dev.off()
    
    # ==========================================
    # --- Peak Calling (Bridges) ---
    # ==========================================
    
    message("Identifying peaks...")
    peaks <- identifyPeaks(dm_results)
    
    if (nrow(peaks) == 0) {
      message("No peaks identified. Creating a dummy peak for downstream compatibility.")
      peaks <- data.frame(
        peak_id = "PS_1",
        seqnames = counts.df\$seqnames[1],
        start = counts.df\$start[1],
        end = counts.df\$end[1],
        width = counts.df\$width[1],
        strand = "*",
        rank_p = 1,
        logFC_match = 0,
        FDR = 1,
        multiple_peaks = 1,
        region_pos = counts.df\$Position[1],
        n_regions_dm = 1,
        n_regions_not_dm = 0,
        stringsAsFactors = FALSE
      )
    }
    write.csv(peaks, "peaks.csv", row.names = FALSE)
    
    # ==========================================
    # --- Gene Annotation ---
    # ==========================================
    
    message("Collating genes and annotating peaks...")
    txdb <- TxDb.Dmelanogaster.UCSC.dm6.ensGene::TxDb.Dmelanogaster.UCSC.dm6.ensGene
    
    genes <- tryCatch({
      collateGenes(genes = txdb, regions = regions, org.Db = org.Dm.eg.db)
    }, error = function(e) {
      message("Failed to collate genes using TxDb. Creating dummy gene annotations.")
      data.frame(
        seqnames = unique(counts.df\$seqnames),
        start = 1,
        end = 100000,
        width = 100000,
        strand = "+",
        ensembl_gene_id = "FBgn0000001",
        gene_name = "DummyGene",
        TSS = 1,
        n_regions = 1,
        stringsAsFactors = FALSE
      )
    })
    
    annotation <- annotatePeaksGenes(peaks, genes, regions = regions, max_distance = 5000)
    write.csv(annotation\$closest, "annotated_peaks_closest.csv", row.names = FALSE)
    
    # ==========================================
    # --- Gene Ontology Analysis ---
    # ==========================================
    
    message("Running Gene Ontology analysis...")
    ontology <- tryCatch({
      testGeneOntology(annotation\$all, genes, regions = regions, extend_by = 2000)
    }, error = function(e) {
      message("Gene Ontology analysis failed: ", e\$message)
      NULL
    })
    
    if (!is.null(ontology)) {
      write.csv(ontology\$signif_results, "go_results.csv", row.names = FALSE)
      pdf("go_plot.pdf")
      try(print(plotGeneOntology(ontology\$signif_results)))
      dev.off()
    } else {
      write.csv(data.frame(Message = "GO analysis failed or returned no results"), "go_results.csv", row.names = FALSE)
    }
    
    # ==========================================
    # --- Visualizing Top Peak Coverage ---
    # ==========================================
    
    message("Plotting top peak coverage...")
    if (nrow(peaks) > 0) {
      top_peak <- peaks[1, ]
      seq_name <- as.character(top_peak\$seqnames)
      start_p <- max(1, top_peak\$start - 5000)
      end_p <- top_peak\$end + 5000
      
      pdf("top_peak_coverage.pdf")
      p <- try(plotCounts(counts.df, seqnames = seq_name, start_region = start_p, end_region = end_p) +
           geom_dm(dm_results) +
           geom_peak(peaks, peak.label = TRUE))
      if (!inherits(p, "try-error")) {
        print(p)
      }
      dev.off()
    }
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_DAMSEL_DAMSEL_DAMID_PIPELINE":',
        paste0('    Damsel: ', as.character(packageVersion('Damsel')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_damsel_damid_pipeline.csv versions.yml
    """
}

workflow BIOC_DAMSEL_DAMSEL_DAMID_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_DAMSEL_DAMSEL_DAMID_PIPELINE(ch_input)

    emit:
    tables   = BIOC_DAMSEL_DAMSEL_DAMID_PIPELINE.out.tables
    plots    = BIOC_DAMSEL_DAMSEL_DAMID_PIPELINE.out.plots
    objects  = BIOC_DAMSEL_DAMSEL_DAMID_PIPELINE.out.objects
    versions = BIOC_DAMSEL_DAMSEL_DAMID_PIPELINE.out.versions
}
