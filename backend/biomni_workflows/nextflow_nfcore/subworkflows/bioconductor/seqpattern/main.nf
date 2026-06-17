#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: seqPattern — oligonucleotide_and_consensus_density
// Extract genomic sequences around a reference point, sort them by a feature, and visualize oligonucleotide or consensus sequence densities and average profiles.
// Input: coordinates.txt, genome_assembly
// Container: quay.io/biocontainers/bioconductor-seqpattern:1.42.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome, Biostrings, GenomicRanges, seqPattern
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create GRanges of reference positions with associated metadata
//  * 2. [Input & Preparation] Define flanking regions of equal width using promoters()
//  * 3. [Core Analysis] Extract genomic sequences using getSeq()
//  * 4. [Visualization & Output] Plot dinucleotide or consensus density maps using plotPatternDensityMap()
//  * 5. [Visualization & Output] Plot average oligonucleotide profiles using plotPatternOccurrenceAverage()

nextflow.enable.dsl = 2

process BIOC_SEQPATTERN_OLIGONUCLEOTIDE_AND_CONSENSUS_DENSITY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("seqPattern", "GenomicRanges", "Biostrings", "BSgenome", "genome_package")
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
    library(seqPattern)
    library(GenomicRanges)
    library(Biostrings)
    library(BSgenome)
    
    # Read user inputs
    genome_package <- readLines("genome_assembly", n = 1, warn = FALSE)
    genome_package <- trimws(genome_package)
    
    # Load the specified BSgenome package and assign it to genome_obj
    library(genome_package, character.only = TRUE)
    genome_obj <- getBSgenome(genome_package)
    
    # Read coordinates and associated features
    zebrafishPromoters24h <- read.table("coordinates.txt", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
    
    # 1. Create GRanges of reference positions with associated metadata
    zebrafishPromotersTSS <- GRanges(seqnames = zebrafishPromoters24h\$chr,
                ranges = IRanges(start = zebrafishPromoters24h\$dominantTSS, 
                end = zebrafishPromoters24h\$dominantTSS), 
                strand = zebrafishPromoters24h\$strand, 
                interquantileWidth = zebrafishPromoters24h\$interquantileWidth, 
                seqlengths = seqlengths(genome_obj))
    
    # 2. Define flanking regions of equal width using promoters()
    zebrafishPromotersTSSflank <- promoters(zebrafishPromotersTSS, upstream = 400, 
                                            downstream = 800)
    
    # Trim and filter out-of-bound ranges to ensure equal sequence lengths
    zebrafishPromotersTSSflank <- trim(zebrafishPromotersTSSflank)
    keep1 <- width(zebrafishPromotersTSSflank) == 1200
    zebrafishPromotersTSSflank <- zebrafishPromotersTSSflank[keep1]
    
    # 3. Extract genomic sequences using getSeq()
    zebrafishPromotersTSSflankSeq <- getSeq(genome_obj, zebrafishPromotersTSSflank)
    
    # Save intermediate RDS
    saveRDS(zebrafishPromotersTSSflank, "processed_TSS_flank_400_800.rds")
    saveRDS(zebrafishPromotersTSSflankSeq, "processed_TSS_flankSeq_400_800.rds")
    
    # 4. Plot dinucleotide or consensus density maps using plotPatternDensityMap()
    # Run multicore plotting inside tryCatch to handle non-Unix environments gracefully
    tryCatch({
      plotPatternDensityMap(regionsSeq = zebrafishPromotersTSSflankSeq, 
                  patterns = c("AA", "TA", "CG", "GC"), 
                  seqOrder = order(zebrafishPromotersTSSflank\$interquantileWidth),
                  flankUp = 400, flankDown = 800, color = "blue", useMulticore = TRUE, nrCores = 4)
    }, error = function(e) {
      warning("Multicore plotting failed or is unsupported on this platform. Falling back to single-core.")
      plotPatternDensityMap(regionsSeq = zebrafishPromotersTSSflankSeq, 
                  patterns = c("AA", "TA", "CG", "GC"), 
                  seqOrder = order(zebrafishPromotersTSSflank\$interquantileWidth), 
                  flankUp = 400, flankDown = 800, color = "blue")
    })
    
    plotPatternDensityMap(regionsSeq = zebrafishPromotersTSSflankSeq, 
                patterns = c("WW", "SS"), 
                seqOrder = order(zebrafishPromotersTSSflank\$interquantileWidth), 
                flankUp = 400, flankDown = 800, color = "cyan", labelCol = "white")
    
    # 5. Plot average oligonucleotide profiles using plotPatternOccurrenceAverage()
    sIdx <- zebrafishPromotersTSSflank\$interquantileWidth <= 9
    bIdx <- zebrafishPromotersTSSflank\$interquantileWidth > 9
    
    pdf("average_oligonucleotide_profiles.pdf", width = 10, height = 5)
    par(mfrow = c(1,2), mar = c(4.5,4,1,1))
    plotPatternOccurrenceAverage(regionsSeq = zebrafishPromotersTSSflankSeq[sIdx], 
                patterns = c("WW", "SS"), flankUp = 400, flankDown = 800, 
                smoothingWindow = 3, color = c("red3", "blue3"), cex.axis = 0.9)
    plotPatternOccurrenceAverage(regionsSeq = zebrafishPromotersTSSflankSeq[bIdx], 
                patterns = c("WW", "SS"), flankUp = 400, flankDown = 800, 
                smoothingWindow = 3, color = c("red3", "blue3"), cex.axis = 0.9)
    dev.off()
    
    # Define narrower flanking regions (200 bp upstream and downstream)
    zebrafishPromotersTSSflank <- promoters(zebrafishPromotersTSS, upstream = 200, 
                                            downstream = 200)
    
    # Trim and filter out-of-bound ranges
    zebrafishPromotersTSSflank <- trim(zebrafishPromotersTSSflank)
    keep2 <- width(zebrafishPromotersTSSflank) == 400
    zebrafishPromotersTSSflank <- zebrafishPromotersTSSflank[keep2]
    
    # Extract genomic sequences for narrower flanking regions
    zebrafishPromotersTSSflankSeq <- getSeq(genome_obj, zebrafishPromotersTSSflank)
    
    # Save intermediate RDS
    saveRDS(zebrafishPromotersTSSflank, "processed_TSS_flank_200_200.rds")
    saveRDS(zebrafishPromotersTSSflankSeq, "processed_TSS_flankSeq_200_200.rds")
    
    # Plot consensus sequence density maps
    plotPatternDensityMap(regionsSeq = zebrafishPromotersTSSflankSeq, 
                patterns = c("TATAWAWR", "YWTWTATA"), 
                seqOrder = order(zebrafishPromotersTSSflank\$interquantileWidth), 
                flankUp = 200, flankDown = 200, 
                bandWidth = c(1,6), color = "pink", addPatternLabel = FALSE)
    
    plotPatternDensityMap(regionsSeq = zebrafishPromotersTSSflankSeq, 
                patterns = c("RGGMGGR", "YCCKCCY"), 
                seqOrder = order(zebrafishPromotersTSSflank\$interquantileWidth), 
                flankUp = 200, flankDown = 200, 
                bandWidth = c(1,6), color = "purple", addPatternLabel = FALSE)

    writeLines(c(
        '"BIOC_SEQPATTERN_OLIGONUCLEOTIDE_AND_CONSENSUS_DENSITY":',
        paste0('    seqPattern: ', as.character(packageVersion('seqPattern')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_oligonucleotide_and_consensus_density.csv versions.yml
    """
}

workflow BIOC_SEQPATTERN_OLIGONUCLEOTIDE_AND_CONSENSUS_DENSITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ coordinates.txt, genome_assembly ] ]

    main:
    BIOC_SEQPATTERN_OLIGONUCLEOTIDE_AND_CONSENSUS_DENSITY(ch_input)

    emit:
    tables   = BIOC_SEQPATTERN_OLIGONUCLEOTIDE_AND_CONSENSUS_DENSITY.out.tables
    plots    = BIOC_SEQPATTERN_OLIGONUCLEOTIDE_AND_CONSENSUS_DENSITY.out.plots
    objects  = BIOC_SEQPATTERN_OLIGONUCLEOTIDE_AND_CONSENSUS_DENSITY.out.objects
    versions = BIOC_SEQPATTERN_OLIGONUCLEOTIDE_AND_CONSENSUS_DENSITY.out.versions
}
