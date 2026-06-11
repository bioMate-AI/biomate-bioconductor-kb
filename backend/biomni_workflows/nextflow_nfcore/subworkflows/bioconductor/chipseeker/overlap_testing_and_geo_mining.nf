#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chipseeker — overlap_testing_and_geo_mining
// Test the statistical significance of overlap between ChIP-seq datasets and mine public GEO datasets for co-regulation.
// Input: files[[5]], files[1:4], txdb
// Container: quay.io/biocontainers/bioconductor-chipseeker:1.46.1--r45hdfd78af_0
// R packages: ChIPseeker, GenomicRanges
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHIPSEEKER_OVERLAP_TESTING_AND_GEO_MINING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-chipseeker:1.46.1--r45hdfd78af_0"

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
    .bm_deps <- c("ChIPseeker", "GenomicRanges")
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
    library(ChIPseeker)
    library(GenomicRanges)
    
    # Read user inputs from the working directory
    # The pipeline expects 'file1.bed', 'file2.bed', 'file3.bed', 'file4.bed', 'file5.bed'
    # and 'txdb.rds' to be present in the working directory.
    files <- c(
      "file1.bed",
      "file2.bed",
      "file3.bed",
      "file4.bed",
      "file5.bed"
    )
    
    txdb <- readRDS("txdb.rds")
    
    # Stage 1: Shuffle genomic coordinates using shuffle
    p <- GRanges(seqnames=c("chr1", "chr3"), ranges=IRanges(start=c(1, 100), end=c(50, 130)))
    shuffled_p <- shuffle(p, TxDb=txdb)
    saveRDS(shuffled_p, "shuffled_peaks.rds")
    
    # Stage 2: Test overlap significance using enrichPeakOverlap
    overlap_results <- enrichPeakOverlap(
      queryPeak     = files[[5]], 
      targetPeak    = unlist(files[1:4]), 
      TxDb          = txdb, 
      pAdjustMethod = "BH", 
      nShuffle      = 50, 
      chainFile     = NULL, 
      verbose       = FALSE
    )
    write.csv(overlap_results, "enrich_peak_overlap_results.csv", row.names = FALSE)
    
    # Stage 3: Query GEO species and genomes using getGEOspecies and getGEOgenomeVersion
    geo_species <- getGEOspecies()
    write.csv(geo_species, "geo_species.csv", row.names = FALSE)
    
    geo_genomes <- getGEOgenomeVersion()
    write.csv(geo_genomes, "geo_genomes.csv", row.names = FALSE)
    
    # Stage 4: Retrieve GEO metadata using getGEOInfo
    hg19 <- getGEOInfo(genome="hg19", simplify=TRUE)
    print(head(hg19))
    write.csv(hg19, "geo_hg19_info.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_CHIPSEEKER_OVERLAP_TESTING_AND_GEO_MINING":',
        paste0('        chipseeker: ', as.character(packageVersion("chipseeker")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_overlap_testing_and_geo_mining.csv versions.yml
    """
}

workflow BIOC_CHIPSEEKER_OVERLAP_TESTING_AND_GEO_MINING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ files[[5]], files[1:4], txdb ] ]

    main:
    BIOC_CHIPSEEKER_OVERLAP_TESTING_AND_GEO_MINING(ch_input)

    emit:
    tables   = BIOC_CHIPSEEKER_OVERLAP_TESTING_AND_GEO_MINING.out.tables
    plots    = BIOC_CHIPSEEKER_OVERLAP_TESTING_AND_GEO_MINING.out.plots
    objects  = BIOC_CHIPSEEKER_OVERLAP_TESTING_AND_GEO_MINING.out.objects
    versions = BIOC_CHIPSEEKER_OVERLAP_TESTING_AND_GEO_MINING.out.versions
}
