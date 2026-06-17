#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RTCA — rtca_data_transformation
// Apply mathematical transformations to RTCA cell index data to prepare for statistical analysis and modeling.
// Input: testOutput.csv, testOutputPhenoData.csv
// Container: quay.io/biocontainers/bioconductor-rtca:1.62.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, RTCA
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Parse raw data with phenotype metadata
//  * 2. [Core Analysis] Apply ratio transformation
//  * 3. [Core Analysis] Apply smooth transformation
//  * 4. [Core Analysis] Apply interpolation transformation
//  * 5. [Core Analysis] Apply derivative transformation
//  * 6. [Core Analysis] Apply relative growth rate transformation

nextflow.enable.dsl = 2

process BIOC_RTCA_RTCA_DATA_TRANSFORMATION {
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
    .bm_deps <- c("RTCA", "Biobase")
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
    library(RTCA)
    library(Biobase)
    
    # Define input file paths as specified by the user
    ofile <- "testOutput.csv"
    pfile <- "testOutputPhenoData.csv"
    
    # Check if input files exist before proceeding
    if (!file.exists(ofile)) {
      stop(paste("Required input file missing:", ofile))
    }
    if (!file.exists(pfile)) {
      stop(paste("Required input file missing:", pfile))
    }
    
    # 1. Parse raw data with phenotype metadata
    pData <- read.csv(pfile, sep="\t", row.names="Well")
    metaData <- data.frame(labelDescription=colnames(pData), row.names=colnames(pData))
    phData <- new("AnnotatedDataFrame", data=pData, varMetadata=metaData)
    x <- parseRTCA(ofile, phenoData=phData)
    
    # 2. Apply ratio transformation
    # Dynamically determine a valid base-time (e.g., the median time point > 0)
    time_points <- as.numeric(featureNames(x))
    valid_times <- time_points[time_points > 0]
    if (length(valid_times) > 0) {
      base_time <- valid_times[ceiling(length(valid_times) / 2)]
    } else {
      base_time <- time_points[1]
    }
    xRatio <- ratioTransform(x, base_time)
    
    # 3. Apply smooth transformation
    xSmooth <- smoothTransform(x)
    
    # 4. Apply interpolation transformation
    xInter <- interpolationTransform(x)
    
    # 5. Apply derivative transformation
    xDeriv <- derivativeTransform(x)
    
    # 6. Apply relative growth rate transformation
    xRgr <- rgrTransform(x)
    
    # Save transformed data matrices as CSV files
    write.csv(exprs(x), "rtca_raw_expression.csv", row.names=TRUE)
    write.csv(exprs(xRatio), "rtca_ratio_transformed.csv", row.names=TRUE)
    write.csv(exprs(xSmooth), "rtca_smooth_transformed.csv", row.names=TRUE)
    write.csv(exprs(xInter), "rtca_interpolation_transformed.csv", row.names=TRUE)
    write.csv(exprs(xDeriv), "rtca_derivative_transformed.csv", row.names=TRUE)
    write.csv(exprs(xRgr), "rtca_rgr_transformed.csv", row.names=TRUE)
    
    # Save the R objects as RDS for downstream analysis
    saveRDS(x, "rtca_raw_object.rds")
    saveRDS(xRatio, "rtca_ratio_object.rds")
    saveRDS(xSmooth, "rtca_smooth_object.rds")
    saveRDS(xInter, "rtca_interpolation_object.rds")
    saveRDS(xDeriv, "rtca_derivative_object.rds")
    saveRDS(xRgr, "rtca_rgr_object.rds")
    
    # Generate diagnostic visualization comparing the transformations for the first 4 wells
    pdf("rtca_transformations_comparison.pdf", width=10, height=12)
    par(mfrow=c(3, 2))
    
    # Raw
    plot(x[, 1:4], type="l", col="black", lty=1:4, xlab="time point", ylab="Cell Index", main="Raw Cell Index")
    
    # Ratio Transform
    plot(xRatio[, 1:4], type="l", col="black", lty=1:4, xlab="time point", ylab="Normalized Cell Index", main=paste0("Ratio Transform (Base-time: ", base_time, ")"))
    abline(v=base_time, col="red", lty=2, lwd=1.5)
    
    # Smooth Transform
    plot(xSmooth[, 1:4], type="l", col="black", lty=1:4, xlab="time point", ylab="Smoothed Cell Index", main="Cubic Spline Smooth Transform")
    
    # Interpolation Transform
    plot(xInter[, 1:4], type="l", col="black", lty=1:4, xlab="time point", ylab="Interpolated Cell Index", main="Interpolation Transform")
    
    # Derivative Transform
    plot(xDeriv[, 1:4], type="l", col="black", lty=1:4, xlab="time point", ylab="First Derivative", main="Derivative Transform (Growth Rate)")
    
    # Relative Growth Rate Transform
    plot(xRgr[, 1:4], type="l", col="black", lty=1:4, xlab="time point", ylab="Relative Growth Rate", main="Relative Growth Rate Transform")
    
    dev.off()
    
    cat("RTCA data transformation pipeline completed successfully.\n")

    writeLines(c(
        '"BIOC_RTCA_RTCA_DATA_TRANSFORMATION":',
        paste0('    RTCA: ', as.character(packageVersion('RTCA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rtca_data_transformation.csv versions.yml
    """
}

workflow BIOC_RTCA_RTCA_DATA_TRANSFORMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ testOutput.csv, testOutputPhenoData.csv ] ]

    main:
    BIOC_RTCA_RTCA_DATA_TRANSFORMATION(ch_input)

    emit:
    tables   = BIOC_RTCA_RTCA_DATA_TRANSFORMATION.out.tables
    plots    = BIOC_RTCA_RTCA_DATA_TRANSFORMATION.out.plots
    objects  = BIOC_RTCA_RTCA_DATA_TRANSFORMATION.out.objects
    versions = BIOC_RTCA_RTCA_DATA_TRANSFORMATION.out.versions
}
