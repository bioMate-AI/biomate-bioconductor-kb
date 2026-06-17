#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: derfinder — expressed_regions_level
// Identify novel expressed regions (ERs) from raw coverage data, construct a coverage matrix, and find differentially expressed regions (DERs) using DESeq2 or lim
// Input: files, brainspanPheno
// Container: quay.io/biocontainers/bioconductor-derfinder:1.44.0--r45hdfd78af_0
// R packages: Rsamtools, TxDb.Hsapiens.UCSC.hg19.knownGene, bumphunter, derfinder, DESeq2, GenomicRanges, IRanges, refmanager, rtracklayer
// Bioconductor: 3.20 | R: 4.4
// Requires: DESeq2, GenomicRanges, Rsamtools, TxDb.Hsapiens.UCSC.hg19.knownGene, derfinder, rtracklayer
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Locate raw coverage files using rawFiles()
//  * 2. [Input & Preparation] Load coverage data into memory using fullCoverage()
//  * 3. [Visualization & Output] Identify expressed regions and calculate the coverage matrix using regionMatrix() (or railMatrix() if pre-computed summary files a
//  * 4. [Core Analysis] Perform differential expression analysis using DESeq2 or limma
//  * 5. [Core Analysis] Annotate the identified regions using annotateRegions()

nextflow.enable.dsl = 2

