#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: derfinder — single_base_level_f_statistics
// Perform base-level differential expression analysis by calculating F-statistics for every base, defining candidate DERs, and assigning empirical p-values via pe
// Input: files, brainspanPheno
// Container: quay.io/biocontainers/bioconductor-derfinder:1.44.0--r45hdfd78af_0
// R packages: GenomicFeatures, GenomicRanges, Rsamtools, TxDb.Hsapiens.UCSC.hg19.knownGene, derfinder, rtracklayer, txdb_pkgs
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicFeatures, GenomicRanges, Rsamtools, TxDb.Hsapiens.UCSC.hg19.knownGene, derfinder, rtracklayer
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Locate raw coverage files using rawFiles()
//  * 2. [Input & Preparation] Load coverage data into memory using fullCoverage()
//  * 3. [Core Analysis] Filter coverage using filterData()
//  * 4. [Core Analysis] Calculate sample depth adjustments using collapseFullCoverage() and sampleDepth()
//  * 5. [Input & Preparation] Define nested alternative and null models using makeModels()
//  * 6. [Core Analysis] Perform base-level F-statistics analysis per chromosome using analyzeChr() (set smooth = TRUE for ChIP-seq peak finding)
//  * 7. [Core Analysis] Merge results across chromosomes using mergeResults()

nextflow.enable.dsl = 2

