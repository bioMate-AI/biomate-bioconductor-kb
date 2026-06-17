#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gmapR — variant_tallying_bam_tally
// Tally nucleotide-level coverage and allele counts from a BAM file to identify variants.
// Input: bam_file, genome
// Container: quay.io/biocontainers/bioconductor-gmapr:1.48.0--r44h15a9599_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: VariantAnnotation, gmapR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load or create the GmapGenome object
//  * 2. [Core Analysis] Configure tally parameters using BamTallyParam
//  * 3. [Core Analysis] Run bam_tally on the BAM file
//  * 4. [Visualization & Output] Summarize the tallies into a VRanges object using variantSummary

nextflow.enable.dsl = 2

process BIOC_GMAPR_VARIANT_TALLYING_BAM_TALLY {
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
    .bm_deps <- c("gmapR", "VariantAnnotation")
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
    library(gmapR)
    library(VariantAnnotation)
    
    # Define input file paths in the working directory
    bam_file <- "input.bam"
    genome_rds <- "genome.rds"
    
    # Verify that the input files exist
    if (!file.exists(bam_file)) {
      stop("Error: Input BAM file 'input.bam' not found in the working directory.")
    }
    if (!file.exists(genome_rds)) {
      stop("Error: Input genome RDS file 'genome.rds' not found in the working directory.")
    }
    
    # Load the GmapGenome object from the RDS file
    genome <- readRDS(genome_rds)
    
    # Define parameters as specified in the documented workflow
    mapq <- 13L
    param <- BamTallyParam(genome,
                           minimum_mapq = mapq,
                           concordant_only = FALSE, unique_only = FALSE,
                           primary_only = FALSE,
                           min_depth = 0L, variant_strand = 1L,
                           ignore_query_Ns = TRUE,
                           indels = FALSE, include_soft_clips = 1L, xs=TRUE,
                           min_base_quality = 23L)
    
    # Run the tallying process on the BAM file
    tallies <- bam_tally(bam_file, param)
    
    # Summarize the tallies into a VRanges object
    variants <- variantSummary(tallies)
    
    # Save the resulting VRanges object as an RDS file
    saveRDS(variants, file = "variants.rds")
    
    # Convert the VRanges object to a data frame and export as a CSV table
    variants_df <- as.data.frame(variants)
    write.csv(variants_df, file = "variants_summary.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_GMAPR_VARIANT_TALLYING_BAM_TALLY":',
        paste0('    gmapR: ', as.character(packageVersion('gmapR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_variant_tallying_bam_tally.csv versions.yml
    """
}

workflow BIOC_GMAPR_VARIANT_TALLYING_BAM_TALLY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bam_file, genome ] ]

    main:
    BIOC_GMAPR_VARIANT_TALLYING_BAM_TALLY(ch_input)

    emit:
    tables   = BIOC_GMAPR_VARIANT_TALLYING_BAM_TALLY.out.tables
    plots    = BIOC_GMAPR_VARIANT_TALLYING_BAM_TALLY.out.plots
    objects  = BIOC_GMAPR_VARIANT_TALLYING_BAM_TALLY.out.objects
    versions = BIOC_GMAPR_VARIANT_TALLYING_BAM_TALLY.out.versions
}