process BIOC_DERFINDER_EXPRESSED_REGIONS_LEVEL {
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
    .bm_deps <- c("Rsamtools", "TxDb.Hsapiens.UCSC.hg19.knownGene", "bumphunter", "derfinder", "DESeq2", "GenomicRanges", "IRanges", "refmanager", "rtracklayer")
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
    library("derfinder")
    library("GenomicRanges")
    library("DESeq2")
    library("TxDb.Hsapiens.UCSC.hg19.knownGene")
    library("rtracklayer")
    library("Rsamtools")
    
    # -----------------------------------------------------------------------------
    # Stage 1: Locate raw coverage files and load phenotype data from working directory
    # -----------------------------------------------------------------------------
    
    # Read brainspanPheno from the working directory (supports CSV, TSV, or RDS)
    if (file.exists("brainspanPheno.csv")) {
      brainspanPheno <- read.csv("brainspanPheno.csv", stringsAsFactors = FALSE, row.names = 1)
    } else if (file.exists("brainspanPheno.tsv")) {
      brainspanPheno <- read.delim("brainspanPheno.tsv", stringsAsFactors = FALSE, row.names = 1)
    } else if (file.exists("brainspanPheno.rds")) {
      brainspanPheno <- readRDS("brainspanPheno.rds")
    } else {
      stop("Error: brainspanPheno file (CSV, TSV, or RDS) not found in the working directory.")
    }
    
    # Locate raw coverage files (BigWig or BAM) in the working directory
    bw_files <- list.files(".", pattern = "\\\\.bw\$")
    bam_files <- list.files(".", pattern = "\\\\.bam\$")
    
    if (length(bw_files) > 0) {
      files <- rawFiles(".", samplepatt = "bw", fileterm = NULL)
      names(files) <- gsub(".bw", "", names(files))
      chrs <- seqlevels(seqinfo(BigWigFile(unname(files[1]))))
    } else if (length(bam_files) > 0) {
      files <- rawFiles(".", samplepatt = "bam", fileterm = NULL)
      names(files) <- gsub(".bam", "", names(files))
      chrs <- seqlevels(seqinfo(BamFile(unname(files[1]))))
    } else {
      stop("Error: No .bw or .bam files found in the working directory.")
    }
    
    # -----------------------------------------------------------------------------
    # Stage 2: Load coverage data into memory
    # -----------------------------------------------------------------------------
    fullCov <- fullCoverage(files = files, chrs = chrs, verbose = FALSE)
    
    # -----------------------------------------------------------------------------
    # Stage 3: Identify expressed regions and calculate the coverage matrix
    # -----------------------------------------------------------------------------
    regionMat <- regionMatrix(fullCov, cutoff = 30, L = 76, verbose = FALSE)
    
    # -----------------------------------------------------------------------------
    # Stage 4: Perform differential expression analysis using DESeq2
    # -----------------------------------------------------------------------------
    pheno <- brainspanPheno
    
    # Combine coverage matrices and regions across all chromosomes
    counts_list <- lapply(regionMat, function(x) x\$coverageMatrix)
    counts <- round(do.call(rbind, unname(counts_list)))
    
    ers_list <- lapply(regionMat, function(x) x\$regions)
    ers <- do.call(c, unname(ers_list))
    
    # Match pheno rownames to counts colnames to prevent DESeqDataSetFromMatrix error
    common_samples <- intersect(colnames(counts), rownames(pheno))
    if (length(common_samples) == 0) {
      stop("Error: No matching samples found between phenotype data and coverage files.")
    }
    counts <- counts[, common_samples, drop = FALSE]
    pheno <- pheno[common_samples, , drop = FALSE]
    
    # Dynamically build design formula using all columns in pheno
    covariates <- colnames(pheno)
    design_formula <- as.formula(paste("~", paste(covariates, collapse = " + ")))
    
    dse <- DESeqDataSetFromMatrix(counts, pheno, design = design_formula)
    
    # Use LRT, dropping the last covariate for the reduced model
    if (length(covariates) > 1) {
      reduced_formula <- as.formula(paste("~", paste(covariates[-length(covariates)], collapse = " + ")))
    } else {
      reduced_formula <- ~ 1
    }
    
    dse <- DESeq(dse, test = "LRT", reduced = reduced_formula, fitType = "local")
    mcols(ers) <- c(mcols(ers), results(dse))
    
    # -----------------------------------------------------------------------------
    # Stage 5: Annotate the identified regions
    # -----------------------------------------------------------------------------
    # Build genomicState dynamically using TxDb.Hsapiens.UCSC.hg19.knownGene for the detected chromosomes
    txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene
    valid_chrs <- intersect(chrs, seqlevels(txdb))
    
    if (length(valid_chrs) > 0) {
      seqlevels(txdb) <- valid_chrs
      genomicState <- makeGenomicState(txdb = txdb, chrs = valid_chrs)
      annoRegs <- annotateRegions(ers, genomicState\$fullGenome, verbose = FALSE)
      txdb <- restoreSeqlevels(txdb)
    } else {
      warning("No matching chromosomes found in TxDb.Hsapiens.UCSC.hg19.knownGene. Skipping annotation.")
      annoRegs <- NULL
    }
    
    # -----------------------------------------------------------------------------
    # Stage 6: Write output files
    # -----------------------------------------------------------------------------
    
    # Save Expressed Regions (ERs) with DESeq2 statistics
    saveRDS(ers, "expressed_regions_deseq2.rds")
    write.csv(as.data.frame(ers), "expressed_regions_deseq2.csv", row.names = FALSE)
    
    # Save Annotation Results
    saveRDS(annoRegs, "annotated_regions.rds")
    if (is.list(annoRegs)) {
      for (name in names(annoRegs)) {
        tryCatch({
          write.csv(as.data.frame(annoRegs[[name]]), paste0("annotated_regions_", name, ".csv"), row.names = FALSE)
        }, error = function(e) {
          # Ignore elements that cannot be coerced to a data frame
        })
      }
    }
    
    # Save diagnostic plot of p-values
    pdf("deseq2_pvalues_histogram.pdf")
    hist(ers\$pvalue, main = "DESeq2 P-values for Expressed Regions", xlab = "p-value", col = "skyblue", breaks = 20)
    dev.off()

    writeLines(c(
        '"BIOC_DERFINDER_EXPRESSED_REGIONS_LEVEL":',
        paste0('    derfinder: ', as.character(packageVersion('derfinder')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_expressed_regions_level.csv versions.yml
    """
}

workflow BIOC_DERFINDER_EXPRESSED_REGIONS_LEVEL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ files, brainspanPheno ] ]

    main:
    BIOC_DERFINDER_EXPRESSED_REGIONS_LEVEL(ch_input)

    emit:
    tables   = BIOC_DERFINDER_EXPRESSED_REGIONS_LEVEL.out.tables
    plots    = BIOC_DERFINDER_EXPRESSED_REGIONS_LEVEL.out.plots
    objects  = BIOC_DERFINDER_EXPRESSED_REGIONS_LEVEL.out.objects
    versions = BIOC_DERFINDER_EXPRESSED_REGIONS_LEVEL.out.versions
}
