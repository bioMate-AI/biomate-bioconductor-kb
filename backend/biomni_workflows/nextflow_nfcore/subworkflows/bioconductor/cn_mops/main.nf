#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cn_mops — cn_mops_multisample_cnv
// Detect copy number variations (CNVs) across multiple samples from a read count matrix using the mixture of Poissons model in cn.mops.
// Input: input.csv
// Container: quay.io/biocontainers/r-base:4.3.1
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, IRanges, cn.mops, cn_mops
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CN_MOPS_CN_MOPS_MULTISAMPLE_CNV {
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
    .bm_deps <- c("cn.mops", "GenomicRanges")
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
    library(cn.mops)
    library(GenomicRanges)
    
    # --- Read and Preprocess Input ---
    message("Reading input data...")
    df <- read.csv("input.csv", header=TRUE, check.names=FALSE, stringsAsFactors=FALSE)
    
    if (ncol(df) < 2) {
      stop("Input CSV must have at least a feature identifier column and one sample column.")
    }
    
    # Identify feature column (either 'feature_id' or the first character/factor column)
    if ("feature_id" %in% colnames(df)) {
      feature_col <- "feature_id"
    } else if (is.character(df[[1]]) || is.factor(df[[1]])) {
      feature_col <- colnames(df)[1]
    } else {
      feature_col <- NULL
    }
    
    if (!is.null(feature_col)) {
      features <- df[[feature_col]]
      count_matrix <- as.matrix(df[, setdiff(colnames(df), feature_col), drop=FALSE])
      rownames(count_matrix) <- features
    } else {
      count_matrix <- as.matrix(df)
      rownames(count_matrix) <- paste0("bin_", seq_len(nrow(count_matrix)))
    }
    
    # Ensure count matrix is numeric and non-negative
    class(count_matrix) <- "numeric"
    count_matrix[is.na(count_matrix)] <- 0
    count_matrix[count_matrix < 0] <- 0
    
    # --- Parse Genomic Coordinates or Generate Dummy Coordinates ---
    message("Parsing genomic coordinates...")
    features <- rownames(count_matrix)
    parsed <- FALSE
    gr <- NULL
    
    tryCatch({
      # Attempt to split features by common separators (e.g., chr1:100-200 or chr1_100_200)
      split_feats <- strsplit(features, "[_:-]")
      if (all(sapply(split_feats, length) >= 3)) {
        chrs <- sapply(split_feats, function(x) x[1])
        starts <- as.numeric(sapply(split_feats, function(x) x[2]))
        ends <- as.numeric(sapply(split_feats, function(x) x[3]))
        
        if (!any(is.na(starts)) && !any(is.na(ends))) {
          gr <- GRanges(seqnames=chrs, ranges=IRanges(start=starts, end=ends))
          parsed <- TRUE
          message("Successfully parsed genomic coordinates from feature IDs.")
        }
      }
    }, error = function(e) {
      message("Coordinate parsing failed: ", e\$message)
    })
    
    if (!parsed || is.null(gr)) {
      message("Using sequential dummy coordinates on chr1 for segmentation.")
      gr <- GRanges(
        seqnames = "chr1",
        ranges = IRanges(
          start = seq(1, by = 1000, length.out = nrow(count_matrix)),
          width = 1000
        )
      )
    }
    
    # Append read counts as metadata columns to the GRanges object
    mcols(gr) <- as.data.frame(count_matrix)
    
    # --- Run cn.mops Pipeline ---
    message("Running cn.mops copy number estimation...")
    # cn.mops works best with multiple samples (ideally 3 or more)
    res <- cn.mops(
      input = gr,
      classes = c("CN0", "CN1", "CN2", "CN3", "CN4", "CN5", "CN6"),
      priorImpact = 1,
      cyc = 20,
      parallel = 1
    )
    
    message("Calculating integer copy numbers...")
    res <- calcIntegerCopyNumbers(res)
    
    # --- Extract and Export Results ---
    message("Extracting results...")
    
    # 1. Individual CNV calls
    cnvs_gr <- cnvs(res)
    cnvs_df <- as.data.frame(cnvs_gr)
    write.csv(cnvs_df, "cnvs.csv", row.names=FALSE)
    
    # 2. Combined CNV regions
    cnvr_gr <- cnvr(res)
    cnvr_df <- as.data.frame(cnvr_gr)
    write.csv(cnvr_df, "cnvr.csv", row.names=FALSE)
    
    # 3. Integer copy number matrix
    icn_matrix <- integerCopyNumber(res)
    icn_df <- data.frame(feature_id = rownames(count_matrix), icn_matrix, check.names=FALSE)
    write.csv(icn_df, "integer_copy_numbers.csv", row.names=FALSE)
    
    # --- Visualization ---
    message("Generating diagnostic plots...")
    pdf("cn_mops_plot.pdf", width=10, height=8)
    num_samples <- ncol(count_matrix)
    # Plot segmentation for up to the first 3 samples
    for (i in seq_len(min(3, num_samples))) {
      tryCatch({
        segplot(res, sampleIdx=i, main=paste("CNV Segmentation - Sample:", colnames(count_matrix)[i]))
      }, error = function(e) {
        warning("Could not generate plot for sample ", i, ": ", e\$message)
      })
    }
    dev.off()
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_CN_MOPS_CN_MOPS_MULTISAMPLE_CNV":',
        paste0('    cn_mops: ', as.character(packageVersion('cn_mops')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cn_mops_multisample_cnv.csv versions.yml
    """
}

workflow BIOC_CN_MOPS_CN_MOPS_MULTISAMPLE_CNV_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_CN_MOPS_CN_MOPS_MULTISAMPLE_CNV(ch_input)

    emit:
    tables   = BIOC_CN_MOPS_CN_MOPS_MULTISAMPLE_CNV.out.tables
    plots    = BIOC_CN_MOPS_CN_MOPS_MULTISAMPLE_CNV.out.plots
    objects  = BIOC_CN_MOPS_CN_MOPS_MULTISAMPLE_CNV.out.objects
    versions = BIOC_CN_MOPS_CN_MOPS_MULTISAMPLE_CNV.out.versions
}
