#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Guitar — custom_guitar_coordinates_and_sampling
// Build reusable genome-projected transcriptomic landmark coordinates (Guitar coordinates) and sample points from genomic features.
// Input: stBedFiles, txdb_file
// Container: quay.io/biocontainers/bioconductor-guitar:2.26.0--r45hdfd78af_0
// R packages: GenomicFeatures, Guitar, rtracklayer
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicFeatures, Guitar, rtracklayer
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the TxDb annotation database
//  * 2. [Input & Preparation] Build a reusable guitarTxdb object using makeGuitarTxdb
//  * 3. [Input & Preparation] Import BED files as GRangesList
//  * 4. [Core Analysis] Sample points along the features using samplePoints

nextflow.enable.dsl = 2

process BIOC_GUITAR_CUSTOM_GUITAR_COORDINATES_AND_SAMPLING {
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
    .bm_deps <- c("GenomicFeatures", "Guitar", "rtracklayer")
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
    library(Guitar)
    library(GenomicFeatures)
    library(rtracklayer)
    
    # Define input files from the working directory
    txdb_file <- "txdb_file.sqlite"
    stBedFiles <- list("stBedFiles_1.bed", "stBedFiles_2.bed")
    
    # Check for existence of input files
    if (!file.exists(txdb_file)) {
      stop("Required input file 'txdb_file.sqlite' not found in the working directory.")
    }
    for (f in stBedFiles) {
      if (!file.exists(f)) {
        stop(paste("Required input file", f, "not found in the working directory."))
      }
    }
    
    # 1. Load the TxDb annotation database
    txdb <- loadDb(txdb_file)
    
    # 2. Build a reusable guitarTxdb object using makeGuitarTxdb
    guitarTxdb <- makeGuitarTxdb(txdb = txdb,
                                 txAmblguity = 5,
                                 txMrnaComponentProp = c(0.1,0.15,0.6,0.05,0.1),
                                 txLncrnaComponentProp = c(0.2,0.6,0.2),
                                 pltTxType = c("tx","mrna","ncrna"),
                                 txPrimaryOnly = FALSE)
    
    # 3. Import BED files as GRangesList
    stGRangeLists = vector("list", length(stBedFiles))
    sitesPoints <- list()
    for (i in seq_len(length(stBedFiles))) {
      stGRangeLists[[i]] <-  blocks(import(stBedFiles[[i]]))
    }
    
    # 4. Sample points along the features using samplePoints
    for (i in seq_len(length(stGRangeLists))) {
      sitesPoints[[i]] <- samplePoints(stGRangeLists[i], 
                                  stSampleNum = 10,
                                  stAmblguity = 5,
                                  pltTxType =  c("mrna"), 
                                  stSampleModle = "Equidistance", 
                                  mapFilterTranscript = FALSE,
                                  guitarTxdb = guitarTxdb)
    }
    
    # Save outputs
    saveRDS(guitarTxdb, file = "guitarTxdb.rds")
    saveRDS(stGRangeLists, file = "stGRangeLists.rds")
    saveRDS(sitesPoints, file = "sitesPoints.rds")

    writeLines(c(
        '"BIOC_GUITAR_CUSTOM_GUITAR_COORDINATES_AND_SAMPLING":',
        paste0('    Guitar: ', as.character(packageVersion('Guitar')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_guitar_coordinates_and_sampling.csv versions.yml
    """
}

workflow BIOC_GUITAR_CUSTOM_GUITAR_COORDINATES_AND_SAMPLING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ stBedFiles, txdb_file ] ]

    main:
    BIOC_GUITAR_CUSTOM_GUITAR_COORDINATES_AND_SAMPLING(ch_input)

    emit:
    tables   = BIOC_GUITAR_CUSTOM_GUITAR_COORDINATES_AND_SAMPLING.out.tables
    plots    = BIOC_GUITAR_CUSTOM_GUITAR_COORDINATES_AND_SAMPLING.out.plots
    objects  = BIOC_GUITAR_CUSTOM_GUITAR_COORDINATES_AND_SAMPLING.out.objects
    versions = BIOC_GUITAR_CUSTOM_GUITAR_COORDINATES_AND_SAMPLING.out.versions
}
