#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GeomxTools — protein_geomx_workflow
// Read, quality control, evaluate signal, check concordance, and normalize GeoMx protein data.
// Input: DCCFiles, PKCFiles, SampleAnnotationFile
// Container: quay.io/biocontainers/bioconductor-geomxtools:3.14.0--r45hdfd78af_0
// R packages: GeomxTools, readxl
// Bioconductor: 3.20 | R: 4.4
// Requires: GeomxTools, readxl
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read raw protein data using readNanoStringGeoMxSet with analyte = "protein"
//  * 2. [Core Analysis] Flag low-quality segments using setSegmentQCFlags
//  * 3. [Core Analysis] Filter out flagged segments
//  * 4. [Core Analysis] Identify housekeepers and negative controls using hkNames and iggNames
//  * 5. [Visualization & Output] Perform target QC and visualize signal using qcProteinSignal and qcProteinSignalNames
//  * 6. [Visualization & Output] Plot concordance of negative controls using plotConcordance
//  * 7. [Visualization & Output] Compute and plot concordance of normalization factors using computeNormalizationFactors and plotNormFactorConcordance
//  * 8. [Core Analysis] Normalize protein data using housekeeper, background, or quantile methods via normalize

nextflow.enable.dsl = 2

process BIOC_GEOMXTOOLS_PROTEIN_GEOMX_WORKFLOW {
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
    .bm_deps <- c("GeomxTools", "readxl")
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
            library(GeomxTools)
            library(readxl)
            
            # 1. Locate User Input Files in the Working Directory
            DCCFiles <- list.files(pattern = "\\\\.dcc\$", full.names = TRUE)
            PKCFiles <- list.files(pattern = "\\\\.pkc\$", full.names = TRUE)
            SampleAnnotationFile <- list.files(pattern = "\\\\.xlsx\$", full.names = TRUE)[1]
            
            # Validate inputs
            if (length(DCCFiles) == 0) {
              stop("Error: No .dcc files found in the working directory.")
            }
            if (length(PKCFiles) == 0) {
              stop("Error: No .pkc files found in the working directory.")
            }
            if (is.na(SampleAnnotationFile) || !file.exists(SampleAnnotationFile)) {
              stop("Error: No .xlsx sample annotation file found in the working directory.")
            }
            
            # Dynamically determine sheet and DCC column name to avoid hardcoding
            sheet_name <- excel_sheets(SampleAnnotationFile)[1]
            anno_cols_raw <- colnames(read_xlsx(SampleAnnotationFile, sheet = sheet_name))
            dcc_col <- if ("Sample_ID" %in% anno_cols_raw) "Sample_ID" else anno_cols_raw[1]
            
            # 2. Read raw protein data
            proteinData <- suppressWarnings(readNanoStringGeoMxSet(
              dccFiles = DCCFiles,
              pkcFiles = PKCFiles,
              phenoDataFile = SampleAnnotationFile,
              phenoDataSheet = sheet_name,
              phenoDataDccColName = dcc_col,
              protocolDataColNames = anno_cols_raw,
              configFile = NULL,
              analyte = "protein",
              phenoDataColPrefix = "",
              experimentDataColNames = NULL
            ))
            
            # Dynamically determine metadata columns for downstream steps
            obj_cols <- names(sData(proteinData))
            plot_factor <- if ("Tissue" %in% obj_cols) "Tissue" else obj_cols[2]
            
            area_col <- grep("area|size", obj_cols, ignore.case = TRUE, value = TRUE)[1]
            if (is.na(area_col)) area_col <- obj_cols[min(3, length(obj_cols))]
            
            nuclei_col <- grep("nuclei", obj_cols, ignore.case = TRUE, value = TRUE)[1]
            if (is.na(nuclei_col)) nuclei_col <- obj_cols[min(4, length(obj_cols))]
            
            # 3. Flag low-quality segments
            proteinData <- setSegmentQCFlags(
              proteinData,
              qcCutoffs = list(
                percentSaturation = 45,
                minSegmentReads = 1000,
                percentAligned = 80,
                minNegativeCount = 10,
                maxNTCCount = 60,
                minNuclei = 20,
                minArea = 16000
              )
            )
            
            # 4. Filter out flagged segments
            QCResultsIndex <- which(apply(protocolData(proteinData)[["QCFlags"]], 1L, function(x) sum(x) == 0L))
            passedQC <- proteinData[, QCResultsIndex]
            
            # 5. Identify housekeepers and negative controls
            hk.names <- hkNames(passedQC)
            igg.names <- iggNames(passedQC)
            
            # 6. Perform target QC and visualize signal (saving plots to PDF)
            pdf("protein_geomx_qc_plots.pdf", width = 11, height = 8.5)
            
            fig <- qcProteinSignal(object = passedQC, neg.names = igg.names)
            if (is.function(fig)) {
              print(fig())
            } else {
              print(fig)
            }
            proteinOrder <- qcProteinSignalNames(object = passedQC, neg.names = igg.names)
            
            # 7. Plot concordance of negative controls
            print(plotConcordance(object = passedQC, targetList = igg.names, plotFactor = plot_factor))
            
            # 8. Compute and plot concordance of normalization factors
            normfactors <- computeNormalizationFactors(object = passedQC, area = area_col, nuclei = nuclei_col)
            print(plotNormFactorConcordance(object = passedQC, plotFactor = plot_factor, normfactors = normfactors))
            
            dev.off()
            
            # 9. Normalize protein data
            normalizedData <- normalize(passedQC, norm_method="hk", toElt = "hk_norm")
            normalizedData <- normalize(normalizedData, norm_method="background", toElt = "background_norm")
            normalizedData <- normalize(normalizedData, norm_method="quant", desiredQuantile = .75, toElt = "q_norm")
            
            # 10. Save meaningful results
            # Save the full and QC-passed GeoMxSet objects
            saveRDS(normalizedData, "proteinData_normalized.rds")
            saveRDS(passedQC, "proteinData_passedQC.rds")
            
            # Export normalized expression matrices
            write.csv(as.data.frame(assayDataElement(normalizedData, "hk_norm")), "expression_hk_norm.csv", row.names = TRUE)
            write.csv(as.data.frame(assayDataElement(normalizedData, "background_norm")), "expression_background_norm.csv", row.names = TRUE)
            write.csv(as.data.frame(assayDataElement(normalizedData, "q_norm")), "expression_q_norm.csv", row.names = TRUE)
            write.csv(as.data.frame(assayDataElement(normalizedData, "exprs")), "expression_raw.csv", row.names = TRUE)
            
            # Export QC Flags (from the unfiltered object to retain all segments' flags)
            qc_flags <- as.data.frame(protocolData(proteinData)[["QCFlags"]])
            write.csv(qc_flags, "segment_qc_flags.csv", row.names = TRUE)
            
            # Export normalization factors
            write.csv(as.data.frame(normfactors), "normalization_factors.csv", row.names = TRUE)
            
            cat("Pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_GEOMXTOOLS_PROTEIN_GEOMX_WORKFLOW":',
        paste0('    GeomxTools: ', as.character(packageVersion('GeomxTools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_protein_geomx_workflow.csv versions.yml
    """
}

workflow BIOC_GEOMXTOOLS_PROTEIN_GEOMX_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ DCCFiles, PKCFiles, SampleAnnotationFile ] ]

    main:
    BIOC_GEOMXTOOLS_PROTEIN_GEOMX_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_GEOMXTOOLS_PROTEIN_GEOMX_WORKFLOW.out.tables
    plots    = BIOC_GEOMXTOOLS_PROTEIN_GEOMX_WORKFLOW.out.plots
    objects  = BIOC_GEOMXTOOLS_PROTEIN_GEOMX_WORKFLOW.out.objects
    versions = BIOC_GEOMXTOOLS_PROTEIN_GEOMX_WORKFLOW.out.versions
}
