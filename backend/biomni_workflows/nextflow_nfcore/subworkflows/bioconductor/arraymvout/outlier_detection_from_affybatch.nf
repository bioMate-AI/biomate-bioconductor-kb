#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: arrayMvout — outlier_detection_from_affybatch
// Perform comprehensive outlier detection directly on a raw AffyBatch object by computing and utilizing intermediate QA diagnostics.
// Input: raw_arrays.CEL
// Container: quay.io/biocontainers/bioconductor-arraymvout:1.68.0--r45hdfd78af_0
// R packages: affy, affyPLM, arrayMvout, simpleaffy
// Bioconductor: 3.20 | R: 4.4
// Requires: affy, affyPLM, arrayMvout, simpleaffy
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the AffyBatch object
//  * 2. [Core Analysis] Compute RNA degradation using AffyRNAdeg
//  * 3. [Core Analysis] Compute simpleaffy QC using qc
//  * 4. [Core Analysis] Fit probe-level models using fitPLM
//  * 5. [Core Analysis] Run outlier detection using ArrayOutliers with the pre-computed QA objects

nextflow.enable.dsl = 2

process BIOC_ARRAYMVOUT_OUTLIER_DETECTION_FROM_AFFYBATCH {
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
    .bm_deps <- c("affy", "affyPLM", "arrayMvout", "simpleaffy")
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
        
    # Load required Bioconductor libraries
    library(affy)
    library(simpleaffy)
    library(affyPLM)
    library(arrayMvout)
    
    # ==========================================
    # 1. Load the AffyBatch object from USER INPUT
    # ==========================================
    # The pipeline reads raw Affymetrix CEL files from the 'raw_arrays.CEL' directory
    # or falls back to the current working directory if the directory is structured differently.
    if (dir.exists("raw_arrays.CEL")) {
      message("Loading CEL files from 'raw_arrays.CEL' directory...")
      afxsub <- ReadAffy(celfile.path = "raw_arrays.CEL")
    } else {
      cel_files <- list.files(pattern = "\\\\.[Cc][Ee][Ll]\$")
      if (length(cel_files) > 0) {
        message("Loading CEL files from current working directory...")
        afxsub <- ReadAffy(filenames = cel_files)
      } else {
        stop("Error: Could not find 'raw_arrays.CEL' directory or any CEL files in the working directory.")
      }
    }
    
    # ==========================================
    # 2. Compute RNA degradation using AffyRNAdeg
    # ==========================================
    message("Computing RNA degradation...")
    afxsubDEG = AffyRNAdeg(afxsub)
    
    # Plot RNA degradation and save to PDF
    pdf("rna_degradation_plot.pdf", width = 8, height = 6)
    plotAffyRNAdeg(afxsubDEG)
    dev.off()
    message("Saved RNA degradation plot to 'rna_degradation_plot.pdf'")
    
    # ==========================================
    # 3. Compute simpleaffy QC using qc
    # ==========================================
    message("Computing simpleaffy QC diagnostics...")
    afxsubQC = qc(afxsub)
    
    # Plot simpleaffy QC and save to PDF
    pdf("simpleaffy_qc_plot.pdf", width = 10, height = 8)
    plot(afxsubQC)
    dev.off()
    message("Saved simpleaffy QC plot to 'simpleaffy_qc_plot.pdf'")
    
    # ==========================================
    # 4. Fit probe-level models using fitPLM
    # ==========================================
    message("Fitting probe-level models (PLM)...")
    splm = fitPLM(afxsub)
    
    # ==========================================
    # 5. Run outlier detection using ArrayOutliers
    # ==========================================
    message("Running outlier detection with ArrayOutliers...")
    AO = ArrayOutliers(afxsub, alpha=0.05, qcOut=afxsubQC, 
      plmOut=splm, degOut=afxsubDEG)
    
    # Display meaningful results to stdout
    num_outliers <- nrow(AO[["outl"]])
    cat("\nNumber of detected outliers:", num_outliers, "\n")
    
    cat("\nFirst few rows of QC features:\n")
    print(AO[[3]][1:min(2, nrow(AO[[3]])), , drop = FALSE])
    
    # ==========================================
    # 6. Write output files
    # ==========================================
    # Save the detected outliers table
    write.csv(AO[["outl"]], "detected_outliers.csv", row.names = TRUE)
    message("Saved detected outliers table to 'detected_outliers.csv'")
    
    # Save the full QC features matrix
    write.csv(AO[[3]], "qc_features.csv", row.names = TRUE)
    message("Saved QC features to 'qc_features.csv'")
    
    # Save the complete ArrayOutliers output object as RDS
    saveRDS(AO, "array_outliers_result.rds")
    message("Saved full ArrayOutliers result object to 'array_outliers_result.rds'")
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_ARRAYMVOUT_OUTLIER_DETECTION_FROM_AFFYBATCH":',
        paste0('    arrayMvout: ', as.character(packageVersion('arrayMvout')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_outlier_detection_from_affybatch.csv versions.yml
    """
}

workflow BIOC_ARRAYMVOUT_OUTLIER_DETECTION_FROM_AFFYBATCH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_arrays.CEL ] ]

    main:
    BIOC_ARRAYMVOUT_OUTLIER_DETECTION_FROM_AFFYBATCH(ch_input)

    emit:
    tables   = BIOC_ARRAYMVOUT_OUTLIER_DETECTION_FROM_AFFYBATCH.out.tables
    plots    = BIOC_ARRAYMVOUT_OUTLIER_DETECTION_FROM_AFFYBATCH.out.plots
    objects  = BIOC_ARRAYMVOUT_OUTLIER_DETECTION_FROM_AFFYBATCH.out.objects
    versions = BIOC_ARRAYMVOUT_OUTLIER_DETECTION_FROM_AFFYBATCH.out.versions
}
