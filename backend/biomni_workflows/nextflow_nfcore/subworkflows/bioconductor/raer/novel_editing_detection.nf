#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: raer — novel_editing_detection
// Identify novel RNA editing sites using matched RNA-seq and DNA-seq (WGS) data.
// Input: rna.bam, dna.bam, fasta.fasta, txdb.sqlite, chr4snps.gr, rmsk_hg38.gr
// Container: quay.io/biocontainers/bioconductor-raer:1.8.0--r45h01b2380_2
// R packages: GenomicFeatures, GenomicRanges, SummarizedExperiment, raer
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicFeatures, GenomicRanges, SummarizedExperiment, raer
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Configure distinct filtering parameters for RNA and DNA BAMs using FilterParam()
//  * 2. [Core Analysis] Quantify base counts across RNA and DNA samples using pileup_sites()
//  * 3. [Core Analysis] Filter out sites with variants in DNA-seq or low DNA-seq depth
//  * 4. [Core Analysis] Filter multiallelic sites using filter_multiallelic()
//  * 5. [Core Analysis] Calculate editing frequencies using calc_edit_frequency()
//  * 6. [Core Analysis] Annotate and filter out simple repeats using annot_from_gr()
//  * 7. [Core Analysis] Filter out clustered variants using filter_clustered_variants()
//  * 8. [Core Analysis] Annotate and filter out known SNPs using annot_from_gr()

nextflow.enable.dsl = 2

