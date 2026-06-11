#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: geomxtools — protein_preprocessing
// Read, QC, filter, and normalize GeoMx protein data.
// Input: DCCFiles, PKCFiles, SampleAnnotationFile
// Container: quay.io/biocontainers/bioconductor-geomxtools:3.14.0--r45hdfd78af_0
// R packages: Biobase, GeomxTools, NanoStringNCTools
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GEOMXTOOLS_PROTEIN_PREPROCESSING {
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
    .bm_deps <- c("Biobase", "GeomxTools", "NanoStringNCTools")
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
    
    # Load required Bioconductor and CRAN libraries
    library(GeomxTools)
    library(NanoStringNCTools)
    library(Biobase)
    
    # ==========================================
    # 1. Identify and Validate User Input Files
    # ==========================================
    
    # Locate DCC files in the working directory
    DCCFiles <- list.files(pattern = "\\\\.dcc\$", ignore.case = TRUE, full.names = TRUE)
    if (length(DCCFiles) == 0) {
      stop("Error: No DCC files found in the working directory.")
    }
    
    # Locate PKC files in the working directory
    PKCFiles <- list.files(pattern = "\\\\.pkc\$", ignore.case = TRUE, full.names = TRUE)
    if (length(PKCFiles) == 0) {
      # Check if there is a zipped archive of PKCs and extract it
      zipFiles <- list.files(pattern = "pkcs\\\\.zip|.*pkc.*\\\\.zip", ignore.case = TRUE, full.names = TRUE)
      if (length(zipFiles) > 0) {
        message("Extracting PKC files from zip archive...")
        PKCFiles <- unzip(zipFiles[1])
      } else {
        stop("Error: No PKC files (.pkc) or pkcs.zip found in the working directory.")
      }
    }
    
    # Locate SampleAnnotationFile (Excel spreadsheet)
    SampleAnnotationFile <- list.files(pattern = "annotation.*\\\\.xlsx\$|annotation.*\\\\.xls\$", ignore.case = TRUE, full.names = TRUE)[1]
    if (is.na(SampleAnnotationFile)) {
      SampleAnnotationFile <- list.files(pattern = "\\\\.xlsx\$|\\\\.xls\$", ignore.case = TRUE, full.names = TRUE)[1]
    }
    if (is.na(SampleAnnotationFile)) {
      stop("Error: No Excel sample annotation file (.xlsx or .xls) found in the working directory.")
    }
    
    message("Using the following input files:")
    message("- DCC Files Count: ", length(DCCFiles))
    message("- PKC Files: ", paste(basename(PKCFiles), collapse = ", "))
    message("- Annotation File: ", basename(SampleAnnotationFile))
    
    # ==========================================
    # 2. Execute GeoMx Protein Preprocessing
    # ==========================================
    
    # Step 1: Read raw protein data
    message("Reading GeoMx protein data...")
    proteinData <- suppressWarnings(readNanoStringGeoMxSet(
      dccFiles = DCCFiles,
      pkcFiles = PKCFiles,
      phenoDataFile = SampleAnnotationFile,
      phenoDataSheet = "Annotations",
      phenoDataDccColName = "Sample_ID",
      protocolDataColNames = c("Tissue", "Segment_Type", "ROI.Size"),
      configFile = NULL,
      analyte = "protein",
      phenoDataColPrefix = "",
      experimentDataColNames = NULL
    ))
    
    # Step 2: Flag and remove low-quality ROIs
    message("Performing Segment QC...")
    proteinData <- setSegmentQCFlags(
      proteinData,
      qcCutoffs = list(
        percentSaturation = 45,
        minSegmentReads = 1000,
        percentAligned = 80,
        minNegativeCount = 10,
        maxNTCCount = 60,
        minNuclei = 16000,
        minArea = 20
      )
    )
    
    # Identify and filter low saturation segments
    qc_flags <- as.data.frame(protocolData(proteinData)[["QCFlags"]])
    lowSaturation <- which(qc_flags["LowSaturation"] == TRUE)
    
    if (length(lowSaturation) > 0) {
      passedQC <- proteinData[, -lowSaturation]
      message(sprintf("Removed %d low-saturation segment(s).", length(lowSaturation)))
    } else {
      passedQC <- proteinData
      message("No segments flagged for low saturation.")
    }
    
    # Step 3: Identify and filter low-signal proteins
    message("Identifying target names and control probes...")
    hk.names <- hkNames(proteinData)
    igg.names <- iggNames(proteinData)
    
    # Open PDF device to capture all diagnostic and concordance plots
    pdf("protein_preprocessing_plots.pdf", width = 10, height = 8)
    
    message("Generating QC protein signal plots...")
    fig <- qcProteinSignal(object = proteinData, neg.names = igg.names)
    if (is.function(fig)) {
      fig()
    }
    
    proteinOrder <- qcProteinSignalNames(object = proteinData, neg.names = igg.names)
    
    # Step 4: Evaluate normalization options using concordance plots
    message("Generating concordance plots...")
    plotConcordance(object = proteinData, targetList = igg.names, plotFactor = "Tissue")
    
    normfactors <- computeNormalizationFactors(object = proteinData, area = "AOI.Size.um2", nuclei = "Nuclei.Counts")
    
    plotNormFactorConcordance(object = proteinData, plotFactor = "Tissue", normfactors = normfactors)
    
    # Close the PDF plotting device
    dev.off()
    message("Plots saved to 'protein_preprocessing_plots.pdf'.")
    
    # Step 5: Normalize protein data using multiple methods
    message("Normalizing protein data...")
    proteinData <- normalize(proteinData, norm_method = "hk", toElt = "hk_norm")
    proteinData <- normalize(proteinData, norm_method = "neg", toElt = "neg_norm")
    proteinData <- normalize(proteinData, norm_method = "quant", desiredQuantile = .75, toElt = "q_norm")
    
    # ==========================================
    # 3. Save Pipeline Outputs
    # ==========================================
    
    message("Saving output files...")
    
    # Save complete S4 objects
    saveRDS(proteinData, "proteinData_normalized.rds")
    saveRDS(passedQC, "proteinData_passedQC.rds")
    
    # Save QC flags and normalization factors
    write.csv(qc_flags, "segment_qc_flags.csv", row.names = TRUE)
    write.csv(as.data.frame(normfactors), "normalization_factors.csv", row.names = TRUE)
    
    # Save raw and normalized expression matrices
    write.csv(as.data.frame(exprs(proteinData)), "expression_raw.csv", row.names = TRUE)
    
    if ("hk_norm" %in% assayDataElementNames(proteinData)) {
      write.csv(as.data.frame(assayDataElement(proteinData, "hk_norm")), "expression_hk_norm.csv", row.names = TRUE)
    }
    if ("neg_norm" %in% assayDataElementNames(proteinData)) {
      write.csv(as.data.frame(assayDataElement(proteinData, "neg_norm")), "expression_neg_norm.csv", row.names = TRUE)
    }
    if ("q_norm" %in% assayDataElementNames(proteinData)) {
      write.csv(as.data.frame(assayDataElement(proteinData, "q_norm")), "expression_q_norm.csv", row.names = TRUE)
    }
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_GEOMXTOOLS_PROTEIN_PREPROCESSING":',
        paste0('        geomxtools: ', as.character(packageVersion("geomxtools")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_protein_preprocessing.csv versions.yml
    """
}

workflow BIOC_GEOMXTOOLS_PROTEIN_PREPROCESSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ DCCFiles, PKCFiles, SampleAnnotationFile ] ]

    main:
    BIOC_GEOMXTOOLS_PROTEIN_PREPROCESSING(ch_input)

    emit:
    tables   = BIOC_GEOMXTOOLS_PROTEIN_PREPROCESSING.out.tables
    plots    = BIOC_GEOMXTOOLS_PROTEIN_PREPROCESSING.out.plots
    objects  = BIOC_GEOMXTOOLS_PROTEIN_PREPROCESSING.out.objects
    versions = BIOC_GEOMXTOOLS_PROTEIN_PREPROCESSING.out.versions
}
