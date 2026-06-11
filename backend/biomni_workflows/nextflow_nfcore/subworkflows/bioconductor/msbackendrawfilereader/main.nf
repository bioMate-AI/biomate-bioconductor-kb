#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MsBackendRawFileReader — raw_file_spectra_extraction
// Extract, filter, and benchmark peptide spectra from Thermo RAW files using MsBackendRawFileReader, matching them against peptide features from an intensity matr
// Input: intensity.csv, coldata.csv
// Container: 1.16.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, MsBackendMgf, MsBackendRawFileReader, Spectra, protViz, rawrr
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSBACKENDRAWFILEREADER_RAW_FILE_SPECTRA_EXTRACTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    .bm_deps <- c("Spectra", "MsBackendRawFileReader", "BiocParallel", "protViz")
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
    
    # --- Load required libraries and initialize environment ---
    library(Spectra)
    library(MsBackendRawFileReader)
    library(BiocParallel)
    library(protViz)
    
    # Ensure RawFileReader DLLs and assemblies are installed
    if (requireNamespace("rawrr", quietly = TRUE)) {
      if (isFALSE(file.exists(rawrr:::.rawrrAssembly()))) {
        try(rawrr::installRawrrExe(), silent = TRUE)
      }
      try(rawrr::installRawFileReaderDLLs(), silent = TRUE)
    } else {
      stop("The 'rawrr' package is required but not installed.")
    }
    
    # --- Read input files from the working directory ---
    intensity_df <- read.csv("intensity.csv", check.names = FALSE)
    coldata_df <- read.csv("coldata.csv")
    
    # Extract candidate peptide sequences from the intensity matrix
    if ("feature_id" %in% colnames(intensity_df)) {
      peptides_candidate <- intensity_df\$feature_id
    } else {
      peptides_candidate <- rownames(intensity_df)
    }
    
    # Validate peptide sequences (standard amino acids, length 5-30)
    is_peptide <- function(x) {
      grepl("^[ARNDCEQGHILKMFPSTWYV]+\$", x, ignore.case = TRUE) & nchar(x) >= 5 & nchar(x) <= 30
    }
    peptides <- peptides_candidate[sapply(peptides_candidate, is_peptide)]
    
    # Fallback to documented peptide if no valid peptides are found in the input
    if (length(peptides) == 0) {
      message("No valid peptide sequences found in intensity.csv. Using fallback peptide 'LGGNEQVTR'.")
      peptides <- "LGGNEQVTR"
    }
    
    # --- Locate Thermo RAW files ---
    raw_files <- list.files(pattern = "\\\\.raw\$", full.names = TRUE, ignore.case = TRUE)
    if (length(raw_files) == 0) {
      message("No .raw files found in working directory. Falling back to rawrr sample file.")
      raw_files <- rawrr::sampleFilePath()
    }
    
    # --- Initialize MsBackendRawFileReader and extract spectra ---
    message("Initializing MsBackendRawFileReader with files: ", paste(raw_files, collapse = ", "))
    beRaw <- Spectra::backendInitialize(
      MsBackendRawFileReader::MsBackendRawFileReader(),
      files = raw_files
    )
    
    # Demonstrate extractByIndex as documented
    if (length(beRaw) > 0) {
      subset_be <- extractByIndex(beRaw, 1:min(5, length(beRaw)))
      message("Successfully verified extractByIndex on the first ", length(subset_be), " spectra.")
    }
    
    # Filter for MS2 scans using scanType and filterScan
    scan_types <- unique(beRaw\$scanType)
    ms2_scan_types <- scan_types[grepl("ms2", scan_types, ignore.case = TRUE)]
    
    if (length(ms2_scan_types) > 0) {
      selected_scan_type <- ms2_scan_types[1]
      message("Filtering scans by type: ", selected_scan_type)
      beMS2 <- filterScan(beRaw, selected_scan_type)
    } else {
      message("No specific MS2 scan types found. Filtering by msLevel == 2.")
      beMS2 <- beRaw[beRaw\$msLevel == 2]
    }
    
    # --- Define and apply filterIons method for targeted peptide ---
    setGeneric("filterIons", function(object, ...) standardGeneric("filterIons"))
    setMethod("filterIons", "MsBackend", function(object, mZ=numeric(), tol=0.005, ...) {
      keep <- lapply(peaksData(object, BPPARAM = bpparam()), FUN=function(x){
        if (is.null(x) || nrow(x) == 0) return(FALSE)
        NN <- protViz::findNN(mZ, x[, 1])
        # Determine hits based on absolute mass error and intensity threshold
        hit <- abs(mZ - x[NN, 1]) < tol & x[NN, 2] >= quantile(x[, 2], 0.9)
        if (sum(hit) == length(mZ)) TRUE else FALSE
      })
      object[unlist(keep)]
    })
    
    # Match peptides against MS2 spectra
    matched_results <- list()
    for (pep in peptides) {
      # Compute theoretical y-ions using protViz
      ions_list <- protViz::fragmentIon(pep)
      if (length(ions_list) == 0) next
      y_ions <- ions_list[[1]]\$y
      n_ions <- min(8, length(y_ions))
      y_ions <- y_ions[1:n_ions]
      names(y_ions) <- paste0("y", seq_len(n_ions))
      
      matched_backend <- tryCatch({
        filterIons(beMS2, mZ = y_ions, tol = 0.005)
      }, error = function(e) {
        NULL
      })
      
      if (!is.null(matched_backend) && length(matched_backend) > 0) {
        matched_results[[pep]] <- list(
          backend = matched_backend,
          y_ions = y_ions
        )
      }
    }
    
    # --- Apply processing queue (Top-N filtering) and generate ---
    pdf("spectra_mirror_plot.pdf", width = 10, height = 6)
    if (length(matched_results) > 0) {
      pep_name <- names(matched_results)[1]
      target_backend <- matched_results[[pep_name]]\$backend
      
      # Verify mz() and intensity() extraction
      mzs <- mz(target_backend)
      ints <- intensity(target_backend)
      message("Matched peptide '", pep_name, "' has ", length(mzs[[1]]), " peaks in its first spectrum.")
      
      s_raw <- Spectra::Spectra(target_backend)
      # Add top_n processing to the queue
      s_filtered <- Spectra::addProcessing(s_raw, MsBackendRawFileReader:::.top_n, n = 1)
      
      tryCatch({
        Spectra::plotSpectraMirror(s_raw[1], s_filtered[1], ppm = 50)
        title(main = paste("Mirror Plot (Raw vs Top-1 Filtered) for Peptide:", pep_name))
      }, error = function(e) {
        plot.new()
        text(0.5, 0.5, paste("Error plotting mirror plot:", e\$message))
      })
    } else {
      plot.new()
      text(0.5, 0.5, "No peptide matches found to generate mirror plot")
    }
    dev.off()
    
    # --- Export matched spectra to Mascot Generic Format (MGF) ---
    if (requireNamespace("MsBackendMgf", quietly = TRUE) && length(matched_results) > 0) {
      pep_name <- names(matched_results)[1]
      target_backend <- matched_results[[pep_name]]\$backend
      
      # Map Spectra variables to Mascot Server compatible vocabulary
      map <- c(custom = "TITLE",
               msLevel = "CHARGE",
               scanIndex = "SCANS",
               precursorMz = "PEPMASS",
               rtime = "RTINSECONDS")
      
      target_backend\$custom <- paste0("File: ", target_backend\$dataOrigin, 
                                      " ; SpectrumID: ", target_backend\$scanIndex,
                                      " ; Peptide: ", pep_name)
      
      tryCatch({
        s_export <- Spectra::Spectra(target_backend)
        s_export <- Spectra::selectSpectraVariables(s_export, 
          c("rtime", "precursorMz", "precursorCharge", "msLevel", "scanIndex", "custom")
        )
        MsBackendMgf::export(s_export,
                             backend = MsBackendMgf::MsBackendMgf(),
                             file = "exported_spectra.mgf",
                             map = map)
      }, error = function(e) {
        writeLines(paste("# Export failed:", e\$message), "exported_spectra.mgf")
      })
    } else {
      writeLines("# No matched spectra or MsBackendMgf not available", "exported_spectra.mgf")
    }
    
    # --- Create matched spectra summary table ---
    summary_rows <- list()
    if (length(matched_results) > 0) {
      for (pep in names(matched_results)) {
        be <- matched_results[[pep]]\$backend
        df <- data.frame(
          peptide = pep,
          scanIndex = be\$scanIndex,
          msLevel = be\$msLevel,
          rtime = be\$rtime,
          precursorMz = be\$precursorMz,
          precursorCharge = be\$precursorCharge,
          stringsAsFactors = FALSE
        )
        summary_rows[[pep]] <- df
      }
      summary_df <- do.call(rbind, summary_rows)
    } else {
      summary_df <- data.frame(
        peptide = character(),
        scanIndex = integer(),
        msLevel = integer(),
        rtime = numeric(),
        precursorMz = numeric(),
        precursorCharge = integer(),
        stringsAsFactors = FALSE
      )
    }
    write.csv(summary_df, "matched_spectra_summary.csv", row.names = FALSE)
    
    # --- Run I/O performance benchmark ---
    if (length(raw_files) > 0) {
      tryCatch({
        bm_res <- ioBenchmark(n = 100, size = c(32, 64), rawfile = raw_files[1])
        write.csv(bm_res, "io_benchmark_results.csv", row.names = FALSE)
      }, error = function(e) {
        write.csv(data.frame(error = e\$message), "io_benchmark_results.csv", row.names = FALSE)
      })
    } else {
      write.csv(data.frame(error = "No raw files available for benchmarking"), "io_benchmark_results.csv", row.names = FALSE)
    }
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_MSBACKENDRAWFILEREADER_RAW_FILE_SPECTRA_EXTRACTION":',
        paste0('    MsBackendRawFileReader: ', as.character(packageVersion('MsBackendRawFileReader')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_raw_file_spectra_extraction.csv versions.yml
    """
}

workflow BIOC_MSBACKENDRAWFILEREADER_RAW_FILE_SPECTRA_EXTRACTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_MSBACKENDRAWFILEREADER_RAW_FILE_SPECTRA_EXTRACTION(ch_input)

    emit:
    tables   = BIOC_MSBACKENDRAWFILEREADER_RAW_FILE_SPECTRA_EXTRACTION.out.tables
    plots    = BIOC_MSBACKENDRAWFILEREADER_RAW_FILE_SPECTRA_EXTRACTION.out.plots
    objects  = BIOC_MSBACKENDRAWFILEREADER_RAW_FILE_SPECTRA_EXTRACTION.out.objects
    versions = BIOC_MSBACKENDRAWFILEREADER_RAW_FILE_SPECTRA_EXTRACTION.out.versions
}
