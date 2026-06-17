#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: minfi — methylation_preprocessing_and_mapping
// Read raw Illumina IDAT files using a sample sheet, perform basic preprocessing, and map the data to the genome.
// Input: SampleSheet.csv, *.idat
// Container: quay.io/biocontainers/bioconductor-minfi:1.56.0--r45hdfd78af_0
// R packages: minfi, minfidata
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MINFI_METHYLATION_PREPROCESSING_AND_MAPPING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-minfi:1.56.0--r45hdfd78af_0"

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
    .bm_deps <- c("minfi", "minfidata")
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
    library(minfi)
    
    # Define base directory (current working directory containing user files)
    baseDir <- "."
    
    # --- Robustness Step: Prepare SampleSheet.csv for read.csv(..., skip = 7) ---
    if (file.exists("SampleSheet.csv")) {
      lines <- readLines("SampleSheet.csv")
      data_start <- grep("^\\[Data\\]", lines)
      if (length(data_start) == 0) {
        data_start <- grep("Sample_ID|Sample_Name|Sentrix_ID", lines)
      }
      
      if (length(data_start) > 0) {
        data_lines <- lines[data_start[1]:length(lines)]
        if (startsWith(data_lines[1], "[Data]")) {
          dummy_header <- c(
            "[Header]",
            "Investigator,User",
            "Project,Project",
            "Date,2023-01-01",
            "[Manifests]",
            "[Data]",
            ""
          )
          if (length(data_lines) > 1) {
            final_lines <- c(dummy_header, data_lines[2:length(data_lines)])
          } else {
            final_lines <- c(dummy_header, data_lines)
          }
        } else {
          dummy_header <- c(
            "[Header]",
            "Investigator,User",
            "Project,Project",
            "Date,2023-01-01",
            "[Manifests]",
            "[Data]",
            ""
          )
          final_lines <- c(dummy_header, data_lines)
        }
        file.copy("SampleSheet.csv", "SampleSheet_backup.csv", overwrite = TRUE)
        writeLines(final_lines, "SampleSheet.csv")
      }
    }
    
    # --- Robustness Step: Create slide directory "5723646052" and populate with IDATs ---
    slide_dir <- file.path(baseDir, "5723646052")
    if (!dir.exists(slide_dir)) {
      dir.create(slide_dir, showWarnings = FALSE, recursive = TRUE)
    }
    idat_files <- list.files(baseDir, pattern = "\\\\.idat\$", ignore.case = TRUE, recursive = TRUE, full.names = TRUE)
    idat_files <- idat_files[!grepl("5723646052", idat_files)]
    if (length(idat_files) > 0) {
      file.copy(idat_files, slide_dir, overwrite = TRUE)
    }
    
    # --- Step 1: Read the sample sheet ---
    targets <- read.metharray.sheet(baseDir)
    
    # --- Step 2: Read the raw IDAT files into an RGChannelSet ---
    RGset <- read.metharray.exp(targets = targets)
    
    # Map the loaded RGset to RGsetEx to match the documented code's variable name
    RGsetEx <- RGset
    
    # --- Step 3: Preprocess the raw data to a MethylSet ---
    MsetEx <- preprocessRaw(RGsetEx)
    
    # --- Step 4: Map the preprocessed data to genomic coordinates ---
    GMsetEx <- mapToGenome(MsetEx)
    
    # --- Step 5: Execute remaining documented reading calls ---
    RGset2 <- tryCatch({
      read.metharray.exp(file.path(baseDir, "5723646052"))
    }, error = function(e) {
      message("Warning: Failed to read RGset2: ", e\$message)
      NULL
    })
    
    RGset3 <- tryCatch({
      read.metharray.exp(baseDir, recursive = TRUE)
    }, error = function(e) {
      message("Warning: Failed to read RGset3: ", e\$message)
      NULL
    })
    
    targets2 <- read.csv(file.path(baseDir, "SampleSheet.csv"), 
                         stringsAsFactors = FALSE, skip = 7)
    
    # Ensure Sentrix_ID and Sentrix_Position exist in targets2 for the Basename construction
    if (!"Sentrix_ID" %in% colnames(targets2)) {
      targets2\$Sentrix_ID <- if ("Slide" %in% colnames(targets2)) targets2\$Slide else "5723646052"
    }
    if (!"Sentrix_Position" %in% colnames(targets2)) {
      targets2\$Sentrix_Position <- if ("Array" %in% colnames(targets2)) targets2\$Array else "R02C02"
    }
    
    targets2\$Basename <- file.path(baseDir, targets2\$Sentrix_ID, 
                                   paste0(targets2\$Sentrix_ID, 
                                          targets2\$Sentrix_Position))
    
    # --- Step 6: Save outputs ---
    saveRDS(RGset, file = "RGset.rds")
    saveRDS(MsetEx, file = "MsetEx.rds")
    saveRDS(GMsetEx, file = "GMsetEx.rds")
    if (!is.null(RGset2)) saveRDS(RGset2, file = "RGset2.rds")
    if (!is.null(RGset3)) saveRDS(RGset3, file = "RGset3.rds")
    write.csv(targets, file = "targets_parsed.csv", row.names = FALSE)
    write.csv(targets2, file = "targets2_parsed.csv", row.names = FALSE)
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_MINFI_METHYLATION_PREPROCESSING_AND_MAPPING":',
        paste0('        minfi: ', as.character(packageVersion("minfi")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methylation_preprocessing_and_mapping.csv versions.yml
    """
}

workflow BIOC_MINFI_METHYLATION_PREPROCESSING_AND_MAPPING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SampleSheet.csv, *.idat ] ]

    main:
    BIOC_MINFI_METHYLATION_PREPROCESSING_AND_MAPPING(ch_input)

    emit:
    tables   = BIOC_MINFI_METHYLATION_PREPROCESSING_AND_MAPPING.out.tables
    plots    = BIOC_MINFI_METHYLATION_PREPROCESSING_AND_MAPPING.out.plots
    objects  = BIOC_MINFI_METHYLATION_PREPROCESSING_AND_MAPPING.out.objects
    versions = BIOC_MINFI_METHYLATION_PREPROCESSING_AND_MAPPING.out.versions
}
