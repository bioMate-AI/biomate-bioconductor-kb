#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SGSeq — de_novo_splice_analysis
// Predict novel splice features de novo from RNA-seq data, annotate them, identify splice variants, and predict their functional effects.
// Input: file_bam, gr, txdb, Hsapiens
// Container: quay.io/biocontainers/bioconductor-sgseq:1.44.0--r45hdfd78af_0
// R packages: BSgenome, GenomicFeatures, GenomicRanges, SGSeq
// Bioconductor: 3.20 | R: 4.4
// Requires: AnnotationDbi, BSgenome, GenomicFeatures, GenomicRanges, SGSeq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Predict transcript features and count compatible fragments using analyzeFeatures()
//  * 2. [Core Analysis] Annotate predicted features with known transcripts using annotate()
//  * 3. [Core Analysis] Identify splice variants and estimate relative usage using analyzeVariants()
//  * 4. [Core Analysis] Predict variant effects on protein-coding potential using predictVariantEffects()
//  * 5. [Core Analysis] Obtain single counts per variant for differential testing using getSGVariantCounts()

nextflow.enable.dsl = 2

process BIOC_SGSEQ_DE_NOVO_SPLICE_ANALYSIS {
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
    .bm_deps <- c("BSgenome", "GenomicFeatures", "GenomicRanges", "SGSeq")
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
    library(SGSeq)
    library(GenomicRanges)
    library(GenomicFeatures)
    library(BSgenome)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    
    # Read genomic region of interest (GRanges)
    if (file.exists("gr.rds")) {
      gr <- readRDS("gr.rds")
    } else {
      stop("Error: 'gr.rds' not found in the working directory.")
    }
    
    # Read TxDb annotation object
    if (file.exists("txdb.rds")) {
      txdb <- readRDS("txdb.rds")
    } else if (file.exists("txdb.sqlite")) {
      txdb <- AnnotationDbi::loadDb("txdb.sqlite")
    } else {
      stop("Error: 'txdb.rds' or 'txdb.sqlite' not found in the working directory.")
    }
    
    # Read BSgenome object for variant effect prediction
    if (file.exists("Hsapiens.rds")) {
      Hsapiens <- readRDS("Hsapiens.rds")
    } else {
      stop("Error: 'Hsapiens.rds' not found in the working directory.")
    }
    
    # Read BAM files
    if (file.exists("file_bam.rds")) {
      file_bam <- readRDS("file_bam.rds")
    } else if (file.exists("file_bam.txt")) {
      file_bam <- readLines("file_bam.txt")
    } else {
      file_bam <- list.files(pattern = "\\\\.bam\$")
      if (length(file_bam) == 0) {
        stop("Error: No BAM files found in the working directory.")
      }
    }
    
    # Construct sample information data frame
    si <- data.frame(
      sample_name = sub("\\\\.bam\$", "", basename(file_bam)),
      file_bam = file_bam,
      stringsAsFactors = FALSE
    )
    
    # Automatically retrieve BAM metadata (paired-end, read length, lib size, etc.)
    si <- getBamInfo(si)
    
    # Prepare known transcript features for annotation
    txf_ucsc <- convertToTxFeatures(txdb)
    txf_ucsc <- txf_ucsc[txf_ucsc %over% gr]
    
    # ==========================================
    # 2. Run SGSeq Workflow
    # ==========================================
    
    # Predict transcript features and count compatible fragments
    sgfc_pred <- analyzeFeatures(si, which = gr)
    
    # Annotate predicted features with known transcripts
    sgfc_pred <- annotate(sgfc_pred, txf_ucsc)
    
    # Plot predicted features and save to PDF
    pdf("plot_features.pdf", width = 8, height = 6)
    valid_geneID <- geneID(sgfc_pred)[1]
    df <- plotFeatures(sgfc_pred, geneID = valid_geneID, color_novel = "red")
    dev.off()
    
    # Identify splice variants and estimate relative usage
    sgvc_pred <- analyzeVariants(sgfc_pred)
    
    # Plot splice variants and save to PDF
    pdf("plot_variants.pdf", width = 8, height = 6)
    valid_eventID <- eventID(sgvc_pred)[1]
    plotVariants(sgvc_pred, eventID = valid_eventID, color_novel = "red")
    dev.off()
    
    # Predict variant effects on protein-coding potential
    seqlevelsStyle(Hsapiens) <- "NCBI"
    sgv_pred <- rowRanges(sgvc_pred) # Define sgv_pred for the documented call
    vep <- predictVariantEffects(sgv_pred, txdb, Hsapiens)
    
    # Obtain single counts per variant for differential testing
    sgv <- rowRanges(sgvc_pred)
    sgvc <- getSGVariantCounts(sgv, sample_info = si)
    x <- counts(sgvc)
    vid <- variantID(sgvc)
    eid <- eventID(sgvc)
    
    # ==========================================
    # 3. Save Outputs
    # ==========================================
    
    # Save RDS objects
    saveRDS(sgfc_pred, "sgfc_pred.rds")
    saveRDS(sgvc_pred, "sgvc_pred.rds")
    saveRDS(sgvc, "sgvc.rds")
    
    # Save CSV tables
    write.csv(df, "predicted_features_info.csv", row.names = FALSE)
    write.csv(as.data.frame(vep), "predicted_variant_effects.csv", row.names = FALSE)
    write.csv(as.data.frame(x), "variant_counts_matrix.csv", row.names = TRUE)
    
    # Save variant and event IDs
    ids_df <- data.frame(variantID = vid, eventID = eid, stringsAsFactors = FALSE)
    write.csv(ids_df, "variant_event_ids.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_SGSEQ_DE_NOVO_SPLICE_ANALYSIS":',
        paste0('    SGSeq: ', as.character(packageVersion('SGSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_de_novo_splice_analysis.csv versions.yml
    """
}

workflow BIOC_SGSEQ_DE_NOVO_SPLICE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ file_bam, gr, txdb, Hsapiens ] ]

    main:
    BIOC_SGSEQ_DE_NOVO_SPLICE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SGSEQ_DE_NOVO_SPLICE_ANALYSIS.out.tables
    plots    = BIOC_SGSEQ_DE_NOVO_SPLICE_ANALYSIS.out.plots
    objects  = BIOC_SGSEQ_DE_NOVO_SPLICE_ANALYSIS.out.objects
    versions = BIOC_SGSEQ_DE_NOVO_SPLICE_ANALYSIS.out.versions
}
