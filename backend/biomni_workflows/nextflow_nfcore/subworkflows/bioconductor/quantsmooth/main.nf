#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: quantsmooth — quantile_smoothing_and_aberration_detection
// Smooth copy number array data, optimize the smoothing parameter, visualize profiles with multiple quantiles, and detect genomic regions with copy number changes
// Input: copy_number_matrix.csv, probe_positions.csv
// Container: quay.io/biocontainers/bioconductor-quantsmooth:1.76.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: quantsmooth
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Perform basic quantile smoothing using quantsmooth
//  * 2. [Visualization & Output] Scale the smoothing parameter smooth.lambda based on
//  * 3. [Visualization & Output] Perform cross-validation using quantsmooth.cv to find the
//  * 4. [Visualization & Output] Smooth and plot multiple percentiles (e.g., 25th and
//  * 5. [Visualization & Output] Use plotSmoothed for automated multi-quantile plotting
//  * 6. [Visualization & Output] Identify genomic regions with copy number changes using

nextflow.enable.dsl = 2

process BIOC_QUANTSMOOTH_QUANTILE_SMOOTHING_AND_ABERRATION_DETECTION {
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
    .bm_deps <- c("quantsmooth")
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
        
    # Load required library
    library(quantsmooth)
    
    # ==========================================
    # 1. READ USER INPUT FILES
    # ==========================================
    
    if (!file.exists("copy_number_matrix.csv")) {
      stop("Required input file 'copy_number_matrix.csv' not found in the working directory.")
    }
    if (!file.exists("probe_positions.csv")) {
      stop("Required input file 'probe_positions.csv' not found in the working directory.")
    }
    
    cn_df <- read.csv("copy_number_matrix.csv", header = TRUE)
    pos_df <- read.csv("probe_positions.csv", header = TRUE)
    
    # Robustly extract numeric columns
    numeric_cols_cn <- which(sapply(cn_df, is.numeric))
    if (length(numeric_cols_cn) == 0) {
      cn_matrix <- matrix(as.numeric(as.matrix(cn_df)), nrow = nrow(cn_df))
    } else {
      cn_matrix <- as.matrix(cn_df[, numeric_cols_cn, drop = FALSE])
    }
    
    numeric_cols_pos <- which(sapply(pos_df, is.numeric))
    if (length(numeric_cols_pos) == 0) {
      pos_vector <- as.numeric(pos_df[[1]])
    } else {
      pos_vector <- pos_df[[numeric_cols_pos[1]]]
    }
    
    # Align lengths to prevent mismatch errors
    common_len <- min(nrow(cn_matrix), length(pos_vector))
    if (common_len == 0) {
      stop("Input files are empty or could not be parsed as numeric.")
    }
    
    primary_cn <- cn_matrix[1:common_len, 1, drop = FALSE]
    primary_pos <- pos_vector[1:common_len]
    
    # ==========================================
    # 2. EXECUTE WORKFLOW & GENERATE PLOTS
    # ==========================================
    
    pdf("quantsmooth_plots.pdf", width = 10, height = 8)
    
    # --- Perform basic quantile smoothing using quantsmooth ---
    plot(primary_cn[,1],pch=".")
    lines(quantsmooth(primary_cn[,1]),lwd=2)
    
    plot(primary_pos,primary_cn[,1],ylab="copy number",xlab="position",pch=".")
    lines(primary_pos,quantsmooth(primary_cn[,1]),lwd=2)
    
    # --- Scale the smoothing parameter smooth.lambda based on ---
    lambda.divisor<-50
    plot(primary_pos,primary_cn[,1],ylab="copy number",xlab="position",pch=".")
    lines(primary_pos,quantsmooth(primary_cn[,1],smooth.lambda=length(primary_pos)/lambda.divisor),lwd=2)
    
    # --- Perform cross-validation using quantsmooth.cv to find the ---
    lambdas<-2^seq(from=-2,to=5,by=0.25)
    lambda.res <- rep(NA, length(lambdas))
    for (lambda in 1:length(lambdas)) lambda.res[lambda] <- quantsmooth.cv(primary_cn[,1], lambdas[lambda])
    plot(lambdas,lambda.res,type="l")
    abline(v=lambdas[which.min(lambda.res)])
    
    # --- Smooth and plot multiple percentiles (e.g., 25th and ---
    plot(primary_pos,quantsmooth(primary_cn[,1],smooth.lambda=length(primary_pos)/lambda.divisor),col="red",type="l",lwd=2)
    lines(primary_pos,quantsmooth(primary_cn[,1],smooth.lambda=length(primary_pos)/lambda.divisor,tau=0.25),col="red",lty=2)
    lines(primary_pos,quantsmooth(primary_cn[,1],smooth.lambda=length(primary_pos)/lambda.divisor,tau=0.75),col="red",lty=2)
    
    # --- Use plotSmoothed for automated multi-quantile plotting ---
    cn_min <- min(primary_cn[,1], na.rm = TRUE)
    cn_max <- max(primary_cn[,1], na.rm = TRUE)
    norm_val <- median(primary_cn[,1], na.rm = TRUE)
    
    plotSmoothed(primary_cn,primary_pos,ylim=c(cn_min,cn_max),normalized.to=norm_val,smooth.lambda=length(primary_pos)/lambda.divisor)
    
    # --- Identify genomic regions with copy number changes using ---
    plotSmoothed(primary_cn[,1],primary_pos,ylim=c(cn_min,cn_max),normalized.to=norm_val,smooth.lambda=length(primary_pos)/lambda.divisor)
    res<-getChangedRegions(primary_cn[,1],primary_pos,normalized.to=norm_val,interval=0.5)
    
    if (!is.null(res) && nrow(res) > 0) {
      segments(res[,"start"],cn_min,res[,"end"],cn_min,col=2,lwd=2)
    }
    
    dev.off()
    
    # ==========================================
    # 3. WRITE OUTPUT TABLES
    # ==========================================
    
    # Save detected changed regions
    if (!is.null(res) && nrow(res) > 0) {
      write.csv(res, "changed_regions.csv", row.names = FALSE)
    } else {
      write.csv(data.frame(Message="No changed regions detected"), "changed_regions.csv", row.names = FALSE)
    }
    
    # Save optimal lambda from cross-validation
    optimal_lambda <- lambdas[which.min(lambda.res)]
    write.csv(data.frame(Optimal_Lambda = optimal_lambda), "optimal_lambda.csv", row.names = FALSE)
    
    # Save smoothed copy number values
    smoothed_val <- quantsmooth(primary_cn[,1], smooth.lambda = length(primary_pos)/lambda.divisor)
    smoothed_df <- data.frame(
      Position = primary_pos,
      Original_CN = primary_cn[,1],
      Smoothed_CN = smoothed_val
    )
    write.csv(smoothed_df, "smoothed_copy_number.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_QUANTSMOOTH_QUANTILE_SMOOTHING_AND_ABERRATION_DETECTION":',
        paste0('    quantsmooth: ', as.character(packageVersion('quantsmooth')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_quantile_smoothing_and_aberration_detection.csv versions.yml
    """
}

workflow BIOC_QUANTSMOOTH_QUANTILE_SMOOTHING_AND_ABERRATION_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ copy_number_matrix.csv, probe_positions.csv ] ]

    main:
    BIOC_QUANTSMOOTH_QUANTILE_SMOOTHING_AND_ABERRATION_DETECTION(ch_input)

    emit:
    tables   = BIOC_QUANTSMOOTH_QUANTILE_SMOOTHING_AND_ABERRATION_DETECTION.out.tables
    plots    = BIOC_QUANTSMOOTH_QUANTILE_SMOOTHING_AND_ABERRATION_DETECTION.out.plots
    objects  = BIOC_QUANTSMOOTH_QUANTILE_SMOOTHING_AND_ABERRATION_DETECTION.out.objects
    versions = BIOC_QUANTSMOOTH_QUANTILE_SMOOTHING_AND_ABERRATION_DETECTION.out.versions
}
