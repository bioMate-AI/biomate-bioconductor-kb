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
    
    # 1. Read User Inputs
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
    
    # 2. Run detectKataegis specifying the refSeq argument
    kdNonStandard <- detectKataegis(genomicVariants = syndata, refSeq = sequenceLength)
    
    # 3. Save Outputs
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

    cat <<-END_VERSIONS > versions.yml
    "BIOC_KATDETECTR_NON_STANDARD_SEQUENCE_DETECTION":
        katdetectr: \$(Rscript -e 'cat(as.character(packageVersion("katdetectr")))')
    END_VERSIONS
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
