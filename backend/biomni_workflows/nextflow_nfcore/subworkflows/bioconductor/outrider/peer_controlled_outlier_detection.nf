#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: OUTRIDER — peer_controlled_outlier_detection
// Detect aberrantly expressed genes in RNA-seq data using PEER to control for confounders instead of the autoencoder.
// Input: ctsTable, annoTable
// Container: quay.io/biocontainers/bioconductor-outrider:1.28.0--r45ha27e39d_0
// R packages: OUTRIDER, peer
// Bioconductor: 3.20 | R: 4.4
// Requires: OUTRIDER, peer
// Visualizations: heatmap
// QC: dispersion/size-factor estimation
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create the OutriderDataSet object and filter non-expressed genes. 2. Estimate size factors. 3. Run the PEER model to calculate res

nextflow.enable.dsl = 2

process BIOC_OUTRIDER_PEER_CONTROLLED_OUTLIER_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("OUTRIDER", "peer")
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
    library(OUTRIDER)
    
    # Helper function to robustly read input files (TSV or CSV)
    read_input <- function(file_path) {
      tryCatch({
        read.table(file_path, header=TRUE, sep="\t", check.names=FALSE, stringsAsFactors=FALSE)
      }, error = function(e) {
        read.csv(file_path, header=TRUE, check.names=FALSE, stringsAsFactors=FALSE)
      })
    }
    
    # Locate input files in the working directory
    cts_file <- list.files(pattern = "^ctsTable(\\\\..+)?\$", ignore.case = TRUE)[1]
    anno_file <- list.files(pattern = "^annoTable(\\\\..+)?\$", ignore.case = TRUE)[1]
    
    if (is.na(cts_file)) {
      stop("Error: ctsTable file not found in the working directory.")
    }
    if (is.na(anno_file)) {
      stop("Error: annoTable file not found in the working directory.")
    }
    
    # Read raw data
    cts_raw <- read_input(cts_file)
    anno_raw <- read_input(anno_file)
    
    # Format count matrix (ensure gene IDs are row names)
    if (!is.numeric(cts_raw[[1]])) {
      rownames(cts_raw) <- cts_raw[[1]]
      cts_raw <- cts_raw[, -1, drop=FALSE]
    }
    ctsTable <- as.matrix(cts_raw)
    
    # Format annotation table
    if (!"sampleID" %in% colnames(anno_raw)) {
      if ("RNA_ID" %in% colnames(anno_raw)) {
        anno_raw\$sampleID <- anno_raw\$RNA_ID
      } else if (!is.numeric(anno_raw[[1]])) {
        anno_raw\$sampleID <- anno_raw[[1]]
      } else {
        anno_raw\$sampleID <- colnames(ctsTable)[1:nrow(anno_raw)]
      }
    }
    rownames(anno_raw) <- anno_raw\$sampleID
    annoTable <- anno_raw
    
    # Align samples between counts and annotations
    common_samples <- intersect(colnames(ctsTable), rownames(annoTable))
    if (length(common_samples) == 0) {
      stop("Error: No common sample IDs found between ctsTable columns and annoTable sampleIDs.")
    }
    ctsTable <- ctsTable[, common_samples, drop=FALSE]
    annoTable <- annoTable[common_samples, , drop=FALSE]
    
    # 1. Create the OutriderDataSet object and filter non-expressed genes
    ods <- OutriderDataSet(countData=ctsTable, colData=annoTable)
    ods <- filterExpression(ods, minCounts=TRUE, filterGenes=TRUE)
    
    # PEER implementation function (reproduced faithfully from documented code)
    peer <- function(ods, maxFactors=NA, maxItr=1000){
    
        # check for PEER
        if(!require(peer)){
            stop("Please install the 'peer' package from GitHub to use this ",
                    "functionality.")
        }
    
        # default and recommendation by PEER: min(0.25*n, 100)
        if(is.na(maxFactors)){
            maxFactors <- min(as.integer(0.25* ncol(ods)), 100)
        }
    
        # log counts
        logCts <- log2(t(t(counts(ods)+1)/sizeFactors(ods)))
    
        # prepare PEER model
        model <- PEER()
        PEER_setNmax_iterations(model, maxItr)
        PEER_setNk(model, maxFactors)
        PEER_setPhenoMean(model, logCts)
        PEER_setAdd_mean(model, TRUE)
    
        # run fullpeer pipeline
        PEER_update(model)
    
        # extract PEER data
        peerResiduals <- PEER_getResiduals(model)
        peerMean <- t(t(2^(logCts - peerResiduals)) * sizeFactors(ods))
    
        # save model in object
        normalizationFactors(ods) <- pmax(peerMean, 1E-8)
        metadata(ods)[["PEER_model"]] <- list(
                alpha     = PEER_getAlpha(model),
                residuals = PEER_getResiduals(model),
                W         = PEER_getW(model))
    
        return(ods)
    }
    
    # 2. Estimate size factors
    ods <- estimateSizeFactors(ods)
    
    # 3. Run the PEER model to calculate residuals and expected means, saving them as normalization factors
    ods <- peer(ods)
    
    # 4. Fit the negative binomial model
    ods <- fit(ods)
    
    # 5. Compute Z-scores using PEER residuals
    ods <- computeZscores(ods, peerResiduals=TRUE)
    
    # 6. Compute P-values and extract results
    ods <- computePvalues(ods)
    
    # Extract results table
    res <- results(ods)
    
    # Write output files
    write.csv(as.data.frame(res), "outrider_results.csv", row.names=FALSE)
    saveRDS(ods, "outrider_ods.rds")
    
    # Save summary of aberrant genes per sample
    ab_sample <- aberrant(ods, by="sample")
    write.csv(data.frame(sampleID=names(ab_sample), aberrantGeneCount=ab_sample),
              "aberrant_genes_per_sample.csv", row.names=FALSE)
    
    # Generate diagnostic plots
    pdf("sample_correlation_heatmap.pdf", width=7, height=7)
    tryCatch({
      plotCountCorHeatmap(ods, normalized=TRUE)
    }, error = function(e) {
      warning("Could not plot correlation heatmap: ", e\$message)
    })
    dev.off()
    
    pdf("power_analysis_plot.pdf", width=7, height=7)
    tryCatch({
      plotPowerAnalysis(ods)
    }, error = function(e) {
      warning("Could not plot power analysis: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_OUTRIDER_PEER_CONTROLLED_OUTLIER_DETECTION":',
        paste0('    OUTRIDER: ', as.character(packageVersion('OUTRIDER')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_peer_controlled_outlier_detection.csv versions.yml
    """
}

workflow BIOC_OUTRIDER_PEER_CONTROLLED_OUTLIER_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ctsTable, annoTable ] ]

    main:
    BIOC_OUTRIDER_PEER_CONTROLLED_OUTLIER_DETECTION(ch_input)

    emit:
    tables   = BIOC_OUTRIDER_PEER_CONTROLLED_OUTLIER_DETECTION.out.tables
    plots    = BIOC_OUTRIDER_PEER_CONTROLLED_OUTLIER_DETECTION.out.plots
    objects  = BIOC_OUTRIDER_PEER_CONTROLLED_OUTLIER_DETECTION.out.objects
    versions = BIOC_OUTRIDER_PEER_CONTROLLED_OUTLIER_DETECTION.out.versions
}
