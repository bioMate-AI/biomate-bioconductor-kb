#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: qpcrNorm — qpcr_normalization_pipeline
// Normalize high-throughput qPCR Ct data using rank-invariant, quantile, or housekeeping gene methods, and evaluate the normalization performance.
// Input: raw_qpcr_data.txt
// Container: quay.io/biocontainers/bioconductor-qpcrnorm:1.68.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: qpcrNorm
// Visualizations: bar plot, box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load raw data into a qpcrBatch object using readQpcr or readQpcrBatch
//  * 2. [Core Analysis] Apply quality control filtering using ctQc if needed
//  * 3. [Core Analysis] Normalize the data using normQpcrRankInvariant, normQpcrQuantile, normQpcrHouseKeepingGenes, or the generic normalize function
//  * 4. [Visualization & Output] Assess normalization performance using boxplot, hist, calcCV, and plotVarMean

nextflow.enable.dsl = 2

process BIOC_QPCRNORM_QPCR_NORMALIZATION_PIPELINE {
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
    .bm_deps <- c("qpcrNorm")
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
    library(qpcrNorm)
    
    # 1. Load raw data into a qpcrBatch object
    if (!file.exists("raw_qpcr_data.txt")) {
      stop("Error: 'raw_qpcr_data.txt' not found in the working directory.")
    }
    
    # Read the raw data using the package's built-in function
    qpcrBatch.object <- readQpcrBatch("raw_qpcr_data.txt")
    
    # Apply quality control filtering step
    qpcrBatch.object <- ctQc(qpcrBatch.object)
    
    # 2. Documented workflow steps
    slotNames(qpcrBatch.object)
    
    # Rank-Invariant Normalization
    mynormRI.data <- normQpcrRankInvariant(qpcrBatch.object, 1)
    mynormRI.data@normGenes
    
    # Quantile Normalization
    mynormQuant.data <- normQpcrQuantile(qpcrBatch.object) 
    
    # Dynamically select an existing gene to use as a housekeeping gene (e.g., the first gene)
    hk_gene <- qpcrBatch.object@geneNames[1]
    
    # Housekeeping Gene Normalization
    mynormHK.data <- normQpcrHouseKeepingGenes(qpcrBatch.object, c(hk_gene))
    
    # Generic Normalize calls
    mynormQuant.data <- normalize(qpcrBatch.object, "quantile") 
    mynormHK.data <- normalize(qpcrBatch.object, "housekeepinggenes", c(hk_gene))
    
    # 3. Assess normalization performance and save plots to PDF
    pdf("qpcr_normalization_plots.pdf", width=10, height=8)
    
    # Boxplot
    num_samples <- ncol(mynormQuant.data@exprs)
    boxplot(data.frame(mynormQuant.data@exprs), names=paste("Time", 1:num_samples, sep=""), col="darkgreen", ylab="Ct Value")
    
    # Histograms
    par(mfrow=c(2,2))
    xr <- range(c(qpcrBatch.object@exprs, mynormHK.data@exprs, mynormQuant.data@exprs, mynormRI.data@exprs), na.rm=TRUE)
    hist(qpcrBatch.object@exprs, breaks=30, prob=T, col="steelblue", main="Raw Data", xlab="Ct value", xlim=xr)
    hist(mynormHK.data@exprs, breaks=30, prob=T, col="orange", main="HK-Gene-Normalized Data", xlab="Ct value", xlim=xr) 
    hist(mynormQuant.data@exprs, breaks=30, prob=T, col="gold", main="Quantile-Normalized Data", xlab="Ct value", xlim=xr) 
    hist(mynormRI.data@exprs, breaks=30, prob=T, col="orchid4", main="Rank-Invariant-Normalized Data", xlab="Ct value", xlim=xr) 
    
    # CV Calculation and Barplot
    cvVals <- c(calcCV(qpcrBatch.object), calcCV(mynormHK.data), calcCV(mynormQuant.data), calcCV(mynormRI.data))
    barplot(cvVals*100, col=c("steelblue", "orange", "gold", "orchid4"), ylab="Average CV(%)", beside=TRUE, names=c("Raw", "HK", "Quantile", "Rank-Invariant"))
    text(c(.75, 1.9, 3.1, 4.3), rep(2,4), round(cvVals*100, 2))
    
    # Variance vs Mean Plot
    plotVarMean(mynormQuant.data, mynormHK.data, normTag1="Quantile", normTag2="HK-Gene")
    
    dev.off()
    
    # 4. Save output tables and RDS objects
    write.csv(as.data.frame(mynormRI.data@exprs), "normalized_RI_exprs.csv", row.names=TRUE)
    write.csv(as.data.frame(mynormQuant.data@exprs), "normalized_Quantile_exprs.csv", row.names=TRUE)
    write.csv(as.data.frame(mynormHK.data@exprs), "normalized_HK_exprs.csv", row.names=TRUE)
    
    saveRDS(mynormRI.data, "mynormRI_data.rds")
    saveRDS(mynormQuant.data, "mynormQuant_data.rds")
    saveRDS(mynormHK.data, "mynormHK_data.rds")

    writeLines(c(
        '"BIOC_QPCRNORM_QPCR_NORMALIZATION_PIPELINE":',
        paste0('    qpcrNorm: ', as.character(packageVersion('qpcrNorm')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qpcr_normalization_pipeline.csv versions.yml
    """
}

workflow BIOC_QPCRNORM_QPCR_NORMALIZATION_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_qpcr_data.txt ] ]

    main:
    BIOC_QPCRNORM_QPCR_NORMALIZATION_PIPELINE(ch_input)

    emit:
    tables   = BIOC_QPCRNORM_QPCR_NORMALIZATION_PIPELINE.out.tables
    plots    = BIOC_QPCRNORM_QPCR_NORMALIZATION_PIPELINE.out.plots
    objects  = BIOC_QPCRNORM_QPCR_NORMALIZATION_PIPELINE.out.objects
    versions = BIOC_QPCRNORM_QPCR_NORMALIZATION_PIPELINE.out.versions
}
