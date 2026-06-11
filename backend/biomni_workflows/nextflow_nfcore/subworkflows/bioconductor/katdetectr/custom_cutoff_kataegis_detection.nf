#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: katdetectr — custom_cutoff_kataegis_detection
// Detect kataegis foci using a custom user-defined function to calculate segment-specific IMD cutoffs.
// Input: syntheticData
// Container: quay.io/biocontainers/bioconductor-katdetectr:1.12.0--r45hdfd78af_0
// R packages: GenomicRanges, VariantAnnotation, dplyr, katdetectr
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KATDETECTR_CUSTOM_CUTOFF_KATAEGIS_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-katdetectr:1.12.0--r45hdfd78af_0"

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
    .bm_deps <- c("GenomicRanges", "VariantAnnotation", "dplyr", "katdetectr")
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
    library(katdetectr)
    library(dplyr)
    library(VariantAnnotation)
    library(GenomicRanges)
    
    # 1. Read the user input file from the working directory
    if (file.exists("syntheticData")) {
        syntheticData <- readRDS("syntheticData")
    } else if (file.exists("syntheticData.rds")) {
        syntheticData <- readRDS("syntheticData.rds")
    } else {
        stop("Error: Input file 'syntheticData' or 'syntheticData.rds' not found in the working directory.")
    }
    
    # 2. Define custom functions for modeling sample rate and calculating segment-specific IMD cutoffs
    modelSampleRate <- function(IMDs) {
        lambda <- log(2) / median(IMDs)
    
        return(lambda)
    }
    
    nthroot <- function(x, n) {
        y <- x^(1 / n)
    
        return(y)
    }
    
    IMDcutoffFun <- function(genomicVariants, segments) {
        IMDs <- genomicVariants\$IMD
        totalVariants <- segments\$totalVariants
        width <- segments |>
            dplyr::as_tibble() |>
            dplyr::pull(width)
    
        sampleRate <- modelSampleRate(IMDs)
    
        IMDcutoff <- -log(1 - nthroot(0.01 / width, ifelse(totalVariants != 0, totalVariants - 1, 1))) / sampleRate
    
        IMDcutoff <- replace(IMDcutoff, IMDcutoff > 1000, 1000)
    
        return(IMDcutoff)
    }
    
    # 3. Run detectKataegis() with the custom function passed to the IMDcutoff parameter
    kdCustom <- detectKataegis(syntheticData, IMDcutoff = IMDcutoffFun)
    
    # 4. Write named output files for the meaningful results
    saveRDS(kdCustom, "kdCustom.rds")
    
    # Extract and save genomic variants
    gv <- getGenomicVariants(kdCustom)
    gv_df <- as.data.frame(gv)
    write.csv(gv_df, "genomic_variants.csv", row.names = FALSE)
    
    # Extract and save segments
    seg <- getSegments(kdCustom)
    seg_df <- as.data.frame(seg)
    write.csv(seg_df, "segments.csv", row.names = FALSE)
    
    # Extract and save kataegis foci
    foci <- getKataegisFoci(kdCustom)
    foci_df <- as.data.frame(foci)
    write.csv(foci_df, "kataegis_foci.csv", row.names = FALSE)
    
    # Generate and save rainfall plot
    pdf("rainfall_plot.pdf", width = 10, height = 6)
    tryCatch({
        rainfallPlot(kdCustom, showKataegis = TRUE, showSegmentation = TRUE)
    }, error = function(e) {
        message("Rainfall plot generation failed: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_KATDETECTR_CUSTOM_CUTOFF_KATAEGIS_DETECTION":',
        paste0('        katdetectr: ', as.character(packageVersion("katdetectr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_cutoff_kataegis_detection.csv versions.yml
    """
}

workflow BIOC_KATDETECTR_CUSTOM_CUTOFF_KATAEGIS_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ syntheticData ] ]

    main:
    BIOC_KATDETECTR_CUSTOM_CUTOFF_KATAEGIS_DETECTION(ch_input)

    emit:
    tables   = BIOC_KATDETECTR_CUSTOM_CUTOFF_KATAEGIS_DETECTION.out.tables
    plots    = BIOC_KATDETECTR_CUSTOM_CUTOFF_KATAEGIS_DETECTION.out.plots
    objects  = BIOC_KATDETECTR_CUSTOM_CUTOFF_KATAEGIS_DETECTION.out.objects
    versions = BIOC_KATDETECTR_CUSTOM_CUTOFF_KATAEGIS_DETECTION.out.versions
}
