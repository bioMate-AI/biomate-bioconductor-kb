#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: fishalyser — automated_fish_quantification
// Perform end-to-end automated background correction, nuclei segmentation, probe detection, and distance calculation on FISH images.
// Input: SampleFISH.jpg, SampleFISH_R.jpg, SampleFISH_G.jpg
// Container: quay.io/biocontainers/bioconductor-fishalyser:1.44.0--r45hdfd78af_0
// R packages: FISHalyseR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FISHALYSER_AUTOMATED_FISH_QUANTIFICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-fishalyser:1.44.0--r45hdfd78af_0"

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
    .bm_deps <- c("FISHalyseR")
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
    
    # Load the required package
    library(FISHalyseR)
    
    # Define input file paths from the working directory
    combinedImage <- "SampleFISH.jpg"
    red_Og   <- "SampleFISH_R.jpg"
    green_Gn <- "SampleFISH_G.jpg"
    
    # Validate that the required input files exist
    required_files <- c(combinedImage, red_Og, green_Gn)
    missing_files <- required_files[!file.exists(required_files)]
    if (length(missing_files) > 0) {
      stop(paste("Missing required input files in the working directory:", paste(missing_files, collapse = ", ")))
    }
    
    # Define output directory where all the files will be saved
    writedir <- "./output_fishalyser"
    if (!dir.exists(writedir)) {
      dir.create(writedir, recursive = TRUE)
    }
    
    # --- Define background correction method list ---
    # list(0, '') specifies no background correction
    bgCorrMethod <- list(0, '')
    
    # --- Define channel signals and colors lists ---
    channelColours <- list(R = c(255, 0, 0), G = c(0, 255, 0))
    channelSignals <- list(red_Og, green_Gn)
    
    # Define size constraints for cell nuclei and probes
    sizecell <- c(1000, 20000)
    sizeprobe <- c(5, 20)
    
    # --- Run end-to-end pipeline using processFISH ---
    processFISH(
      combinedImage,
      writedir,
      bgCorrMethod,
      channelSignals,
      channelColours,
      sizecell,
      sizeprobe
    )
    
    # Save an RDS of the configuration/parameters for reproducibility
    config <- list(
      combinedImage = combinedImage,
      writedir = writedir,
      bgCorrMethod = bgCorrMethod,
      channelSignals = channelSignals,
      channelColours = channelColours,
      sizecell = sizecell,
      sizeprobe = sizeprobe
    )
    saveRDS(config, file = file.path(writedir, "fishalyser_config.rds"))

    writeLines(c(
        '"BIOC_FISHALYSER_AUTOMATED_FISH_QUANTIFICATION":',
        paste0('        fishalyser: ', as.character(packageVersion("fishalyser")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_automated_fish_quantification.csv versions.yml
    """
}

workflow BIOC_FISHALYSER_AUTOMATED_FISH_QUANTIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SampleFISH.jpg, SampleFISH_R.jpg, SampleFISH_G.jpg ] ]

    main:
    BIOC_FISHALYSER_AUTOMATED_FISH_QUANTIFICATION(ch_input)

    emit:
    tables   = BIOC_FISHALYSER_AUTOMATED_FISH_QUANTIFICATION.out.tables
    plots    = BIOC_FISHALYSER_AUTOMATED_FISH_QUANTIFICATION.out.plots
    objects  = BIOC_FISHALYSER_AUTOMATED_FISH_QUANTIFICATION.out.objects
    versions = BIOC_FISHALYSER_AUTOMATED_FISH_QUANTIFICATION.out.versions
}
