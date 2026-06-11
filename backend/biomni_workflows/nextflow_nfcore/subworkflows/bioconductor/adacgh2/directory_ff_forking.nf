#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ADaCGH2 — directory_ff_forking
// Optimize the analysis of extremely large datasets by splitting the input file into single-column files, reading them in parallel into ff objects, and segmenting
// Input: inputEx.txt
// Container: quay.io/biocontainers/bioconductor-adacgh2:2.50.0--r45h01b2380_1
// R packages: ADaCGH2, ff
// Bioconductor: 3.20 | R: 4.4
// Requires: ADaCGH2, ff
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Split the large text file into single-column files
//  * 2. [Input & Preparation] Read the directory of split files into ff objects
//  * 3. [Core Analysis] Run parallelized HaarSeg segmentation using forking
//  * 4. [Visualization & Output] Save the segmentation results and plot them

nextflow.enable.dsl = 2

process BIOC_ADACGH2_DIRECTORY_FF_FORKING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
    library(ADaCGH2)
    library(ff)
    
    # Define the input file from the working directory
    input_file <- "inputEx.txt"
    
    if (!file.exists(input_file)) {
      stop(paste("Required input file", input_file, "is missing from the working directory."))
    }
    
    # Get the absolute path of the input file before changing directories
    fnametxt <- normalizePath(input_file)
    
    # Create a directory for the split single-column files
    cut_dir <- "cuttedFile"
    if (!file.exists(cut_dir)) {
      dir.create(cut_dir)
    }
    
    # Change directory to perform the file splitting
    setwd(cut_dir)
    
    # 1. Split the large text file into single-column files
    # Using the exact documented function and arguments
    cutFile(fnametxt, 1, 2, 3, sep = "\t", mc.cores = 2)
    
    # Save the path of the directory containing the split files
    cuttedFile.dir <- getwd()
    
    # Return to the parent directory
    setwd("../")
    
    # 2. Read the directory of split files into ff objects
    # Using the exact documented function and arguments
    inputToADaCGH(ff.or.RAM = "ff",
                  path = cuttedFile.dir,
                  verbose = TRUE,
                  mc.cores = 2)
    
    # 3. Run parallelized HaarSeg segmentation using forking
    # Using the exact documented function and arguments
    haar.ff.fork <- pSegmentHaarSeg("cghData.RData",
                                    "chromData.RData",
                                     merging = "MAD",
                                    typeParall = "fork",
                                    mc.core = 2)
    
    # 4. Save the segmentation results
    # Using the exact documented function and arguments
    save(haar.ff.fork, file = "haar.ff.fork.RData", compress = FALSE)
    
    # 5. Plot the results
    # Using the exact documented function and arguments
    pChromPlot(outRDataName = "haar.ff.fork.RData",
               cghRDataName = "cghData.RData",
               chromRDataName = "chromData.RData",
               posRDataName = "posData.RData",
               probenamesRDataName = "probeNames.RData",
               imgheight = 350,
               typeParall = "fork",
               mc.cores = 2)
    
    # Export meaningful results to CSV tables
    # Ensure the ff objects are open to access the data
    lapply(haar.ff.fork, open)
    
    # Extract smoothed values and states as data frames
    smoothed_df <- as.data.frame(haar.ff.fork\$outSmoothed[,])
    state_df <- as.data.frame(haar.ff.fork\$outState[,])
    
    # Write to CSV files
    write.csv(smoothed_df, "segmented_smoothed_values.csv", row.names = FALSE)
    write.csv(state_df, "segmented_state_values.csv", row.names = FALSE)
    
    # Clean up the temporary cuttedFile directory
    unlink(cut_dir, recursive = TRUE)

    writeLines(c(
        '"BIOC_ADACGH2_DIRECTORY_FF_FORKING":',
        paste0('    ADaCGH2: ', as.character(packageVersion('ADaCGH2')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_directory_ff_forking.csv versions.yml
    """
}

workflow BIOC_ADACGH2_DIRECTORY_FF_FORKING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ inputEx.txt ] ]

    main:
    BIOC_ADACGH2_DIRECTORY_FF_FORKING(ch_input)

    emit:
    tables   = BIOC_ADACGH2_DIRECTORY_FF_FORKING.out.tables
    plots    = BIOC_ADACGH2_DIRECTORY_FF_FORKING.out.plots
    objects  = BIOC_ADACGH2_DIRECTORY_FF_FORKING.out.objects
    versions = BIOC_ADACGH2_DIRECTORY_FF_FORKING.out.versions
}
