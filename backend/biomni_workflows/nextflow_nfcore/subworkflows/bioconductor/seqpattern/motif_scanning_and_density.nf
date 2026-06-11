#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: seqPattern — motif_scanning_and_density
// Scan genomic sequences with a Position Weight Matrix (PWM) to visualize motif density, scanning scores, and average occurrence profiles.
// Input: coordinates.txt, genome_assembly, pwm_matrix.RData
// Container: quay.io/biocontainers/bioconductor-seqpattern:1.42.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome, Biostrings, GenomicRanges, seqPattern
// Visualizations: density plot, heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create GRanges of reference positions with associated metadata
//  * 2. [Input & Preparation] Define flanking regions of equal width using promoters()
//  * 3. [Core Analysis] Extract genomic sequences using getSeq()
//  * 4. [Visualization & Output] Plot motif density maps above a threshold using plotMotifDensityMap()
//  * 5. [Visualization & Output] Plot a heatmap of PWM scanning scores along sequences using plotMotifScanScores()
//  * 6. [Visualization & Output] Plot average motif occurrence profiles using plotMotifOccurrenceAverage()
//  * 7. [Core Analysis] Retrieve raw motif hits using motifScanHits() or scanning scores using motifScanScores()

nextflow.enable.dsl = 2

process BIOC_SEQPATTERN_MOTIF_SCANNING_AND_DENSITY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    
    # -----------------------------------------------------------------------------
    # 1. Read User Input Files
    # -----------------------------------------------------------------------------
    
    # Read genomic coordinates and associated features
    coords <- read.delim("coordinates.txt", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
    
    # Read the BSgenome package name and load it
    genome_package <- trimws(readLines("genome_assembly", n = 1))
    library(genome_package, character.only = TRUE)
    genome_obj <- getBSgenome(genome_package)
    
    # Load the Position Weight Matrix (PWM)
    env <- new.env()
    load("pwm_matrix.RData", envir = env)
    # Identify the PWM object from the loaded environment
    pwm_name <- ls(env)[1]
    for (name in ls(env)) {
      if (is.matrix(env[[name]]) || is.array(env[[name]])) {
        pwm_name <- name
        break
      }
    }
    TBPpwm <- env[[pwm_name]]
    
    # -----------------------------------------------------------------------------
    # 2. Create GRanges of reference positions with associated metadata
    # -----------------------------------------------------------------------------
    # Extract columns by name if present, otherwise assume standard order (chr, start, end, strand, feature)
    chr_vals <- if ("chr" %in% colnames(coords)) coords\$chr else coords[, 1]
    start_vals <- if ("start" %in% colnames(coords)) coords\$start else coords[, 2]
    end_vals <- if ("end" %in% colnames(coords)) coords\$end else coords[, 3]
    strand_vals <- if ("strand" %in% colnames(coords)) coords\$strand else coords[, 4]
    feature_vals <- if ("feature" %in% colnames(coords)) coords\$feature else coords[, 5]
    
    zebrafishPromotersTSS <- GRanges(seqnames = chr_vals,
                ranges = IRanges(start = start_vals, 
                end = end_vals), 
                strand = strand_vals, 
                feature = feature_vals, 
                seqlengths = seqlengths(genome_obj))
    
    # -----------------------------------------------------------------------------
    # 3. Define flanking regions of equal width using promoters()
    # -----------------------------------------------------------------------------
    zebrafishPromotersTSSflank <- promoters(zebrafishPromotersTSS, upstream = 200, 
                                            downstream = 200)
    
    # Trim and filter to ensure all ranges are within chromosome boundaries and have equal width (400 bp)
    zebrafishPromotersTSSflank <- trim(zebrafishPromotersTSSflank)
    zebrafishPromotersTSSflank <- zebrafishPromotersTSSflank[width(zebrafishPromotersTSSflank) == 400]
    
    # -----------------------------------------------------------------------------
    # 4. Extract genomic sequences using getSeq()
    # -----------------------------------------------------------------------------
    zebrafishPromotersTSSflankSeq <- getSeq(genome_obj, zebrafishPromotersTSSflank)
    
    # -----------------------------------------------------------------------------
    # 5. Plot motif density maps above a threshold using plotMotifDensityMap()
    # -----------------------------------------------------------------------------
    plotMotifDensityMap(regionsSeq = zebrafishPromotersTSSflankSeq, 
                motifPWM = TBPpwm, minScore = "90%", 
                seqOrder = order(zebrafishPromotersTSSflank\$feature),
                flankUp = 200, flankDown = 200, color = "red",
                outFile = "motif_density_map.png")
    
    # -----------------------------------------------------------------------------
    # 6. Plot a heatmap of PWM scanning scores along sequences using plotMotifScanScores()
    # -----------------------------------------------------------------------------
    plotMotifScanScores(regionsSeq = zebrafishPromotersTSSflankSeq, 
                motifPWM = TBPpwm,
                seqOrder = order(zebrafishPromotersTSSflank\$feature),
                flankUp = 200, flankDown = 200,
                outFile = "motif_scan_scores_heatmap.png")
    
    # -----------------------------------------------------------------------------
    # 7. Plot average motif occurrence profiles using plotMotifOccurrenceAverage()
    # -----------------------------------------------------------------------------
    pdf("motif_occurrence_average.pdf", width = 8, height = 6)
    
    # Generalize the threshold for splitting sequences by using the median of the feature
    feature_median <- median(zebrafishPromotersTSSflank\$feature, na.rm = TRUE)
    sIdx <- zebrafishPromotersTSSflank\$feature <= feature_median
    bIdx <- zebrafishPromotersTSSflank\$feature > feature_median
    
    # Plot average motif occurrence profile for sharp promoters
    plotMotifOccurrenceAverage(regionsSeq = zebrafishPromotersTSSflankSeq[sIdx], 
                motifPWM = TBPpwm, minScore = "90%", flankUp = 200, flankDown = 200, 
                smoothingWindow = 3, color = c("red3"), cex.axis = 0.9)
    
    # Add average motif occurrence profile for broad promoters to the existing plot
    plotMotifOccurrenceAverage(regionsSeq = zebrafishPromotersTSSflankSeq[bIdx], 
                motifPWM = TBPpwm, minScore = "90%", flankUp = 200, flankDown = 200, 
                smoothingWindow = 3, color = c("blue3"), add = TRUE)
    
    legend("topright", legend = c("sharp", "broad"), col = c("red3", "blue3"), 
    bty = "n", lwd = 1)
    dev.off()
    
    # -----------------------------------------------------------------------------
    # 8. Retrieve raw motif hits and scanning scores
    # -----------------------------------------------------------------------------
    # Determine safe subset limit based on available sequences
    n_seqs <- min(50, length(zebrafishPromotersTSSflankSeq))
    
    motifOccurrence <- motifScanHits(regionsSeq = 
                zebrafishPromotersTSSflankSeq[1:n_seqs], 
                motifPWM = TBPpwm, minScore = "90%", seqOrder = 
                order(zebrafishPromotersTSSflank\$feature[1:n_seqs]))
    
    scanScores <- motifScanScores(regionsSeq = zebrafishPromotersTSSflankSeq[1:n_seqs], 
                motifPWM = TBPpwm, seqOrder = 
                order(zebrafishPromotersTSSflank\$feature[1:n_seqs]))
    
    # Save tabular outputs
    write.csv(as.data.frame(motifOccurrence), "motif_occurrence_hits.csv", row.names = FALSE)
    write.csv(as.data.frame(scanScores), "motif_scan_scores.csv", row.names = TRUE)
    
    # Save RDS objects for downstream analysis
    saveRDS(motifOccurrence, "motif_occurrence_hits.rds")
    saveRDS(scanScores, "motif_scan_scores.rds")

    writeLines(c(
        '"BIOC_SEQPATTERN_MOTIF_SCANNING_AND_DENSITY":',
        paste0('    seqPattern: ', as.character(packageVersion('seqPattern')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_motif_scanning_and_density.csv versions.yml
    """
}

workflow BIOC_SEQPATTERN_MOTIF_SCANNING_AND_DENSITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ coordinates.txt, genome_assembly, pwm_matrix.RData ] ]

    main:
    BIOC_SEQPATTERN_MOTIF_SCANNING_AND_DENSITY(ch_input)

    emit:
    tables   = BIOC_SEQPATTERN_MOTIF_SCANNING_AND_DENSITY.out.tables
    plots    = BIOC_SEQPATTERN_MOTIF_SCANNING_AND_DENSITY.out.plots
    objects  = BIOC_SEQPATTERN_MOTIF_SCANNING_AND_DENSITY.out.objects
    versions = BIOC_SEQPATTERN_MOTIF_SCANNING_AND_DENSITY.out.versions
}
