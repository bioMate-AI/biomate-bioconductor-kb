#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: varianttools — wildtype_calling
// Determine which non-variant positions have sufficient coverage to be confidently called wildtype.
// Input: sample.bam, called_variants.GRanges
// Container: quay.io/biocontainers/bioconductor-varianttools:1.51.0--r45hdfd78af_0
// R packages: GenomicRanges, VariantTools
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VARIANTTOOLS_WILDTYPE_CALLING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-varianttools:1.51.0--r45hdfd78af_0"

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
    .bm_deps <- c("GenomicRanges", "VariantTools")
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
    library(VariantTools)
    library(GenomicRanges)
    
    # --- Read the declared user input files from the working ---
    bam <- "sample.bam"
    called.variants <- readRDS("called_variants.GRanges")
    
    # --- Execute the documented workflow steps exactly as specified ---
    called.variants <- called.variants[!isIndel(called.variants)]
    pos <- c(called.variants, shift(called.variants, 3))
    wildtype <- callWildtype(bam, called.variants, VariantCallingFilters(), 
                             pos = pos, power = 0.85)
    
    # --- Write meaningful output files ---
    # Save the raw wildtype results as an RDS object
    saveRDS(wildtype, "wildtype_results.rds")
    
    # Export a combined CSV table of positions and their wildtype status
    output_df <- as.data.frame(pos)
    output_df\$wildtype <- as.vector(wildtype)
    write.csv(output_df, "wildtype_calls.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_VARIANTTOOLS_WILDTYPE_CALLING":',
        paste0('        varianttools: ', as.character(packageVersion("varianttools")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_wildtype_calling.csv versions.yml
    """
}

workflow BIOC_VARIANTTOOLS_WILDTYPE_CALLING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample.bam, called_variants.GRanges ] ]

    main:
    BIOC_VARIANTTOOLS_WILDTYPE_CALLING(ch_input)

    emit:
    tables   = BIOC_VARIANTTOOLS_WILDTYPE_CALLING.out.tables
    plots    = BIOC_VARIANTTOOLS_WILDTYPE_CALLING.out.plots
    objects  = BIOC_VARIANTTOOLS_WILDTYPE_CALLING.out.objects
    versions = BIOC_VARIANTTOOLS_WILDTYPE_CALLING.out.versions
}
