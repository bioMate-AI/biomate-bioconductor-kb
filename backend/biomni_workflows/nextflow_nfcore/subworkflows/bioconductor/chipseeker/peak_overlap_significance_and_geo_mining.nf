#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ChIPseeker — peak_overlap_significance_and_geo_mining
// Test the statistical significance of overlap between a query peak set and target peak sets (including downloaded GEO datasets) using genomic shuffling.
// Input: files[[5]], files[1:4]
// Container: quay.io/biocontainers/bioconductor-chipseeker:1.46.1--r45hdfd78af_0
// R packages: ChIPseeker, GenomicRanges, TxDb.Hsapiens.UCSC.hg19.knownGene
// Bioconductor: 3.20 | R: 4.4
// Requires: ChIPseeker, GenomicRanges, TxDb.Hsapiens.UCSC.hg19.knownGene
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Randomly permute genomic locations of peaks using shuffle
//  * 2. [Core Analysis] Calculate overlap significance using enrichPeakOverlap
//  * 3. [Core Analysis] Query GEO database metadata using getGEOspecies, getGEOgenomeVersion, and getGEOInfo
//  * 4. [Input & Preparation] Download GEO BED files using downloadGEObedFiles or downloadGSMbedFiles

nextflow.enable.dsl = 2

process BIOC_CHIPSEEKER_PEAK_OVERLAP_SIGNIFICANCE_AND_GEO_MINING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("ChIPseeker", "GenomicRanges", "TxDb.Hsapiens.UCSC.hg19.knownGene")
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
        library(TxDb.Hsapiens.UCSC.hg19.knownGene)
        library(GenomicRanges)
        
        # Set TxDb object
        txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene
        
        # Identify and read the declared user input files from the working directory
        # The pipeline expects at least 5 BED files in the working directory.
        # files[[5]] will be the Query BED file, and files[1:4] will be the Target BED files.
        all_bed_files <- list.files(pattern = "\\\\.bed(\\\\.gz)?\$", full.names = TRUE)
        if (length(all_bed_files) < 5) {
          stop("Error: The pipeline requires at least 5 BED files in the working directory to proceed.")
        }
        
        # Construct the files list matching the user input specification
        files <- all_bed_files[1:5]
        
        # 1. Randomly permute genomic locations of peaks using shuffle
        p <- readPeakFile(files[[5]])
        shuffled_p <- shuffle(p, TxDb=txdb)
        saveRDS(shuffled_p, file = "shuffled_peaks.rds")
        
        # 2. Calculate overlap significance using enrichPeakOverlap
        overlap_results <- enrichPeakOverlap(queryPeak     = files[[5]],
                                             targetPeak    = unlist(files[1:4]),
                                             TxDb          = txdb,
                                             pAdjustMethod = "BH",
                                             nShuffle      = 50,
                                             chainFile     = NULL,
                                             verbose       = FALSE)
        
        # Save overlap results to a CSV file
        write.csv(as.data.frame(overlap_results), file = "enrich_peak_overlap_results.csv", row.names = FALSE)
        
        # 3. Query GEO database metadata
        geo_species <- getGEOspecies()
        write.csv(geo_species, file = "geo_species.csv", row.names = FALSE)
        
        geo_genomes <- getGEOgenomeVersion()
        write.csv(geo_genomes, file = "geo_genomes.csv", row.names = FALSE)
        
        hg19 <- getGEOInfo(genome="hg19", simplify=TRUE)
        write.csv(hg19, file = "geo_hg19_info.csv", row.names = FALSE)
        
        # 4. Download GEO BED files (wrapped in tryCatch to ensure pipeline robustness against network issues)
        gsm <- hg19\$gsm[sample(nrow(hg19), 10)]
        tryCatch({
          downloadGSMbedFiles(gsm, destDir="hg19")
          
          # Perform overlap significance test on downloaded GEO datasets
          geo_overlap_results <- enrichPeakOverlap(queryPeak     = files[[5]],
                                                   targetPeak    = "hg19",
                                                   TxDb          = txdb,
                                                   pAdjustMethod = "BH",
                                                   nShuffle      = 50,
                                                   chainFile     = NULL,
                                                   verbose       = FALSE)
          
          # Save GEO overlap results to a CSV file
          write.csv(as.data.frame(geo_overlap_results), file = "geo_enrich_peak_overlap_results.csv", row.names = FALSE)
        }, error = function(e) {
          message("Warning: downloadGSMbedFiles or GEO overlap failed or timed out. Proceeding...")
        })

    writeLines(c(
        '"BIOC_CHIPSEEKER_PEAK_OVERLAP_SIGNIFICANCE_AND_GEO_MINING":',
        paste0('    ChIPseeker: ', as.character(packageVersion('ChIPseeker')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_peak_overlap_significance_and_geo_mining.csv versions.yml
    """
}

workflow BIOC_CHIPSEEKER_PEAK_OVERLAP_SIGNIFICANCE_AND_GEO_MINING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ files[[5]], files[1:4] ] ]

    main:
    BIOC_CHIPSEEKER_PEAK_OVERLAP_SIGNIFICANCE_AND_GEO_MINING(ch_input)

    emit:
    tables   = BIOC_CHIPSEEKER_PEAK_OVERLAP_SIGNIFICANCE_AND_GEO_MINING.out.tables
    plots    = BIOC_CHIPSEEKER_PEAK_OVERLAP_SIGNIFICANCE_AND_GEO_MINING.out.plots
    objects  = BIOC_CHIPSEEKER_PEAK_OVERLAP_SIGNIFICANCE_AND_GEO_MINING.out.objects
    versions = BIOC_CHIPSEEKER_PEAK_OVERLAP_SIGNIFICANCE_AND_GEO_MINING.out.versions
}
