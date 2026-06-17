#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SGSeq — annotation_guided_splice_analysis
// Analyze and quantify splice features and variants using existing transcript annotations.
// Input: file_bam, txdb
// Container: quay.io/biocontainers/bioconductor-sgseq:1.44.0--r45hdfd78af_0
// R packages: GenomeInfoDb, GenomicFeatures, Rsamtools, knitr, SGSeq
// Bioconductor: 3.20 | R: 4.4
// Requires: AnnotationDbi, GenomeInfoDb, GenomicFeatures, Rsamtools, SGSeq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert TxDb annotation to transcript features using convertToTxFeatures()
//  * 2. [Core Analysis] Convert transcript features to splice graph features and count compatible fragments using analyzeFeatures()
//  * 3. [Visualization & Output] Plot splice graph and feature expression using plotFeatures()

nextflow.enable.dsl = 2

process BIOC_SGSEQ_ANNOTATION_GUIDED_SPLICE_ANALYSIS {
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
    .bm_deps <- c("GenomeInfoDb", "GenomicFeatures", "Rsamtools", "knitr", "SGSeq", "SummarizedExperiment")
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
    library(SummarizedExperiment)
    library(GenomeInfoDb)
    library(GenomicFeatures)
    library(Rsamtools)
    
    # ==========================================
    # 1. USER INPUT & SAMPLE INFO SETUP
    # ==========================================
    
    # Locate BAM files in the working directory
    bam_files <- list.files(pattern = "\\\\.bam\$")
    if (length(bam_files) == 0) {
      if (file.exists("file_bam")) {
        bam_files <- "file_bam"
      } else {
        stop("Error: No BAM files found in the working directory.")
      }
    }
    
    # Construct sample information data frame
    sample_info <- data.frame(
      sample_name = paste0("Sample_", seq_along(bam_files)),
      file_bam = bam_files,
      stringsAsFactors = FALSE
    )
    
    # Obtain BAM info automatically (paired-end, read length, etc.)
    si <- getBamInfo(sample_info)
    
    # Locate and load the TxDb object
    txdb <- NULL
    if (file.exists("txdb")) {
      txdb <- tryCatch({
        AnnotationDbi::loadDb("txdb")
      }, error = function(e) {
        readRDS("txdb")
      })
    } else if (file.exists("txdb.rds")) {
      txdb <- readRDS("txdb.rds")
    } else {
      # Fallback: search for any sqlite or rds file in the working directory
      txdb_files <- list.files(pattern = "\\\\.(sqlite|sqlite3|db|rds)\$")
      if (length(txdb_files) > 0) {
        txdb <- tryCatch({
          AnnotationDbi::loadDb(txdb_files[1])
        }, error = function(e) {
          readRDS(txdb_files[1])
        })
      }
    }
    
    if (is.null(txdb)) {
      stop("Error: TxDb annotation object/file not found in the working directory.")
    }
    
    # ==========================================
    # 2. EXECUTING THE DOCUMENTED WORKFLOW
    # ==========================================
    
    txf_ucsc <- convertToTxFeatures(txdb)
    
    sgfc_ucsc <- analyzeFeatures(si, features = txf_ucsc)
    
    # Save plot to PDF and capture the returned data frame
    pdf("splice_graph_features.pdf", width = 10, height = 8)
    df <- NULL
    if (length(rowRanges(sgfc_ucsc)) > 0) {
      valid_geneID <- geneID(rowRanges(sgfc_ucsc))[1]
      df <- plotFeatures(sgfc_ucsc, geneID = valid_geneID)
    }
    dev.off()
    
    # ==========================================
    # 3. WRITE OUTPUTS
    # ==========================================
    
    # Save the quantified splice features
    saveRDS(sgfc_ucsc, "sgfc_ucsc.rds")
    
    # Save the details of the plotted features
    if (!is.null(df)) {
      write.csv(df, "plot_features_details.csv", row.names = FALSE)
    }

    writeLines(c(
        '"BIOC_SGSEQ_ANNOTATION_GUIDED_SPLICE_ANALYSIS":',
        paste0('    SGSeq: ', as.character(packageVersion('SGSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_annotation_guided_splice_analysis.csv versions.yml
    """
}

workflow BIOC_SGSEQ_ANNOTATION_GUIDED_SPLICE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ file_bam, txdb ] ]

    main:
    BIOC_SGSEQ_ANNOTATION_GUIDED_SPLICE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SGSEQ_ANNOTATION_GUIDED_SPLICE_ANALYSIS.out.tables
    plots    = BIOC_SGSEQ_ANNOTATION_GUIDED_SPLICE_ANALYSIS.out.plots
    objects  = BIOC_SGSEQ_ANNOTATION_GUIDED_SPLICE_ANALYSIS.out.objects
    versions = BIOC_SGSEQ_ANNOTATION_GUIDED_SPLICE_ANALYSIS.out.versions
}
