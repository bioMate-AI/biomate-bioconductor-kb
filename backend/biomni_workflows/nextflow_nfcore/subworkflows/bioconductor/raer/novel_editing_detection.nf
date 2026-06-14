#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: raer — novel_editing_detection
// Identify novel RNA editing sites using matched RNA-seq and DNA-seq (WGS) data.
// Input: bams.bam, fasta.fasta, txdb.sqlite, chr4snps.gr, rmsk_hg38.gr
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

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("GenomicFeatures", "GenomicRanges", "SummarizedExperiment", "raer")
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
    library(raer)
    library(SummarizedExperiment)
    library(GenomicRanges)
    library(GenomicFeatures)
    
    # ==========================================
    # 1. Load User Input Files
    # ==========================================
    
    # BAM files: matched RNA-seq and DNA-seq alignments
    bams <- c(rna = "bams.bam", dna = "bams.bam")
    
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
    ch_input  // channel: [ val(meta), [ bams.bam, fasta.fasta, txdb.sqlite, chr4snps.gr, rmsk_hg38.gr ] ]

    main:
    BIOC_RAER_NOVEL_EDITING_DETECTION(ch_input)

    emit:
    tables   = BIOC_RAER_NOVEL_EDITING_DETECTION.out.tables
    plots    = BIOC_RAER_NOVEL_EDITING_DETECTION.out.plots
    objects  = BIOC_RAER_NOVEL_EDITING_DETECTION.out.objects
    versions = BIOC_RAER_NOVEL_EDITING_DETECTION.out.versions
}
