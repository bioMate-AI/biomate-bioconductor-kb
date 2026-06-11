#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: anota — translational_efficiency_analysis
// Perform quality control, test regression assumptions, and identify significantly translationally regulated genes using APV.
// Input: dataT, dataP, phenoVec
// Container: quay.io/biocontainers/bioconductor-anota:1.58.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: anota
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Perform quality control of influential data points and interactions using anotaPerformQc
//  * 2. [Core Analysis] Assess residual normality using anotaResidOutlierTest
//  * 3. [Core Analysis] Identify significantly translationally regulated genes using anotaGetSigGenes
//  * 4. [Visualization & Output] Filter and plot significant genes using anotaPlotSigGenes

nextflow.enable.dsl = 2

process BIOC_ANOTA_TRANSLATIONAL_EFFICIENCY_ANALYSIS {
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
    .bm_deps <- c("anota")
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
        
        # Load required library
        library("anota")
        
        # Helper function to find and read matrix/data frame inputs
        find_and_read_matrix <- function(name) {
          extensions <- c("", ".csv", ".tsv", ".txt", ".rds")
          for (ext in extensions) {
            file_path <- paste0(name, ext)
            if (file.exists(file_path)) {
              if (ext == ".rds") {
                return(as.matrix(readRDS(file_path)))
              } else {
                # Try reading as CSV/TSV
                df <- tryCatch({
                  read.csv(file_path, row.names = 1, check.names = FALSE)
                }, error = function(e) {
                  read.delim(file_path, row.names = 1, check.names = FALSE)
                })
                return(as.matrix(df))
              }
            }
          }
          stop(paste("Required input file for", name, "not found in the working directory."))
        }
        
        # Helper function to find and read vector inputs
        find_and_read_vector <- function(name) {
          extensions <- c("", ".csv", ".tsv", ".txt", ".rds")
          for (ext in extensions) {
            file_path <- paste0(name, ext)
            if (file.exists(file_path)) {
              if (ext == ".rds") {
                return(as.character(unlist(readRDS(file_path))))
              } else {
                lines <- readLines(file_path)
                if (length(lines) == 1) {
                  parts <- strsplit(lines, "[,\\t]")[[1]]
                  return(parts)
                } else {
                  df <- read.table(file_path, header = FALSE, sep = "", stringsAsFactors = FALSE)
                  if (ncol(df) > 1 && nrow(df) == 1) {
                    return(as.character(unlist(df)))
                  } else {
                    return(as.character(df[[1]]))
                  }
                }
              }
            }
          }
          stop(paste("Required input file for", name, "not found in the working directory."))
        }
        
        # Read user inputs
        raw_dataT <- find_and_read_matrix("dataT")
        raw_dataP <- find_and_read_matrix("dataP")
        anotaPhenoVec <- find_and_read_vector("phenoVec")
        
        # Align columns between dataT and dataP
        common_cols <- intersect(colnames(raw_dataT), colnames(raw_dataP))
        if (length(common_cols) == 0) {
          # Fallback to positional alignment if no matching column names
          common_cols <- 1:min(ncol(raw_dataT), ncol(raw_dataP))
          raw_dataT <- raw_dataT[, common_cols, drop = FALSE]
          raw_dataP <- raw_dataP[, common_cols, drop = FALSE]
        } else {
          raw_dataT <- raw_dataT[, common_cols, drop = FALSE]
          raw_dataP <- raw_dataP[, common_cols, drop = FALSE]
        }
        
        # Align phenoVec length with the number of columns
        if (length(anotaPhenoVec) != ncol(raw_dataT)) {
          if (length(anotaPhenoVec) > ncol(raw_dataT)) {
            anotaPhenoVec <- anotaPhenoVec[1:ncol(raw_dataT)]
          } else {
            stop("phenoVec length is shorter than the number of samples in dataT/dataP.")
          }
        }
        
        anotaDataT <- raw_dataT
        anotaDataP <- raw_dataP
        
        # Open PDF device to capture all diagnostic and results plots
        pdf("anota_analysis_plots.pdf", width = 10, height = 8)
        
        # 1. Perform quality control of influential data points and interactions
        anotaQcOut <- anotaPerformQc(
          dataT = anotaDataT,
          dataP = anotaDataP,
          phenoVec = anotaPhenoVec,
          nDfbSimData = 500,
          useProgBar = FALSE
        )
        
        # 2. Assess residual normality
        anotaResidOut <- anotaResidOutlierTest(
          anotaQcObj = anotaQcOut,
          useProgBar = FALSE
        )
        
        # 3. Identify significantly translationally regulated genes using APV
        anotaSigOut <- anotaGetSigGenes(
          dataT = anotaDataT,
          dataP = anotaDataP,
          phenoVec = anotaPhenoVec,
          anotaQcObj = anotaQcOut,
          useRVM = FALSE,
          useProgBar = FALSE
        )
        
        # 4. Filter and plot significant genes (wrapped in tryCatch in case no genes pass thresholds)
        anotaSelected <- tryCatch({
          anotaPlotSigGenes(
            anotaSigObj = anotaSigOut,
            selContr = 1,
            maxP = 0.1,
            minSlope = (-0.5),
            maxSlope = 1.5,
            selDeltaPT = 0.5
          )
        }, error = function(e) {
          message("Warning: anotaPlotSigGenes failed or no significant genes met the filtering criteria. Error: ", e\$message)
          NULL
        })
        
        # Close PDF device
        dev.off()
        
        # Save pipeline outputs to disk
        saveRDS(anotaQcOut, "anotaQcOut.rds")
        saveRDS(anotaResidOut, "anotaResidOut.rds")
        saveRDS(anotaSigOut, "anotaSigOut.rds")
        
        if (!is.null(anotaSelected)) {
          saveRDS(anotaSelected, "anotaSelected.rds")
          
          # anotaPlotSigGenes returns a list containing selectedData and selectedRvmData
          if ("selectedData" %in% names(anotaSelected)) {
            write.csv(anotaSelected\$selectedData, "anotaSelected.csv", row.names = TRUE)
          } else {
            write.csv(anotaSelected, "anotaSelected.csv", row.names = TRUE)
          }
        }

    writeLines(c(
        '"BIOC_ANOTA_TRANSLATIONAL_EFFICIENCY_ANALYSIS":',
        paste0('    anota: ', as.character(packageVersion('anota')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_translational_efficiency_analysis.csv versions.yml
    """
}

workflow BIOC_ANOTA_TRANSLATIONAL_EFFICIENCY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dataT, dataP, phenoVec ] ]

    main:
    BIOC_ANOTA_TRANSLATIONAL_EFFICIENCY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ANOTA_TRANSLATIONAL_EFFICIENCY_ANALYSIS.out.tables
    plots    = BIOC_ANOTA_TRANSLATIONAL_EFFICIENCY_ANALYSIS.out.plots
    objects  = BIOC_ANOTA_TRANSLATIONAL_EFFICIENCY_ANALYSIS.out.objects
    versions = BIOC_ANOTA_TRANSLATIONAL_EFFICIENCY_ANALYSIS.out.versions
}
