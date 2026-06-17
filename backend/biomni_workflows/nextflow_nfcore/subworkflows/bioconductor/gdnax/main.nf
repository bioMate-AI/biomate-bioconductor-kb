#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gDNAx — diagnose_and_filter_gdna_contamination
// Diagnose genomic DNA contamination in RNA-seq BAM files and filter out reads of potential gDNA origin.
// Input: bamfiles, txdb
// Container: quay.io/biocontainers/bioconductor-gdnax:1.8.2--r45hdfd78af_0
// R packages: GenomicFeatures, gdnainrnaseqdata, gDNAx, txdb_input
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicFeatures, gDNAx
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load BAM files and TxDb annotation
//  * 2. [Core Analysis] Run diagnostics using gDNAdx()
//  * 3. [Visualization & Output] Plot diagnostics using plot(), plotFrgLength(), and plotAlnOrigins()
//  * 4. [Core Analysis] Retrieve diagnostic values using getDx(), getIgc(), and getInt()
//  * 5. [Core Analysis] Estimate and classify strandedness using strandedness() and classifyStrandMode()
//  * 6. [Core Analysis] Filter BAM files to remove gDNA contamination using gDNAtx() or filterBAMtx()

nextflow.enable.dsl = 2

process BIOC_GDNAX_DIAGNOSE_AND_FILTER_GDNA_CONTAMINATION {
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
    .bm_deps <- c("GenomicFeatures", "gdnainrnaseqdata", "gDNAx", "txdb_input")
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
    library(gDNAx)
    library(GenomicFeatures)
    
    # 1. Load BAM files and TxDb annotation from the working directory
    if (file.exists("bamfiles.txt")) {
      bamfiles <- readLines("bamfiles.txt")
      bamfiles <- bamfiles[bamfiles != ""]
    } else {
      bamfiles <- list.files(pattern = "\\\\.bam\$", full.names = TRUE)
    }
    
    if (length(bamfiles) == 0) {
      stop("Error: No BAM files found. Please provide BAM files in the working directory or list them in 'bamfiles.txt'.")
    }
    
    # Load TxDb annotation
    if (file.exists("txdb.txt")) {
      txdb_input <- trimws(readLines("txdb.txt", n = 1))
      if (suppressWarnings(require(txdb_input, character.only = TRUE, quietly = TRUE))) {
        txdb <- get(txdb_input)
      } else if (file.exists(txdb_input)) {
        if (grepl("\\\\.rds\$", txdb_input, ignore.case = TRUE)) {
          txdb <- readRDS(txdb_input)
        } else {
          txdb <- loadDb(txdb_input)
        }
      } else {
        stop("Error: Specified TxDb package or file not found: ", txdb_input)
      }
    } else if (file.exists("txdb.rds")) {
      txdb <- readRDS("txdb.rds")
    } else {
      stop("Error: TxDb annotation not found. Please provide 'txdb.txt' (containing TxDb package name or path) or 'txdb.rds' in the working directory.")
    }
    
    # Load phenodata if available, otherwise create a default one
    if (file.exists("phenodata.csv")) {
      pdat <- read.csv("phenodata.csv", row.names = 1)
      if (!"gDNA" %in% colnames(pdat)) {
        pdat\$gDNA <- "unknown"
      }
    } else {
      pdat <- data.frame(
        gDNA = rep("unknown", length(bamfiles)),
        row.names = basename(bamfiles),
        stringsAsFactors = FALSE
      )
    }
    
    # 2. Run diagnostics using gDNAdx()
    gdnax <- gDNAdx(bamfiles, txdb)
    
    # 3. Plot diagnostics using plot(), plotFrgLength(), and plotAlnOrigins()
    pdf("diagnostics_plot.pdf", width = 8, height = 12)
    par(mar=c(4, 5, 2, 1))
    plot(gdnax, group=pdat\$gDNA, pch=19)
    dev.off()
    
    pdf("fragment_length_plot.pdf", width = 8, height = 4)
    plotFrgLength(gdnax)
    dev.off()
    
    pdf("alignment_origins_plot.pdf", width = 8, height = 5)
    plotAlnOrigins(gdnax, group=pdat\$gDNA)
    dev.off()
    
    # 4. Retrieve diagnostic values using getDx(), getIgc(), and getInt()
    dx <- getDx(gdnax)
    write.csv(as.data.frame(dx), "dx_metrics.csv", row.names = TRUE)
    
    igcann <- getIgc(gdnax)
    saveRDS(igcann, "igc_annotations.rds")
    
    intann <- getInt(gdnax)
    saveRDS(intann, "int_annotations.rds")
    
    # 5. Estimate and classify strandedness using strandedness() and classifyStrandMode()
    strand_res <- strandedness(gdnax)
    write.csv(as.data.frame(strand_res), "strandedness_metrics.csv", row.names = TRUE)
    
    strand_class <- classifyStrandMode(strand_res)
    strand_class_df <- data.frame(
      Sample = names(strand_class),
      ClassifiedStrandMode = as.character(strand_class),
      stringsAsFactors = FALSE
    )
    write.csv(strand_class_df, "strand_mode_classification.csv", row.names = FALSE)
    
    # 6. Filter BAM files to remove gDNA contamination using gDNAtx()
    tmpdir <- "filtered_bams"
    if (!dir.exists(tmpdir)) {
      dir.create(tmpdir, recursive = TRUE)
    }
    fstats <- gDNAtx(gdnax, path=tmpdir)
    write.csv(as.data.frame(fstats), "filtering_stats.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_GDNAX_DIAGNOSE_AND_FILTER_GDNA_CONTAMINATION":',
        paste0('    gDNAx: ', as.character(packageVersion('gDNAx')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_diagnose_and_filter_gdna_contamination.csv versions.yml
    """
}

workflow BIOC_GDNAX_DIAGNOSE_AND_FILTER_GDNA_CONTAMINATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bamfiles, txdb ] ]

    main:
    BIOC_GDNAX_DIAGNOSE_AND_FILTER_GDNA_CONTAMINATION(ch_input)

    emit:
    tables   = BIOC_GDNAX_DIAGNOSE_AND_FILTER_GDNA_CONTAMINATION.out.tables
    plots    = BIOC_GDNAX_DIAGNOSE_AND_FILTER_GDNA_CONTAMINATION.out.plots
    objects  = BIOC_GDNAX_DIAGNOSE_AND_FILTER_GDNA_CONTAMINATION.out.objects
    versions = BIOC_GDNAX_DIAGNOSE_AND_FILTER_GDNA_CONTAMINATION.out.versions
}
