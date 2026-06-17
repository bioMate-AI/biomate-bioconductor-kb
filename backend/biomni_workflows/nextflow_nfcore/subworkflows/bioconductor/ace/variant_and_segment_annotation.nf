#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ACE — variant_and_segment_annotation
// Extract adjusted copy number segments and link them to somatic mutations or specific genomic locations.
// Input: Segmented template data frame, variant/mutation data frame.
// Container: quay.io/biocontainers/bioconductor-ace:1.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ACE
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read User Input Files
//  * 2. [Core Analysis] Extract adjusted segments using getadjustedsegments
//  * 3. [Core Analysis] Link mutations to copy number segments and calculate
//  * 4. [Core Analysis] Query specific genomic locations using

nextflow.enable.dsl = 2

process BIOC_ACE_VARIANT_AND_SEGMENT_ANNOTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("ACE")
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
    library(ACE)
    
    # -----------------------------------------------------------------------------
    # --- Read User Input Files ---
    # -----------------------------------------------------------------------------
    # The pipeline expects 'template.csv' (segmented template data frame)
    # and 'variants.csv' (variant/mutation data frame) in the working directory.
    
    if (file.exists("template.csv")) {
      template <- read.csv("template.csv", stringsAsFactors = FALSE)
    } else if (file.exists("template.tsv")) {
      template <- read.delim("template.tsv", stringsAsFactors = FALSE)
    } else {
      stop("Error: Required input file 'template.csv' or 'template.tsv' not found in the working directory.")
    }
    
    if (file.exists("variants.csv")) {
      variantdf <- read.csv("variants.csv", stringsAsFactors = FALSE)
    } else if (file.exists("variants.tsv")) {
      variantdf <- read.delim("variants.tsv", stringsAsFactors = FALSE)
    } else {
      stop("Error: Required input file 'variants.csv' or 'variants.tsv' not found in the working directory.")
    }
    
    # -----------------------------------------------------------------------------
    # --- Extract adjusted segments using getadjustedsegments ---
    # -----------------------------------------------------------------------------
    segmentdf <- getadjustedsegments(template, cellularity = 0.38)
    head(segmentdf)
    
    # Save the adjusted segments to a CSV file
    write.csv(segmentdf, "adjusted_segments.csv", row.names = FALSE)
    
    # -----------------------------------------------------------------------------
    # --- Link mutations to copy number segments and calculate ---
    # -----------------------------------------------------------------------------
    # The documented function call uses:
    # chrindex = 2 (Chromosome), posindex = 3 (Position), freqindex = 4 (Frequency)
    # We execute the exact function call on the loaded variantdf and segmentdf.
    linked_variants <- linkvariants(variantdf, segmentdf, cellularity = 0.38, 
                                    chrindex = 2, posindex = 3, freqindex = 4)
    
    # Save the linked variants to a CSV file
    write.csv(linked_variants, "linked_variants.csv", row.names = FALSE)
    
    # -----------------------------------------------------------------------------
    # --- Query specific genomic locations using ---
    # -----------------------------------------------------------------------------
    # Query 1: Single location
    loc_query1 <- analyzegenomiclocations(segmentdf, Chromosome = 1, Position = 26365569)
    write.csv(loc_query1, "genomic_location_query1.csv", row.names = FALSE)
    
    # Query 2: Multiple locations
    chr <- c(1,2,3)
    pos <- c(2000000,4000000,6000000)
    loc_query2 <- analyzegenomiclocations(segmentdf, Chromosome = chr, Position = pos)
    write.csv(loc_query2, "genomic_location_query2.csv", row.names = FALSE)
    
    # Query 3: Multiple locations with frequencies to calculate mutant copies
    freq <- c(38,19,0)
    loc_query3 <- analyzegenomiclocations(segmentdf=segmentdf, cellularity = 0.38, 
                                          Chromosome = chr, Position = pos, Frequency = freq)
    write.csv(loc_query3, "genomic_location_query3.csv", row.names = FALSE)
    
    # Save all results in an RDS object for downstream analysis
    saveRDS(list(
      adjusted_segments = segmentdf,
      linked_variants = linked_variants,
      query1 = loc_query1,
      query2 = loc_query2,
      query3 = loc_query3
    ), "ace_workflow_results.rds")

    writeLines(c(
        '"BIOC_ACE_VARIANT_AND_SEGMENT_ANNOTATION":',
        paste0('    ACE: ', as.character(packageVersion('ACE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_variant_and_segment_annotation.csv versions.yml
    """
}

workflow BIOC_ACE_VARIANT_AND_SEGMENT_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Segmented template data frame, variant/mutation data frame. ] ]

    main:
    BIOC_ACE_VARIANT_AND_SEGMENT_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_ACE_VARIANT_AND_SEGMENT_ANNOTATION.out.tables
    plots    = BIOC_ACE_VARIANT_AND_SEGMENT_ANNOTATION.out.plots
    objects  = BIOC_ACE_VARIANT_AND_SEGMENT_ANNOTATION.out.objects
    versions = BIOC_ACE_VARIANT_AND_SEGMENT_ANNOTATION.out.versions
}