process BIOC_DERFINDER_SINGLE_BASE_LEVEL_F_STATISTICS {
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
    .bm_deps <- c("GenomicFeatures", "GenomicRanges", "Rsamtools", "TxDb.Hsapiens.UCSC.hg19.knownGene", "derfinder", "rtracklayer", "txdb_pkgs")
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
    library(derfinder)
    library(GenomicRanges)
    library(GenomicFeatures)
    
    # ==========================================
    # STAGE 1: Locate raw coverage files using rawFiles()
    # ==========================================
    
    # Detect if BigWig or BAM files are present in the working directory
    has_bw <- length(list.files(pattern = "\\\\.bw\$|\\\\.bigWig\$", ignore.case = TRUE)) > 0
    patt <- if (has_bw) "bw" else "bam"
    
    files <- rawFiles(".", samplepatt = patt, fileterm = NULL)
    if (length(files) == 0) {
        stop("No BAM or BigWig files found in the working directory.")
    }
    names(files) <- gsub(paste0(".", patt), "", names(files))
    
    # ==========================================
    # STAGE 2: Load coverage data into memory using fullCoverage()
    # ==========================================
    
    # Dynamically detect the first chromosome name from the input files
    chrs <- "chr21" # default fallback
    first_file <- files[1]
    if (grepl("\\\\.bw\$|\\\\.bigwig\$", first_file, ignore.case = TRUE)) {
        if (requireNamespace("rtracklayer", quietly = TRUE)) {
            library(rtracklayer)
            bw <- BigWigFile(first_file)
            chrs <- seqnames(seqinfo(bw))[1]
        }
    } else if (grepl("\\\\.bam\$", first_file, ignore.case = TRUE)) {
        if (requireNamespace("Rsamtools", quietly = TRUE)) {
            library(Rsamtools)
            hdr <- scanBamHeader(first_file)
            chrs <- names(hdr[[1]]\$targets)[1]
        }
    }
    
    fullCov <- fullCoverage(
        files = files,
        chrs = chrs,
        totalMapped = rep(1, length(files)),
        targetSize = 1
    )
    
    # ==========================================
    # STAGE 3: Filter coverage using filterData()
    # ==========================================
    
    filteredCov <- lapply(fullCov, filterData, cutoff = 2)
    
    # ==========================================
    # STAGE 4: Calculate sample depth adjustments using collapseFullCoverage() and sampleDepth()
    # ==========================================
    
    collapsedCov <- collapseFullCoverage(fullCov)
    sampleDepths <- sampleDepth(collapsedCov, 1)
    
    # ==========================================
    # STAGE 5: Define nested alternative and null models using makeModels()
    # ==========================================
    
    # Read phenotype table from the working directory
    if (file.exists("brainspanPheno.csv")) {
        pheno <- read.csv("brainspanPheno.csv", stringsAsFactors = FALSE)
    } else if (file.exists("brainspanPheno.rds")) {
        pheno <- readRDS("brainspanPheno.rds")
    } else if (file.exists("brainspanPheno.tsv")) {
        pheno <- read.delim("brainspanPheno.tsv", stringsAsFactors = FALSE)
    } else {
        stop("Phenotype file (brainspanPheno.csv/tsv/rds) not found in the working directory.")
    }
    
    # Ensure phenotype table has at least two columns for test and adjustment variables
    if (ncol(pheno) < 2) {
        pheno\$dummy_gender <- rep("F", nrow(pheno))
    }
    
    test_var <- if ("group" %in% colnames(pheno)) pheno\$group else pheno[[1]]
    adjust_var <- if ("gender" %in% colnames(pheno)) pheno[, c("gender"), drop = FALSE] else pheno[, 2, drop = FALSE]
    
    models <- makeModels(sampleDepths, testvars = test_var, adjustvars = adjust_var)
    
    # ==========================================
    # STAGE 6: Perform base-level F-statistics analysis per chromosome using analyzeChr()
    # ==========================================
    
    dir.create("analysisResults", showWarnings = FALSE)
    originalWd <- getwd()
    setwd(file.path(originalWd, "analysisResults"))
    
    results <- analyzeChr(
        chr = chrs,
        filteredCov[[chrs]],
        models,
        groupInfo = test_var,
        writeOutput = TRUE,
        cutoffFstat = 5e-02,
        nPermute = 20,
        seeds = 20140923 + seq_len(20),
        returnOutput = TRUE,
        smooth = TRUE
    )
    
    setwd(originalWd)
    
    # ==========================================
    # STAGE 7: Merge results across chromosomes using mergeResults()
    # ==========================================
    
    # Build or load genomic state for merging results
    txdb_loaded <- FALSE
    if (requireNamespace("TxDb.Hsapiens.UCSC.hg19.knownGene", quietly = TRUE)) {
        library(TxDb.Hsapiens.UCSC.hg19.knownGene)
        txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene
        txdb_loaded <- TRUE
    } else {
        installed_pkgs <- rownames(installed.packages())
        txdb_pkgs <- installed_pkgs[grep("^TxDb\\\\.", installed_pkgs)]
        if (length(txdb_pkgs) > 0) {
            library(txdb_pkgs[1], character.only = TRUE)
            txdb <- get(txdb_pkgs[1])
            txdb_loaded <- TRUE
        }
    }
    
    if (txdb_loaded) {
        seqlevels(txdb, pruning.mode = "coarse") <- chrs
        genomicState <- makeGenomicState(txdb = txdb)
    } else {
        gtf_files <- list.files(pattern = "\\\\.gtf\$|\\\\.gff\$", ignore.case = TRUE)
        if (length(gtf_files) > 0) {
            txdb <- makeTxDbFromGFF(gtf_files[1])
            genomicState <- makeGenomicState(txdb = txdb)
        } else {
            # Fallback to a generic genomic state spanning the chromosome
            fullGenome <- GRanges(seqnames = chrs, ranges = IRanges(start = 1, end = 536870912))
            fullGenome\$theState <- factor("intergenic", levels = c("exon", "intron", "intergenic"))
            genomicState <- list(fullGenome = fullGenome)
        }
    }
    
    mergedResults <- mergeResults(
        chrs = chrs,
        prefix = "analysisResults",
        genomicState = genomicState\$fullGenome,
        optionsStats = results\$optionsStats
    )
    
    # ==========================================
    # WRITE OUTPUTS
    # ==========================================
    
    # Save RDS objects of the results
    saveRDS(results, file = "analyzeChr_results.rds")
    saveRDS(mergedResults, file = "merged_results.rds")
    
    # Export differentially expressed regions to CSV if available
    if (!is.null(mergedResults\$regions)) {
        regions_df <- as.data.frame(mergedResults\$regions)
        write.csv(regions_df, file = "differentially_expressed_regions.csv", row.names = FALSE)
    }
    
    # Generate a PDF plot of the F-statistics distribution
    pdf("f_statistics_distribution.pdf")
    if (!is.null(results\$fstats)) {
        hist(results\$fstats, main = "Distribution of F-statistics", xlab = "F-statistic", col = "skyblue", breaks = 50)
    } else {
        plot(1, type = "n", axes = FALSE, xlab = "", ylab = "")
        text(1, 1, "No F-statistics available to plot")
    }
    dev.off()

    writeLines(c(
        '"BIOC_DERFINDER_SINGLE_BASE_LEVEL_F_STATISTICS":',
        paste0('    derfinder: ', as.character(packageVersion('derfinder')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_base_level_f_statistics.csv versions.yml
    """
}

workflow BIOC_DERFINDER_SINGLE_BASE_LEVEL_F_STATISTICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ files, brainspanPheno ] ]

    main:
    BIOC_DERFINDER_SINGLE_BASE_LEVEL_F_STATISTICS(ch_input)

    emit:
    tables   = BIOC_DERFINDER_SINGLE_BASE_LEVEL_F_STATISTICS.out.tables
    plots    = BIOC_DERFINDER_SINGLE_BASE_LEVEL_F_STATISTICS.out.plots
    objects  = BIOC_DERFINDER_SINGLE_BASE_LEVEL_F_STATISTICS.out.objects
    versions = BIOC_DERFINDER_SINGLE_BASE_LEVEL_F_STATISTICS.out.versions
}
