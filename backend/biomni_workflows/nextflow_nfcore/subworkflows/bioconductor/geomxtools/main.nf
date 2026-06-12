#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: geomxtools — rna_preprocessing_and_coercion
// Read, QC, aggregate, normalize, and coerce GeoMx RNA data to Seurat or SpatialExperiment objects.
// Input: DCCFiles, PKCFiles, SampleAnnotationFile
// Container: quay.io/biocontainers/bioconductor-geomxtools:3.14.0--r45hdfd78af_0
// R packages: Biobase, envstats, GeomxTools, NanoStringNCTools, Seurat, SpatialDecon, SpatialExperiment
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GEOMXTOOLS_RNA_PREPROCESSING_AND_COERCION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-geomxtools:3.14.0--r45hdfd78af_0"

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
    .bm_deps <- c("Biobase", "envstats", "GeomxTools", "NanoStringNCTools", "Seurat", "SpatialDecon", "SpatialExperiment")
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
    library(GeomxTools)
    library(NanoStringNCTools)
    library(Biobase)
    library(Seurat)
    library(SpatialExperiment)
    
    # ==========================================
    # --- Locate User Input Files in Working Dir ---
    # ==========================================
    
    # Locate DCC files
    DCCFiles <- list.files(path = ".", pattern = "\\\\.dcc\$", full.names = TRUE, ignore.case = TRUE)
    if (length(DCCFiles) == 0) {
      stop("Error: No DCC files found in the working directory.")
    }
    
    # Locate PKC files
    PKCFiles <- list.files(path = ".", pattern = "\\\\.pkc\$", full.names = TRUE, ignore.case = TRUE)
    if (length(PKCFiles) == 0) {
      # Check if there is a zip file containing pkcs
      zipFiles <- list.files(path = ".", pattern = "\\\\.zip\$", full.names = TRUE, ignore.case = TRUE)
      if (length(zipFiles) > 0) {
        message("Unzipping PKC files from zip archive...")
        extracted <- unzip(zipFiles[1], exdir = ".")
        PKCFiles <- extracted[grep("\\\\.pkc\$", extracted, ignore.case = TRUE)]
      }
    }
    if (length(PKCFiles) == 0) {
      stop("Error: No PKC files found in the working directory.")
    }
    
    # Locate Sample Annotation File (Excel spreadsheet)
    SampleAnnotationFile <- list.files(path = ".", pattern = "\\\\.xlsx\$|\\\\.xls\$", full.names = TRUE, ignore.case = TRUE)
    if (length(SampleAnnotationFile) == 0) {
      stop("Error: No Excel sample annotation file (.xlsx or .xls) found in the working directory.")
    } else {
      SampleAnnotationFile <- SampleAnnotationFile[1] # Use the first matching file
    }
    
    # ==========================================
    # --- Execute Documented Workflow ---
    # ==========================================
    
    # Read raw data using readNanoStringGeoMxSet
    demoData <- suppressWarnings(readNanoStringGeoMxSet(
      dccFiles = DCCFiles, 
      pkcFiles = PKCFiles, 
      phenoDataFile = SampleAnnotationFile, 
      phenoDataSheet = "CW005", 
      phenoDataDccColName = "Sample_ID", 
      protocolDataColNames = c("aoi", "cell_line", "roi_rep", "pool_rep", "slide_rep")
    ))
    
    # Shift zero counts by one using shiftCountsOne
    demoData <- shiftCountsOne(demoData, useDALogic=TRUE)
    
    # Flag low-quality segments and probes
    demoData <- setSegmentQCFlags(demoData, qcCutoffs = list(percentSaturation = 45))
    demoData <- setBioProbeQCFlags(demoData)
    
    # Identify flagged low-quality ROIs and probes
    lowSaturation <- which(protocolData(demoData)[["QCFlags"]]\$LowSaturation)
    lowQCprobes <- which(featureData(demoData)[["QCFlags"]]\$LowProbeRatio | featureData(demoData)[["QCFlags"]]\$GlobalGrubbsOutlier)
    
    # Filter out flagged low-quality ROIs and probes
    # Using a robust tryCatch to handle cases where empty indices might cause standard R subsetting issues,
    # while keeping the exact documented function call intact.
    passedQC <- tryCatch({
      demoData[-lowQCprobes, -lowSaturation]
    }, error = function(e) {
      message("Standard negative indexing failed (likely due to empty QC flag vectors). Applying safe subsetting fallback.")
      tempData <- demoData
      if (length(lowQCprobes) > 0) {
        tempData <- tempData[-lowQCprobes, ]
      }
      if (length(lowSaturation) > 0) {
        tempData <- tempData[, -lowSaturation]
      }
      tempData
    })
    
    # Aggregate probe-level counts to target-level counts
    target_demoData <- aggregateCounts(passedQC)
    
    # Normalize target counts using normalize
    norm_target_demoData <- normalize(target_demoData, norm_method="quant", desiredQuantile = .75, toElt = "q_norm")
    
    # Coerce the normalized target-level object to Seurat
    demoSeurat <- as.Seurat(x = norm_target_demoData, normData = "q_norm")
    
    # Coerce the normalized target-level object to SpatialExperiment
    demoSPE <- as.SpatialExperiment(norm_target_demoData, normData = "q_norm")
    
    # ==========================================
    # --- Save Outputs and Results ---
    # ==========================================
    
    # Save RDS objects of the processed data
    saveRDS(demoData, "raw_demoData_GeoMxSet.rds")
    saveRDS(passedQC, "passedQC_GeoMxSet.rds")
    saveRDS(target_demoData, "target_demoData_GeoMxSet.rds")
    saveRDS(norm_target_demoData, "normalized_target_demoData_GeoMxSet.rds")
    saveRDS(demoSeurat, "demoSeurat.rds")
    saveRDS(demoSPE, "demoSPE.rds")
    
    # Export QC Flags as CSV tables
    write.csv(as.data.frame(protocolData(demoData)[["QCFlags"]]), "segment_qc_flags.csv", row.names = TRUE)
    write.csv(as.data.frame(featureData(demoData)[["QCFlags"]]), "probe_qc_flags.csv", row.names = TRUE)
    
    # Export Normalized Expression Matrix as CSV
    norm_exprs <- assayDataElement(norm_target_demoData, elt = "q_norm")
    write.csv(norm_exprs, "normalized_target_counts.csv", row.names = TRUE)
    
    message("Workflow completed successfully. Outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_GEOMXTOOLS_RNA_PREPROCESSING_AND_COERCION":',
        paste0('        geomxtools: ', as.character(packageVersion("geomxtools")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rna_preprocessing_and_coercion.csv versions.yml
    """
}

workflow BIOC_GEOMXTOOLS_RNA_PREPROCESSING_AND_COERCION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ DCCFiles, PKCFiles, SampleAnnotationFile ] ]

    main:
    BIOC_GEOMXTOOLS_RNA_PREPROCESSING_AND_COERCION(ch_input)

    emit:
    tables   = BIOC_GEOMXTOOLS_RNA_PREPROCESSING_AND_COERCION.out.tables
    plots    = BIOC_GEOMXTOOLS_RNA_PREPROCESSING_AND_COERCION.out.plots
    objects  = BIOC_GEOMXTOOLS_RNA_PREPROCESSING_AND_COERCION.out.objects
    versions = BIOC_GEOMXTOOLS_RNA_PREPROCESSING_AND_COERCION.out.versions
}