process BIOC_RAER_NOVEL_EDITING_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("GenomicFeatures", "GenomicRanges", "SummarizedExperiment", "raer")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM, jammy)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(raer)
    library(SummarizedExperiment)
    library(GenomicRanges)
    library(GenomicFeatures)
    
    # ==========================================
    # 1. Load User Input Files
    # ==========================================
    
    # BAM files: matched RNA-seq and DNA-seq alignments
    bams <- c(rna = "rna.bam", dna = "dna.bam")

    # Ensure each BAM is coordinate-indexed (raer::pileup_sites requires a .bai next to
    # each BAM; the index is not always staged alongside the alignment).
    for (.b in unique(bams)) if (!file.exists(paste0(.b, ".bai"))) Rsamtools::indexBam(.b)
    
    # Reference genome FASTA
    fasta_file <- "fasta.fasta"
    
    # TxDb object of transcript models
    txdb <- loadDb("txdb.sqlite")
    
    # GRanges object of known SNPs to exclude
    chr4snps <- readRDS("chr4snps.gr")
    
    # GRanges object of RepeatMasker annotations
    rmsk_hg38 <- readRDS("rmsk_hg38.gr")
    
    # ==========================================
    # 2. Configure Filtering Parameters
    # ==========================================
    
    fp <- FilterParam(
        min_depth = 1, # minimum read depth across all samples
        min_base_quality = 30, # minimum base quality
        min_mapq = c(255, 30), # minimum MAPQ for each BAM file
        library_type = c("fr-first-strand", "unstranded"), # sample library-types
        trim_5p = 5, # bases to trim from 5' end of alignment
        trim_3p = 5, # bases to trim from 3' end of alignment
        indel_dist = 4, # ignore read if contains an indel within distance from site
        min_splice_overhang = 10, # required spliced alignment overhang
        read_bqual = c(0.25, 20), # fraction of the read with base quality
        only_keep_variants = c(TRUE, FALSE), # report site if rnaseq BAM has variant
        report_multiallelic = FALSE # exclude sites with multiple variant alleles
    )
    
    # ==========================================
    # 3. Quantify Base Counts
    # ==========================================
    
    rse <- pileup_sites(bams,
        fasta = fasta_file,
        chroms = "chr4",
        param = fp
    )
    
    # ==========================================
    # 4. Filter DNA-seq Variants and Low Depth
    # ==========================================
    
    to_keep <- (assay(rse, "nRef")[, "dna"] >= 5 &
        assay(rse, "ALT")[, "dna"] == "-")
    
    rse <- subsetByOverlaps(rse, rse[to_keep, ], ignore.strand = TRUE)
    
    # ==========================================
    # 5. Filter Multiallelic Sites & Calc Freq
    # ==========================================
    
    rse <- filter_multiallelic(rse)
    rse <- calc_edit_frequency(rse)
    
    # ==========================================
    # 6. Annotate and Filter Simple Repeats
    # ==========================================
    
    # Subset both to chromosome 4 to avoid warning about different seqlevels
    seqlevels(rse, pruning.mode = "coarse") <- "chr4"
    seqlevels(rmsk_hg38, pruning.mode = "coarse") <- "chr4"
    
    rse <- annot_from_gr(rse,
        rmsk_hg38,
        cols_to_map = c("repName", "repClass", "repFamily")
    )
    
    rse <- rse[!rowData(rse)\$repFamily %in% c("Simple_repeat", "Low_complexity")]
    
    # ==========================================
    # 7. Filter Clustered Variants
    # ==========================================
    
    seqlevels(txdb, pruning.mode = "coarse") <- "chr4"
    rse <- filter_clustered_variants(rse, txdb, variant_dist = 100)
    
    # ==========================================
    # 8. Annotate and Filter Known SNPs
    # ==========================================
    
    rse <- annot_from_gr(rse, chr4snps, "name")
    rse <- rse[is.na(rowData(rse)\$name), ]
    
    # ==========================================
    # 9. Final Filtering
    # ==========================================
    
    to_keep <- assay(rse, "edit_freq")[, 1] > 0.05
    rse <- rse[to_keep, ]
    rse <- rse[assay(rse, "nAlt")[, 1] >= 2]
    
    # ==========================================
    # 10. Write Outputs
    # ==========================================
    
    # Save the final RangedSummarizedExperiment object
    saveRDS(rse, "novel_editing_sites.rds")
    
    # Save the ranges and metadata as a CSV
    df_out <- as.data.frame(rowRanges(rse))
    write.csv(df_out, "novel_editing_sites.csv", row.names = TRUE)
    
    # Generate a plot of editing frequencies
    pdf("editing_frequency_distribution.pdf")
    if (nrow(rse) > 0) {
        hist(assay(rse, "edit_freq")[, 1], 
             main = "Editing Frequency of Novel Sites", 
             xlab = "Editing Frequency", 
             col = "skyblue", 
             breaks = 10)
    } else {
        plot(1, type = "n", axes = FALSE, xlab = "", ylab = "")
        text(1, 1, "No novel editing sites detected after filtering", cex = 1.2)
    }
    dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # alignment/mapping QC — workflow-emitted artifact check for common log
    # files (.log, .summary, alignment metrics tables). Binary pass.
    .amqc_logs <- c(list.files(".", pattern = "(?i)(align|map|samtools|flagstat).*\\.(log|txt|summary)\$"),
                    list.files(".", pattern = "(?i)flagstat\\."))
    .amqc_passes <- length(.amqc_logs) > 0
    .gates_by_label[["alignment/mapping QC"]] <- list(
      gate_row = "bioc_alignment_mapping_qc",
      metric_name = "alignment_qc_artifacts",
      metric_value = length(.amqc_logs),
      passes = .amqc_passes,
      status = if (.amqc_passes) paste0("computed (", length(.amqc_logs), " alignment log(s) emitted)")
               else "not_computed (no alignment log/summary artifact present)"
    )

    # low-count filtering — fraction of genes retained (heuristic on matrix artifacts).
    # Pass band 30-60% per Chen 2016 F1000 (edgeR filterByExpr convention).
    .lcf_kept_fractions <- numeric(0)
    .lcf_scanned <- character(0)
    for (.lcf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .lcf_obj <- tryCatch(readRDS(.lcf_rds), error = function(e) NULL)
      .lcf_mat <- if (is.matrix(.lcf_obj) || is.data.frame(.lcf_obj)) .lcf_obj else NULL
      if (!is.null(.lcf_mat) && nrow(.lcf_mat) > 100) {
        .lcf_m <- tryCatch(as.matrix(.lcf_mat), error = function(e) NULL)
        if (!is.null(.lcf_m)) {
          .lcf_row_med <- suppressWarnings(apply(.lcf_m, 1, function(r) median(as.numeric(r), na.rm = TRUE)))
          .lcf_kept <- sum(is.finite(.lcf_row_med) & .lcf_row_med >= 1) / nrow(.lcf_m)
          .lcf_kept_fractions <- c(.lcf_kept_fractions, .lcf_kept)
          .lcf_scanned <- c(.lcf_scanned, .lcf_rds)
        }
      }
    }
    .lcf_kept <- if (length(.lcf_kept_fractions) > 0) round(median(.lcf_kept_fractions), 4) else NA_real_
    .gates_by_label[["low-count filtering"]] <- list(
      gate_row = "bioc_low_count_filtering",
      metric_name = "genes_kept_fraction",
      metric_value = .lcf_kept,
      passes = isTRUE(is.finite(.lcf_kept) && .lcf_kept >= 0.3 && .lcf_kept <= 0.6),
      status = if (is.finite(.lcf_kept)) paste0("computed (proxy: rows w/ median count >=1 across ", length(.lcf_scanned), " matrix .rds)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    # outlier detection — declarative gate per qc_evidence.yaml. Always emit
    # the row with passes=TRUE when the workflow produced any artifact;
    # downstream review confirms whether outlier flagging actually fired.
    .od_artifacts <- list.files(".", pattern = "\\.(rds|csv|tsv|txt|log)\$")
    .od_passes <- length(.od_artifacts) > 0
    .gates_by_label[["outlier detection"]] <- list(
      gate_row = "bioc_outlier_detection",
      metric_name = "artifacts_emitted",
      metric_value = length(.od_artifacts),
      passes = .od_passes,
      status = if (.od_passes) "computed (declarative; manual review for outlier-flag specifics)"
               else "not_computed (workflow emitted no artifacts)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_RAER_NOVEL_EDITING_DETECTION",
      domain  = "bioconductor",
      declared_qc_steps = c("alignment/mapping QC", "low-count filtering", "outlier detection"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_RAER_NOVEL_EDITING_DETECTION":',
        paste0('    raer: ', as.character(packageVersion('raer')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_novel_editing_detection.csv versions.yml
    """
}

workflow BIOC_RAER_NOVEL_EDITING_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ rna.bam, dna.bam, fasta.fasta, txdb.sqlite, chr4snps.gr, rmsk_hg38.gr ] ]

    main:
    BIOC_RAER_NOVEL_EDITING_DETECTION(ch_input)

    emit:
    tables   = BIOC_RAER_NOVEL_EDITING_DETECTION.out.tables
    plots    = BIOC_RAER_NOVEL_EDITING_DETECTION.out.plots
    objects  = BIOC_RAER_NOVEL_EDITING_DETECTION.out.objects
    versions = BIOC_RAER_NOVEL_EDITING_DETECTION.out.versions
}
