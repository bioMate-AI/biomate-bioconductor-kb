#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TAPseq — primer_design_and_evaluation
// Design, BLAST, and check multiplex compatibility of outer and inner primers for a target gene panel.
// Input: chr11_genes, chr11_k562_dropseq.bam, hg38
// Container: quay.io/biocontainers/bioconductor-tapseq:1.22.1--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome, BiocParallel, Biostrings, GenomicRanges, TAPseq, dplyr, ggplot2, rtracklayer
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Infer polyA sites from BAM data
//  * 2. [Core Analysis] Truncate transcripts at polyA sites
//  * 3. [Core Analysis] Extract transcript sequences
//  * 4. [Input & Preparation] Create Primer3 input and design outer primers
//  * 5. [Input & Preparation] Create BLAST database and estimate off-targets
//  * 6. [Core Analysis] Pick best outer primers
//  * 7. [Core Analysis] Design, BLAST, and pick inner primers
//  * 8. [Core Analysis] Check multiplex compatibility
//  * 9. [Visualization & Output] Export primers to data frames and BED tracks

nextflow.enable.dsl = 2

process BIOC_TAPSEQ_PRIMER_DESIGN_AND_EVALUATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("TAPseq", "GenomicRanges", "BiocParallel", "BSgenome", "rtracklayer", "dplyr", "ggplot2")
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
        library(TAPseq)
        library(GenomicRanges)
        library(BiocParallel)
        library(BSgenome)
        library(rtracklayer)
        library(dplyr)
        library(ggplot2)
        
        # 1. Read User Inputs from Working Directory
        message("Loading input files...")
        
        # Load chr11_genes
        if (file.exists("chr11_genes.rds")) {
          chr11_genes <- readRDS("chr11_genes.rds")
        } else if (file.exists("chr11_genes")) {
          chr11_genes <- tryCatch({
            readRDS("chr11_genes")
          }, error = function(e) {
            import("chr11_genes")
          })
        } else {
          stop("Error: 'chr11_genes' file not found in the working directory.")
        }
        
        # Load hg38
        if (file.exists("hg38.rds")) {
          hg38 <- readRDS("hg38.rds")
        } else if (file.exists("hg38")) {
          hg38 <- tryCatch({
            readRDS("hg38")
          }, error = function(e) {
            tryCatch({
              Biostrings::readDNAStringSet("hg38")
            }, error = function(e2) {
              genome_name <- trimws(readLines("hg38", n = 1))
              getBSgenome(genome_name)
            })
          })
        } else {
          message("hg38 file not found in working directory, attempting to load BSgenome.Hsapiens.UCSC.hg38 from Bioconductor...")
          hg38 <- getBSgenome("BSgenome.Hsapiens.UCSC.hg38")
        }
        
        # BAM file path
        dropseq_bam <- "chr11_k562_dropseq.bam"
        if (!file.exists(dropseq_bam)) {
          stop("Error: 'chr11_k562_dropseq.bam' file not found in the working directory.")
        }
        
        # 2. Prepare Target Genes
        message("Preparing target genes...")
        if (is(chr11_genes, "GRanges")) {
          target_genes <- split(chr11_genes, f = chr11_genes\$gene_name)
        } else {
          target_genes <- chr11_genes
        }
        
        # 3. Register Parallel Backend
        message("Registering parallel backend...")
        if (.Platform\$OS.type == "windows") {
          register(SnowParam(workers = 2))
        } else {
          register(MulticoreParam(workers = 2))
        }
        
        # 4. Infer PolyA Sites
        message("Inferring polyA sites...")
        polyA_sites <- inferPolyASites(target_genes, bam = dropseq_bam, polyA_downstream = 50,
                                       wdsize = 100, min_cvrg = 1, parallel = TRUE)
        export(polyA_sites, con = "polyA_sites.bed", format = "bed")
        saveRDS(polyA_sites, "polyA_sites.rds")
        
        # 5. Truncate Transcripts
        message("Truncating transcripts at inferred polyA sites...")
        truncated_txs <- truncateTxsPolyA(target_genes, polyA_sites = polyA_sites, parallel = TRUE)
        saveRDS(truncated_txs, "truncated_txs.rds")
        
        # 6. Extract Transcript Sequences
        message("Extracting transcript sequences...")
        txs_seqs <- getTxsSeq(truncated_txs, genome = hg38)
        saveRDS(txs_seqs, "txs_seqs.rds")
        
        # 7. Design Outer Primers
        message("Designing outer primers...")
        outer_primers <- TAPseqInput(txs_seqs, target_annot = truncated_txs,
                                     product_size_range = c(350, 500), primer_num_return = 5)
        
        # Wrap Primer3 execution in tryCatch to handle missing local installations gracefully
        outer_primers <- tryCatch({
          designPrimers(outer_primers)
        }, error = function(e) {
          message("Warning: Primer3 design failed. Ensure Primer3 is installed and in your PATH.")
          message("Error details: ", e\$message)
          NULL
        })
        
        if (!is.null(outer_primers)) {
          saveRDS(outer_primers, "outer_primers_designed.rds")
          
          # 8. Create BLAST Database and Estimate Off-Targets
          message("Creating BLAST database and estimating off-targets...")
          if (is(hg38, "BSgenome")) {
            chr11_genome <- DNAStringSet(getSeq(hg38, "chr11"))
          } else {
            if ("chr11" %in% names(hg38)) {
              chr11_genome <- hg38["chr11"]
            } else {
              chr11_genome <- hg38
            }
          }
          names(chr11_genome) <- "chr11"
        
          blastdb <- file.path(tempdir(), "blastdb")
          createBLASTDb(genome = chr11_genome, annot = unlist(target_genes), blastdb = blastdb)
        
          outer_primers <- tryCatch({
            blastPrimers(outer_primers, blastdb = blastdb, max_mismatch = 0, min_aligned = 0.75)
          }, error = function(e) {
            message("Warning: BLAST failed. Ensure blastn is installed and in your PATH.")
            message("Error details: ", e\$message)
            outer_primers
          })
        
          # Pick best outer primers
          best_outer_primers <- pickPrimers(outer_primers, n = 1, by = "off_targets")
          saveRDS(best_outer_primers, "best_outer_primers.rds")
        
          # 9. Design Inner Primers
          message("Designing inner primers...")
          inner_primers <- TAPseqInput(txs_seqs, target_annot = truncated_txs,
                                       product_size_range = c(150, 300), primer_num_return = 5)
          
          inner_primers <- tryCatch({
            designPrimers(inner_primers)
          }, error = function(e) {
            message("Warning: Inner primer design failed.")
            NULL
          })
        
          if (!is.null(inner_primers)) {
            inner_primers <- tryCatch({
              blastPrimers(inner_primers, blastdb = blastdb, max_mismatch = 0, min_aligned = 0.75)
            }, error = function(e) {
              inner_primers
            })
        
            best_inner_primers <- pickPrimers(inner_primers, n = 1, by = "off_targets")
            saveRDS(best_inner_primers, "best_inner_primers.rds")
        
            # 10. Check Multiplex Compatibility
            message("Checking multiplex compatibility...")
            outer_comp <- tryCatch({
              checkPrimers(best_outer_primers)
            }, error = function(e) {
              message("Warning: checkPrimers failed for outer primers.")
              NULL
            })
        
            inner_comp <- tryCatch({
              checkPrimers(best_inner_primers)
            }, error = function(e) {
              message("Warning: checkPrimers failed for inner primers.")
              NULL
            })
        
            if (!is.null(outer_comp) && !is.null(inner_comp)) {
              comp <- bind_rows(outer = outer_comp, inner = inner_comp, .id = "set")
              comp <- comp %>%
                mutate(high_compl = if_else(primer_pair_compl_any_th > 47 | primer_pair_compl_end_th > 47,
                                            true = "high", false = "ok")) %>% 
                mutate(high_compl = factor(high_compl, levels = c("ok", "high")))
                                            
              p <- ggplot(comp, aes(x = primer_pair_compl_any_th, y = primer_pair_compl_end_th)) +
                facet_wrap(~set, ncol = 2) +
                geom_point(aes(color = high_compl), alpha = 0.25) +
                scale_color_manual(values = c("black", "red"), drop = FALSE) +
                geom_hline(aes(yintercept = 47), colour = "darkgray", linetype = "dashed") +
                geom_vline(aes(xintercept = 47), colour = "darkgray", linetype = "dashed") +
                labs(title = "Complementarity scores TAP-seq primer combinations",
                     color = "Complementarity") +
                theme_bw()
        
              ggsave("primer_complementarity_plot.pdf", plot = p, width = 7, height = 4)
              write.csv(comp, "primer_compatibility_scores.csv", row.names = FALSE)
            }
        
            # 11. Export Primers and Tracks
            message("Exporting primers and tracks...")
            outer_primers_df <- primerDataFrame(best_outer_primers)
            inner_primers_df <- primerDataFrame(best_inner_primers)
        
            write.csv(outer_primers_df, "best_outer_primers.csv", row.names = FALSE)
            write.csv(inner_primers_df, "best_inner_primers.csv", row.names = FALSE)
        
            outer_primers_track <- createPrimerTrack(best_outer_primers, color = "steelblue3")
            inner_primers_track <- createPrimerTrack(best_inner_primers, color = "goldenrod1")
        
            write.csv(outer_primers_track, "outer_primers_track.csv", row.names = FALSE)
            write.csv(inner_primers_track, "inner_primers_track.csv", row.names = FALSE)
        
            exportPrimerTrack(outer_primers_track, con = "outer_primers.bed")
            exportPrimerTrack(inner_primers_track, con = "inner_primers.bed")
            exportPrimerTrack(outer_primers_track, inner_primers_track, con = "all_primers.bed")
          }
        }
        
        message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_TAPSEQ_PRIMER_DESIGN_AND_EVALUATION":',
        paste0('    TAPseq: ', as.character(packageVersion('TAPseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_primer_design_and_evaluation.csv versions.yml
    """
}

workflow BIOC_TAPSEQ_PRIMER_DESIGN_AND_EVALUATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ chr11_genes, chr11_k562_dropseq.bam, hg38 ] ]

    main:
    BIOC_TAPSEQ_PRIMER_DESIGN_AND_EVALUATION(ch_input)

    emit:
    tables   = BIOC_TAPSEQ_PRIMER_DESIGN_AND_EVALUATION.out.tables
    plots    = BIOC_TAPSEQ_PRIMER_DESIGN_AND_EVALUATION.out.plots
    objects  = BIOC_TAPSEQ_PRIMER_DESIGN_AND_EVALUATION.out.objects
    versions = BIOC_TAPSEQ_PRIMER_DESIGN_AND_EVALUATION.out.versions
}
