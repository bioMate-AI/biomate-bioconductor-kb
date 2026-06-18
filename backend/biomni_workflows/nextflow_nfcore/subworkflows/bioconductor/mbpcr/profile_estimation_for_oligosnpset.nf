#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mbpcr — profile_estimation_for_oligosnpset
// Estimate copy number profiles directly from an oligoSnpSet object.
// Input: oligoSet
// Container: quay.io/biocontainers/bioconductor-mbpcr:1.64.0--r45hdfd78af_0
// R packages: Biobase, mBPCR, oligoClasses
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_MBPCR_PROFILE_ESTIMATION_FOR_OLIGOSNPSET {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-mbpcr:1.64.0--r45hdfd78af_0"

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
    .bm_deps <- c("Biobase", "mBPCR", "oligoClasses")
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
    library(mBPCR)
    library(oligoClasses)
    library(Biobase)
    
    # --- Read the user input file from the working directory ---
    # The input is expected to be an oligoSnpSet object saved as an RDS file.
    input_file <- "oligoSet.rds"
    if (!file.exists(input_file)) {
      if (file.exists("oligoSet")) {
        input_file <- "oligoSet"
      } else {
        stop("Error: Input file 'oligoSet.rds' or 'oligoSet' not found in the working directory.")
      }
    }
    
    message("Reading input oligoSnpSet object from: ", input_file)
    oligoSet <- readRDS(input_file)
    
    # --- Run profile estimation using ---
    # We use the exact function call and arguments from the documented vignette workflow.
    message("Estimating copy number profile...")
    r <- estProfileWithMBPCRforOligoSnpSet(
      oligoSet, 
      sampleToBeAnalyzed = 1, 
      chrToBeAnalyzed = 2, 
      maxProbeNumber = 1000, 
      ifLogRatio = 0, 
      rhoSquare = 0.0889637
    )
    
    # --- Extract the estimated copy number profile ---
    cc <- r\$estPC
    cc1 <- cc[chromosome(cc) == "2", 1]
    
    # --- Save the results to output files ---
    # Save the full results object
    saveRDS(r, "mbpcr_results.rds")
    
    # Save the extracted profile as a CSV table
    df_profile <- data.frame(
      position = position(cc1),
      copy_number = copyNumber(cc1)[, 1]
    )
    write.csv(df_profile, "estimated_copy_number_chr2.csv", row.names = FALSE)
    
    # Plot the estimated copy number profile and save as PDF
    pdf("copy_number_profile_chr2.pdf", width = 8, height = 6)
    par(las = 1)
    plot(
      position(cc1), 
      copyNumber(cc1), 
      ylim = c(-0.23, 0.1), 
      ylab = "copy number", 
      xlab = "base position",
      main = "Estimated Copy Number Profile (Chromosome 2)"
    )
    dev.off()
    
    message("Workflow completed successfully.")
    message("Outputs written:")
    message("- mbpcr_results.rds (Full estimation results)")
    message("- estimated_copy_number_chr2.csv (Estimated copy numbers for Chromosome 2)")
    message("- copy_number_profile_chr2.pdf (Visualization plot)")

    writeLines(c(
        '"BIOC_MBPCR_PROFILE_ESTIMATION_FOR_OLIGOSNPSET":',
        paste0('        mbpcr: ', as.character(packageVersion("mbpcr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_profile_estimation_for_oligosnpset.csv versions.yml
    """
}

workflow BIOC_MBPCR_PROFILE_ESTIMATION_FOR_OLIGOSNPSET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ oligoSet ] ]

    main:
    BIOC_MBPCR_PROFILE_ESTIMATION_FOR_OLIGOSNPSET(ch_input)

    emit:
    tables   = BIOC_MBPCR_PROFILE_ESTIMATION_FOR_OLIGOSNPSET.out.tables
    plots    = BIOC_MBPCR_PROFILE_ESTIMATION_FOR_OLIGOSNPSET.out.plots
    objects  = BIOC_MBPCR_PROFILE_ESTIMATION_FOR_OLIGOSNPSET.out.objects
    versions = BIOC_MBPCR_PROFILE_ESTIMATION_FOR_OLIGOSNPSET.out.versions
}
