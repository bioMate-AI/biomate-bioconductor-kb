#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: adacgh2 — ram_objects_forking
// Analyze small to moderate aCGH datasets entirely in memory using fast forking parallelization on Unix-like operating systems.
// Input: inputEx.RData
// Container: quay.io/biocontainers/bioconductor-adacgh2:2.50.0--r45h01b2380_1
// R packages: ADaCGH2, CGHregions, limma
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ADACGH2_RAM_OBJECTS_FORKING {
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
    .bm_deps <- c("ADaCGH2", "CGHregions", "limma")
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
    library(ADaCGH2)
    
    # --- Read the declared USER INPUT file from the working ---
    input_file <- "inputEx.RData"
    if (!file.exists(input_file)) {
      stop(paste("Required input file", input_file, "not found in the working directory."))
    }
    
    # Load the RData file which contains the 'inputEx' data frame
    load(input_file)
    
    if (!exists("inputEx")) {
      stop("The loaded RData file did not contain an object named 'inputEx'.")
    }
    
    # --- Prepare RAM objects from the input data frame ---
    cgh.dat <- inputEx[, -c(1, 2, 3)]
    chrom.dat <- as.integer(inputEx[, 2])
    pos.dat <- inputEx[, 3]
    probenames.dat <- as.character(inputEx[, 1])
    
    # --- Run parallelized segmentation using HaarSeg with forking ---
    # (Reproducing the documented function call and arguments exactly)
    haar.RAM.fork <- pSegmentHaarSeg(cgh.dat, chrom.dat,
                                     merging = "MAD",
                                     typeParall = "fork",
                                     mc.cores = 2)
    
    # --- Plot the chromosome results ---
    # (Reproducing the documented function call and arguments exactly)
    pChromPlot(haar.RAM.fork,
               cghRDataName = cgh.dat,
               chromRDataName = chrom.dat,
               posRDataName = pos.dat,
               probenamesRDataName = probenames.dat,
               imgheight = 350,
               typeParall = "fork",
               mc.cores = 2)
    
    # --- Write meaningful output files ---
    # Save the segmentation results object
    saveRDS(haar.RAM.fork, file = "haar_RAM_fork_results.rds")
    
    # Export smoothed values and states to CSV files
    if (!is.null(haar.RAM.fork\$outSmoothed)) {
      write.csv(as.data.frame(haar.RAM.fork\$outSmoothed), 
                file = "segmented_smoothed_values.csv", 
                row.names = FALSE)
    }
    
    if (!is.null(haar.RAM.fork\$outState)) {
      write.csv(as.data.frame(haar.RAM.fork\$outState), 
                file = "segmented_state_calls.csv", 
                row.names = FALSE)
    }
    
    cat("Pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_ADACGH2_RAM_OBJECTS_FORKING":',
        paste0('        adacgh2: ', as.character(packageVersion("adacgh2")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ram_objects_forking.csv versions.yml
    """
}

workflow BIOC_ADACGH2_RAM_OBJECTS_FORKING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ inputEx.RData ] ]

    main:
    BIOC_ADACGH2_RAM_OBJECTS_FORKING(ch_input)

    emit:
    tables   = BIOC_ADACGH2_RAM_OBJECTS_FORKING.out.tables
    plots    = BIOC_ADACGH2_RAM_OBJECTS_FORKING.out.plots
    objects  = BIOC_ADACGH2_RAM_OBJECTS_FORKING.out.objects
    versions = BIOC_ADACGH2_RAM_OBJECTS_FORKING.out.versions
}
