#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: adacgh2 — large_text_file_cutting
// Process extremely large text files by cutting them into single-column files and reading them in parallel to ff objects.
// Input: inputEx.txt
// Container: quay.io/biocontainers/bioconductor-adacgh2:2.50.0--r45h01b2380_1
// R packages: ADaCGH2, ff
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ADACGH2_LARGE_TEXT_FILE_CUTTING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-adacgh2:2.50.0--r45h01b2380_1"

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
    .bm_deps <- c("ADaCGH2", "ff")
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
    library(ADaCGH2)
    library(ff)
    
    # Define the input file from the working directory
    input_file <- "inputEx.txt"
    
    # Ensure the input file exists
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    # Get the absolute path of the input file before changing directories
    fnametxt <- normalizePath(input_file, mustWork = TRUE)
    
    # Clean up any pre-existing cuttedFile directory to avoid conflicts
    if (file.exists("cuttedFile")) {
      unlink("cuttedFile", recursive = TRUE)
    }
    dir.create("cuttedFile")
    
    # --- Cut the large text file into single-column files ---
    setwd("cuttedFile")
    cutFile(fnametxt, 1, 2, 3, sep = "\t", mc.cores = 2)
    cuttedFile.dir <- getwd()
    setwd("../")
    
    # --- Read the directory of cut files in parallel to ff objects ---
    inputToADaCGH(ff.or.RAM = "ff",
                  path = cuttedFile.dir,
                  verbose = TRUE,
                  mc.cores = 2)
    
    # --- Run parallelized segmentation ---
    haar.ff.fork <- pSegmentHaarSeg("cghData.RData",
                                    "chromData.RData",
                                     merging = "MAD",
                                    typeParall = "fork",
                                    mc.core = 2)
    
    # Save the segmentation output object
    save(haar.ff.fork, file = "haar.ff.fork.RData", compress = FALSE)
    
    # --- Plot results ---
    pChromPlot(outRDataName = "haar.ff.fork.RData",
               cghRDataName = "cghData.RData",
               chromRDataName = "chromData.RData",
               posRDataName = "posData.RData",
               probenamesRDataName = "probeNames.RData",
               imgheight = 350,
               typeParall = "fork",
               mc.cores = 2)
    
    # Export meaningful results to accessible CSV tables
    if (exists("haar.ff.fork")) {
      # Open ff objects if they are closed
      lapply(haar.ff.fork, open)
      
      # Extract smoothed values and states
      smoothed_values <- as.data.frame(haar.ff.fork\$outSmoothed[,])
      states <- as.data.frame(haar.ff.fork\$outState[,])
      
      # Write to CSV
      write.csv(smoothed_values, "segmented_smoothed_values.csv", row.names = FALSE)
      write.csv(states, "segmented_states.csv", row.names = FALSE)
    }

    writeLines(c(
        '"BIOC_ADACGH2_LARGE_TEXT_FILE_CUTTING":',
        paste0('        adacgh2: ', as.character(packageVersion("adacgh2")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_large_text_file_cutting.csv versions.yml
    """
}

workflow BIOC_ADACGH2_LARGE_TEXT_FILE_CUTTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ inputEx.txt ] ]

    main:
    BIOC_ADACGH2_LARGE_TEXT_FILE_CUTTING(ch_input)

    emit:
    tables   = BIOC_ADACGH2_LARGE_TEXT_FILE_CUTTING.out.tables
    plots    = BIOC_ADACGH2_LARGE_TEXT_FILE_CUTTING.out.plots
    objects  = BIOC_ADACGH2_LARGE_TEXT_FILE_CUTTING.out.objects
    versions = BIOC_ADACGH2_LARGE_TEXT_FILE_CUTTING.out.versions
}
