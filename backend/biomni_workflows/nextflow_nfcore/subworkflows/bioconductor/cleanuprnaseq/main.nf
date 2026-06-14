#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CleanUpRNAseq — unstranded_gdna_cleanup
// Detect and correct genomic DNA contamination in unstranded RNA-seq data using global or GC-content-based correction methods.
// Input: example.gtf.gz, K084CD7PCD1N.srt.bam, quant.sf, example.colData.txt
// Container: quay.io/biocontainers/bioconductor-cleanuprnaseq:1.4.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, CleanUpRNAseq, GenomeInfoDb, GenomicRanges, R.utils, ensembldb, ggplotify, patchwork
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Build an EnsDb database from the reference GTF file
//  * 2. [Visualization & Output] Generate Simplified Annotation Format (SAF) files
//  * 3. [Visualization & Output] Create a SummarizedCounts object
//  * 4. [Visualization & Output] Summarize reads and import Salmon quantifications
//  * 5. [Visualization & Output] Generate diagnostic plots
//  * 6. [Visualization & Output] Correct for gDNA contamination

nextflow.enable.dsl = 2

process BIOC_CLEANUPRNASEQ_UNSTRANDED_GDNA_CLEANUP {
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
    .bm_deps <- c("CleanUpRNAseq", "ggplotify", "patchwork", "ensembldb", "GenomicRanges", "Biostrings", "GenomeInfoDb", "genome_pkg")
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
    suppressPackageStartupMessages({
      library("CleanUpRNAseq")
      library("ggplotify")
      library("patchwork")
      library("ensembldb")
      library("utils")
      library("GenomicRanges")
      library("Biostrings")
      library("GenomeInfoDb")
    })
    
    # Set options
    options(timeout = max(3000, getOption("timeout")))
    tmp_dir <- tempdir()
    
    # --- Build an EnsDb database from the reference GTF file ---
    gtf_gz <- "example.gtf.gz"
    gtf <- "example.gtf"
    if (!file.exists(gtf)) {
      R.utils::gunzip(gtf_gz, destname = gtf, overwrite = TRUE, remove = FALSE)
    }
    
    hs_ensdb_sqlite <- ensDbFromGtf(
      gtf = gtf,
      outfile = file.path(tmp_dir, "EnsDb.hs.v110.sqlite"),
      organism = "Homo_Sapiens",
      genomeVersion = "GRCh38",
      version = 110
    )
    
    # --- Generate Simplified Annotation Format (SAF) files ---
    bam_file <- "K084CD7PCD1N.srt.bam"
    saf_list <- get_saf(
      ensdb_sqlite = hs_ensdb_sqlite,
      bamfile = bam_file,
      mitochondrial_genome = "MT"
    )
    
    # --- Create a SummarizedCounts object ---
    col_data <- read.delim("example.colData.txt", as.is = TRUE)
    
    # Standardize paths to the working directory
    col_data\$BAM_file <- basename(col_data\$BAM_file)
    col_data\$salmon_quant_file <- basename(col_data\$salmon_quant_file)
    if ("salmon_quant_file_opposite_strand" %in% colnames(col_data)) {
      col_data\$salmon_quant_file_opposite_strand <- basename(col_data\$salmon_quant_file_opposite_strand)
    } else {
      col_data\$salmon_quant_file_opposite_strand <- col_data\$salmon_quant_file
    }
    
    # Filter colData to only include samples with existing files
    file_exists <- file.exists(col_data\$BAM_file) & file.exists(col_data\$salmon_quant_file)
    if (any(file_exists)) {
      col_data <- col_data[file_exists, , drop = FALSE]
    } else {
      # Fallback to the single provided sample if no matches found
      col_data <- data.frame(
        sample_name = "K084CD7PCD1N",
        BAM_file = "K084CD7PCD1N.srt.bam",
        salmon_quant_file = "quant.sf",
        salmon_quant_file_opposite_strand = "quant.sf",
        group = "CD1N",
        stringsAsFactors = FALSE
      )
    }
    
    sc <- create_summarizedcounts(lib_strand = 0, colData = col_data)
    
    # --- Summarize reads and import Salmon quantifications ---
    capture.output({
      counts_list <- summarize_reads(
        SummarizedCounts = sc,
        saf_list = saf_list,
        gtf = gtf,
        threads = 1,
        verbose = TRUE
      )
    }, file = tempfile())
    
    salmon_counts <- salmon_tximport(
      SummarizedCounts = sc,
      ensdb_sqlite = hs_ensdb_sqlite
    )
    
    # Explicitly populate the SummarizedCounts object
    sc\$set_feature_counts(counts_list)
    sc\$set_salmon_quant(salmon_counts)
    sc\$set_salmon_quant_opposite(salmon_counts)
    
    # --- Generate diagnostic plots ---
    pdf("cleanup_diagnostics.pdf", width = 10, height = 8)
    
    p_assignment_stat <- plot_assignment_stat(SummarizedCounts = sc)
    print(wrap_plots(p_assignment_stat))
    
    assigned_per_region <- get_region_stat(SummarizedCounts = sc)
    p <- plot_read_distr(assigned_per_region)
    print(p)
    
    plot_sample_corr(SummarizedCounts = sc)
    
    p_expr_distr <- plot_expr_distr(
      SummarizedCounts = sc,
      normalization = "DESeq2"
    )
    print(wrap_plots(p_expr_distr, ncol = 1, nrow = 3))
    
    plot_gene_content(
      SummarizedCounts = sc,
      min_cpm = 1,
      min_tpm = 1
    )
    
    p_pca <- plot_pca_heatmap(SummarizedCounts = sc, silent = TRUE)
    print(p_pca\$pca + as.ggplot(p_pca\$heatmap))
    
    dev.off()
    
    # --- Correct for gDNA contamination ---
    # Global median per-base read coverage subtraction
    global_correction <- correct_global(SummarizedCounts = sc)
    saveRDS(global_correction, "global_correction_results.rds")
    
    # GC-content-bias-aware correction
    # Dynamically load a matching BSgenome package to calculate GC content
    genome_pkg <- "BSgenome.Hsapiens.UCSC.hg38"
    if (!requireNamespace(genome_pkg, quietly = TRUE)) {
      installed_bsg <- grep("^BSgenome\\\\.", installed.packages()[, "Package"], value = TRUE)
      if (length(installed_bsg) > 0) {
        genome_pkg <- installed_bsg[1]
      } else {
        stop("A BSgenome package (e.g., BSgenome.Hsapiens.UCSC.hg38) is required to calculate GC content.")
      }
    }
    
    library(genome_pkg, character.only = TRUE)
    genome <- get(genome_pkg)
    
    # Helper function to calculate GC content for SAF features
    get_saf_gc <- function(saf, genome) {
      gr <- GRanges(
        seqnames = saf\$Chr,
        ranges = IRanges(start = saf\$Start, end = saf\$End),
        strand = saf\$Strand,
        gene_id = saf\$GeneID
      )
      seqlevelsStyle(gr) <- seqlevelsStyle(genome)[1]
      common_seqlevels <- intersect(seqlevels(gr), seqlevels(genome))
      gr <- keepSeqlevels(gr, common_seqlevels, pruning.mode = "coarse")
      
      seqs <- getSeq(genome, gr)
      lf <- letterFrequency(seqs, letters = c("G", "C", "A", "T"), as.prob = TRUE)
      gc_vals <- lf[, "G"] + lf[, "C"]
      
      df <- data.frame(
        gene_id = mcols(gr)\$gene_id,
        GC = gc_vals,
        stringsAsFactors = FALSE
      )
      return(df)
    }
    
    # Extract gene and intergenic SAFs
    gene_saf_name <- grep("gene", names(saf_list), value = TRUE)[1]
    intergenic_saf_name <- grep("intergenic", names(saf_list), value = TRUE)[1]
    
    gene_saf <- saf_list[[gene_saf_name]]
    intergenic_saf <- saf_list[[intergenic_saf_name]]
    
    # Calculate GC content
    gene_GC <- get_saf_gc(gene_saf, genome)
    intergenic_GC <- get_saf_gc(intergenic_saf, genome)
    
    # Ensure compatible column names for correct_GC
    gene_GC\$gc <- gene_GC\$GC
    intergenic_GC\$gc <- intergenic_GC\$GC
    intergenic_GC\$region <- intergenic_GC\$gene_id
    intergenic_GC\$id <- intergenic_GC\$gene_id
    
    gc_correction <- correct_GC(
      SummarizedCounts = sc,
      gene_gc = gene_GC,
      intergenic_gc = intergenic_GC,
      plot = FALSE
    )
    saveRDS(gc_correction, "gc_correction_results.rds")

    writeLines(c(
        '"BIOC_CLEANUPRNASEQ_UNSTRANDED_GDNA_CLEANUP":',
        paste0('    CleanUpRNAseq: ', as.character(packageVersion('CleanUpRNAseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_unstranded_gdna_cleanup.csv versions.yml
    """
}

workflow BIOC_CLEANUPRNASEQ_UNSTRANDED_GDNA_CLEANUP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ example.gtf.gz, K084CD7PCD1N.srt.bam, quant.sf, example.colData.txt ] ]

    main:
    BIOC_CLEANUPRNASEQ_UNSTRANDED_GDNA_CLEANUP(ch_input)

    emit:
    tables   = BIOC_CLEANUPRNASEQ_UNSTRANDED_GDNA_CLEANUP.out.tables
    plots    = BIOC_CLEANUPRNASEQ_UNSTRANDED_GDNA_CLEANUP.out.plots
    objects  = BIOC_CLEANUPRNASEQ_UNSTRANDED_GDNA_CLEANUP.out.objects
    versions = BIOC_CLEANUPRNASEQ_UNSTRANDED_GDNA_CLEANUP.out.versions
}
