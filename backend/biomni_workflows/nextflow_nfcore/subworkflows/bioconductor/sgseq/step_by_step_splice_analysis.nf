#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SGSeq — step_by_step_splice_analysis
// Perform de novo splice feature prediction, quantification, and variant identification using individual step-by-step functions for advanced control.
// Input: file_bam, gr, txf_ucsc
// Container: quay.io/biocontainers/bioconductor-sgseq:1.44.0--r45hdfd78af_0
// R packages: GenomicRanges, SGSeq
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, SGSeq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Predict transcript features using predictTxFeatures()
//  * 2. [Core Analysis] Convert predicted transcript features to splice graph features using convertToSGFeatures()
//  * 3. [Core Analysis] Annotate splice graph features using annotate()
//  * 4. [Core Analysis] Get compatible fragment counts for splice graph features using getSGFeatureCounts()
//  * 5. [Core Analysis] Find splice variants from splice graph features using findSGVariants()
//  * 6. [Core Analysis] Get variant counts and relative frequencies using getSGVariantCounts()

nextflow.enable.dsl = 2

process BIOC_SGSEQ_STEP_BY_STEP_SPLICE_ANALYSIS {
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
    .bm_deps <- c("GenomicRanges", "SGSeq")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
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
    library(SGSeq)
    library(GenomicRanges)
    
    # 1. Read User Input Files from the Working Directory
    # Read GRanges object of genomic region of interest
    if (file.exists("gr.rds")) {
      gr <- readRDS("gr.rds")
    } else {
      stop("Required input file 'gr.rds' not found in the working directory.")
    }
    
    # Read TxFeatures object from annotation
    if (file.exists("txf_ucsc.rds")) {
      txf_ucsc <- readRDS("txf_ucsc.rds")
    } else {
      stop("Required input file 'txf_ucsc.rds' not found in the working directory.")
    }
    
    # Identify BAM file
    bam_file <- "file_bam"
    if (!file.exists(bam_file)) {
      if (file.exists("file_bam.bam")) {
        bam_file <- "file_bam.bam"
      } else {
        stop("Required BAM file 'file_bam' or 'file_bam.bam' not found in the working directory.")
      }
    }
    
    # Construct sample information data frame
    si <- data.frame(
      sample_name = "sample_1",
      file_bam = bam_file,
      stringsAsFactors = FALSE
    )
    
    # Obtain BAM info automatically (extracts paired_end, read_length, frag_length, lib_size)
    si <- getBamInfo(si)
    
    # 2. Step-by-Step Splice Analysis Workflow (Faithful to Documented Code)
    # Step 1: Predict transcript features
    txf <- predictTxFeatures(si, gr)
    
    # Step 2: Convert predicted transcript features to splice graph features
    sgf <- convertToSGFeatures(txf)
    
    # Step 3: Annotate splice graph features
    sgf <- annotate(sgf, txf_ucsc)
    
    # Step 4: Get compatible fragment counts for splice graph features
    sgfc <- getSGFeatureCounts(si, sgf)
    
    # Step 5: Find splice variants from splice graph features
    sgv <- findSGVariants(sgf)
    
    # Step 6: Get variant counts and relative frequencies
    sgvc <- getSGVariantCounts(sgv, sgfc)
    
    # 3. Save Outputs to Working Directory
    # Save RDS objects for downstream analysis
    saveRDS(txf, "predicted_tx_features.rds")
    saveRDS(sgf, "splice_graph_features.rds")
    saveRDS(sgfc, "sg_feature_counts.rds")
    saveRDS(sgv, "sg_variants.rds")
    saveRDS(sgvc, "sg_variant_counts.rds")
    
    # Save CSV tables of counts and frequencies
    tryCatch({
      write.csv(as.data.frame(counts(sgfc)), "sg_feature_counts.csv", row.names = TRUE)
    }, error = function(e) {
      warning("Could not write feature counts CSV: ", e\$message)
    })
    
    tryCatch({
      write.csv(as.data.frame(variantFreq(sgvc)), "sg_variant_frequencies.csv", row.names = TRUE)
    }, error = function(e) {
      warning("Could not write variant frequencies CSV: ", e\$message)
    })
    
    # Generate Diagnostic Plots
    pdf("splice_graph_plots.pdf", width = 8, height = 6)
    tryCatch({
      g_ids <- unique(geneID(sgf))
      if (length(g_ids) > 0) {
        plotFeatures(sgfc, geneID = g_ids[1])
      }
    }, error = function(e) {
      message("Could not plot features: ", e\$message)
    })
    
    tryCatch({
      if (exists("sgvc") && nrow(sgvc) > 0) {
        e_ids <- unique(eventID(sgvc))
        if (length(e_ids) > 0) {
          plotVariants(sgvc, eventID = e_ids[1])
        }
      }
    }, error = function(e) {
      message("Could not plot variants: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_SGSEQ_STEP_BY_STEP_SPLICE_ANALYSIS":',
        paste0('    SGSeq: ', as.character(packageVersion('SGSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_step_by_step_splice_analysis.csv versions.yml
    """
}

workflow BIOC_SGSEQ_STEP_BY_STEP_SPLICE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ file_bam, gr, txf_ucsc ] ]

    main:
    BIOC_SGSEQ_STEP_BY_STEP_SPLICE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SGSEQ_STEP_BY_STEP_SPLICE_ANALYSIS.out.tables
    plots    = BIOC_SGSEQ_STEP_BY_STEP_SPLICE_ANALYSIS.out.plots
    objects  = BIOC_SGSEQ_STEP_BY_STEP_SPLICE_ANALYSIS.out.objects
    versions = BIOC_SGSEQ_STEP_BY_STEP_SPLICE_ANALYSIS.out.versions
}
