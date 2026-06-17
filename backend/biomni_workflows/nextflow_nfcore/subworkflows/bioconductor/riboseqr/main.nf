#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: riboSeqR — riboseqr_translation_analysis
// Perform a comprehensive ribosome profiling analysis including reading frame estimation, footprint filtering, visualization of average and transcript-specific tr
// Input: regions.bed, coldata.csv
// Container: 1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, baySeq, riboSeqR
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RIBOSEQR_RIBOSEQR_TRANSLATION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("riboSeqR", "GenomicRanges", "baySeq")
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
    library(riboSeqR)
    library(GenomicRanges)
    library(baySeq)
    
    # ==========================================
    # --- Load Input Data and Metadata ---
    # ==========================================
    message("Stage 1: Loading input data and metadata...")
    
    # Read and parse BED file for CDS coordinates
    if (!file.exists("regions.bed")) {
      stop("Required input file 'regions.bed' is missing.")
    }
    bed <- read.table("regions.bed", header = FALSE, sep = "\t", stringsAsFactors = FALSE)
    if (ncol(bed) < 3) {
      stop("BED file must have at least 3 columns (chrom, start, end)")
    }
    
    chroms <- bed[, 1]
    starts <- bed[, 2]
    ends <- bed[, 3]
    names_vec <- if (ncol(bed) >= 4) bed[, 4] else paste0("region_", 1:nrow(bed))
    strands <- if (ncol(bed) >= 6) bed[, 6] else "*"
    
    fastaCDS <- GRanges(seqnames = chroms,
                        ranges = IRanges(start = starts + 1, end = ends),
                        strand = strands)
    names(fastaCDS) <- names_vec
    
    # Read and parse coldata.csv
    if (!file.exists("coldata.csv")) {
      stop("Required input file 'coldata.csv' is missing.")
    }
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    if (!all(c("file", "type", "replicate") %in% colnames(coldata))) {
      stop("coldata.csv must contain 'file', 'type', and 'replicate' columns.")
    }
    
    ribofiles <- coldata\$file[coldata\$type == "ribo"]
    rnafiles <- coldata\$file[coldata\$type == "rna"]
    ribo_replicates <- coldata\$replicate[coldata\$type == "ribo"]
    
    if (length(ribofiles) == 0) {
      stop("No ribosome profiling files specified in coldata.csv")
    }
    
    # ==========================================
    # --- Read Ribosome Profiling Data ---
    # ==========================================
    message("Stage 2: Reading alignment data...")
    
    if (length(rnafiles) > 0) {
      riboDat <- readRibodata(ribofiles = ribofiles, rnafiles = rnafiles, replicates = ribo_replicates)
    } else {
      riboDat <- readRibodata(ribofiles = ribofiles, replicates = ribo_replicates)
    }
    
    # ==========================================
    # --- Frame Counting and Reading Frame Estimation ---
    # ==========================================
    message("Stage 3: Counting frames and estimating reading frames...")
    
    fCs <- frameCounting(riboDat, fastaCDS)
    fS <- readingFrame(rC = fCs)
    
    # Plot reading frames
    pdf("reading_frames.pdf")
    plotFS(fS)
    dev.off()
    
    # ==========================================
    # --- Dynamic Filtering of Footprints ---
    # ==========================================
    message("Stage 4: Filtering footprint hits...")
    
    # Dynamically identify the top 2 read lengths with the highest counts
    all_lengths <- unique(unlist(lapply(fS, function(x) colnames(x))))
    length_sums <- sapply(all_lengths, function(l) {
      sum(sapply(fS, function(x) {
        if (l %in% colnames(x)) sum(as.numeric(x[1:3, l])) else 0
      }))
    })
    
    top_lengths <- as.numeric(names(sort(length_sums, decreasing = TRUE)[1:2]))
    if (length(top_lengths) < 2) {
      top_lengths <- c(27, 28) # Fallback defaults
    }
    
    # Determine the most likely frame for each of the top lengths
    top_frames <- sapply(top_lengths, function(l) {
      frames <- sapply(fS, function(x) {
        if (as.character(l) %in% colnames(x)) {
          as.numeric(x["frame.ML", as.character(l)])
        } else {
          0
        }
      })
      as.numeric(names(sort(table(frames), decreasing = TRUE)[1]))
    })
    
    message(paste("Selected top lengths:", paste(top_lengths, collapse = ", ")))
    message(paste("Selected top frames:", paste(top_frames, collapse = ", ")))
    
    # Filter hits with fallback to relaxed thresholds if strict filtering yields no hits
    ffCs <- tryCatch({
      filterHits(fCs, lengths = top_lengths, frames = as.list(top_frames), 
                 hitMean = 10, unqhitMean = 2, fS = fS)
    }, error = function(e) {
      message("Strict filtering failed or returned no hits. Retrying with relaxed parameters...")
      filterHits(fCs, lengths = top_lengths, frames = as.list(top_frames), 
                 hitMean = 1, unqhitMean = 0, fS = fS)
    })
    
    # ==========================================
    # --- Metagene and Transcript Visualization ---
    # ==========================================
    message("Stage 5: Generating diagnostic plots...")
    
    # Plot average alignment at 5' and 3' ends of CDS
    pdf("cds_plots.pdf")
    for (len in top_lengths) {
      tryCatch({
        plotCDS(coordinates = ffCs@CDS, riboDat = riboDat, lengths = len)
      }, error = function(e) {
        message(paste("Could not plot CDS for length", len))
      })
    }
    dev.off()
    
    # Plot alignment over an individual transcript
    pdf("transcript_plot.pdf")
    if (length(ffCs@CDS) > 0) {
      tx_name <- as.character(seqnames(ffCs@CDS))[1]
      tryCatch({
        plotTranscript(tx_name, coordinates = ffCs@CDS, 
                       riboData = riboDat, length = top_lengths[1], cap = 200)
      }, error = function(e) {
        message("Could not plot transcript-specific alignment.")
      })
    }
    dev.off()
    
    # ==========================================
    # --- Count Extraction and Differential Translation ---
    # ==========================================
    message("Stage 6: Extracting counts and performing differential translation analysis...")
    
    riboCounts <- sliceCounts(ffCs, lengths = top_lengths, frames = as.list(top_frames))
    write.csv(riboCounts, "ribo_counts.csv", row.names = TRUE)
    
    if (length(rnafiles) > 0) {
      rnaCounts <- rnaCounts(riboDat, ffCs@CDS)
      write.csv(rnaCounts, "rna_counts.csv", row.names = TRUE)
      
      # Run baySeq differential translation analysis
      tryCatch({
        reps <- ffCs@replicates
        pD <- new("countData", replicates = reps, 
                  data = list(riboCounts, rnaCounts),
                  groups = list(NDT = rep(1, length(reps)), DT = reps),
                  annotation = as.data.frame(ffCs@CDS),
                  densityFunction = bbDensity)
        libsizes(pD) <- getLibsizes(pD)
        
        pD <- getPriors(pD, cl = NULL)
        pD <- getLikelihoods(pD, cl = NULL)
        
        dt_results <- topCounts(pD, "DT", normaliseData = TRUE)
        write.csv(dt_results, "differential_translation.csv", row.names = FALSE)
        message("Differential translation analysis completed successfully.")
      }, error = function(e) {
        message("baySeq analysis failed. Writing empty results table.")
        write.csv(data.frame(Warning = "baySeq analysis failed or insufficient replicates"), 
                  "differential_translation.csv", row.names = FALSE)
      })
    } else {
      message("No RNA-seq files provided. Skipping differential translation analysis.")
      write.csv(data.frame(Warning = "No RNA-seq data provided"), 
                "rna_counts.csv", row.names = FALSE)
      write.csv(data.frame(Warning = "No RNA-seq data provided for differential translation"), 
                "differential_translation.csv", row.names = FALSE)
    }
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_RIBOSEQR_RIBOSEQR_TRANSLATION_ANALYSIS":',
        paste0('    riboSeqR: ', as.character(packageVersion('riboSeqR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_riboseqr_translation_analysis.csv versions.yml
    """
}

workflow BIOC_RIBOSEQR_RIBOSEQR_TRANSLATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_RIBOSEQR_RIBOSEQR_TRANSLATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_RIBOSEQR_RIBOSEQR_TRANSLATION_ANALYSIS.out.tables
    plots    = BIOC_RIBOSEQR_RIBOSEQR_TRANSLATION_ANALYSIS.out.plots
    objects  = BIOC_RIBOSEQR_RIBOSEQR_TRANSLATION_ANALYSIS.out.objects
    versions = BIOC_RIBOSEQR_RIBOSEQR_TRANSLATION_ANALYSIS.out.versions
}
