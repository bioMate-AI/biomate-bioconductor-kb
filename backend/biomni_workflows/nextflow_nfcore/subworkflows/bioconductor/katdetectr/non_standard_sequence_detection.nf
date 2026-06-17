#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: katdetectr — non_standard_sequence_detection
// Detect kataegis foci in genomes with non-standard sequences by providing custom sequence lengths.
// Input: syndata, sequenceLength
// Container: quay.io/biocontainers/bioconductor-katdetectr:1.12.0--r45hdfd78af_0
// R packages: katdetectr
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KATDETECTR_NON_STANDARD_SEQUENCE_DETECTION {
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
    .bm_deps <- c("katdetectr")
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
    library(katdetectr)
    
    # --- Read User Inputs ---
    # Read the VRanges object containing variants on non-standard sequences
    if (file.exists("syndata.rds")) {
        syndata <- readRDS("syndata.rds")
    } else {
        stop("Error: Required input file 'syndata.rds' not found in the working directory.")
    }
    
    # Read the sequence lengths data frame
    if (file.exists("sequenceLength.csv")) {
        sequenceLength <- read.csv("sequenceLength.csv", check.names = FALSE)
    } else if (file.exists("sequenceLength.rds")) {
        sequenceLength <- readRDS("sequenceLength.rds")
    } else {
        stop("Error: Required input file 'sequenceLength.csv' or 'sequenceLength.rds' not found in the working directory.")
    }
    
    # --- Run detectKataegis specifying the refSeq argument ---
    kdNonStandard <- detectKataegis(genomicVariants = syndata, refSeq = sequenceLength)
    
    # --- Save Outputs ---
    # Save the complete KatDetect object
    saveRDS(kdNonStandard, "kdNonStandard.rds")
    
    # Extract and save putative kataegis foci
    foci <- getKataegisFoci(kdNonStandard)
    foci_df <- as.data.frame(foci)
    write.csv(foci_df, "kataegis_foci.csv", row.names = FALSE)
    
    # Extract and save segments
    segments <- getSegments(kdNonStandard)
    segments_df <- as.data.frame(segments)
    write.csv(segments_df, "segments.csv", row.names = FALSE)
    
    # Extract and save processed genomic variants
    variants <- getGenomicVariants(kdNonStandard)
    variants_df <- as.data.frame(variants)
    write.csv(variants_df, "genomic_variants.csv", row.names = FALSE)
    
    # Generate and save rainfall plot
    pdf("rainfall_plot.pdf", width = 12, height = 7)
    tryCatch({
        rainfallPlot(kdNonStandard)
    }, error = function(e) {
        warning("Could not generate rainfall plot: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_KATDETECTR_NON_STANDARD_SEQUENCE_DETECTION":',
        paste0('        katdetectr: ', as.character(packageVersion("katdetectr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_non_standard_sequence_detection.csv versions.yml
    """
}

workflow BIOC_KATDETECTR_NON_STANDARD_SEQUENCE_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ syndata, sequenceLength ] ]

    main:
    BIOC_KATDETECTR_NON_STANDARD_SEQUENCE_DETECTION(ch_input)

    emit:
    tables   = BIOC_KATDETECTR_NON_STANDARD_SEQUENCE_DETECTION.out.tables
    plots    = BIOC_KATDETECTR_NON_STANDARD_SEQUENCE_DETECTION.out.plots
    objects  = BIOC_KATDETECTR_NON_STANDARD_SEQUENCE_DETECTION.out.objects
    versions = BIOC_KATDETECTR_NON_STANDARD_SEQUENCE_DETECTION.out.versions
}
