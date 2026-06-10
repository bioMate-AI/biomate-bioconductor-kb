#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: VariantTools — wildtype_and_nocall_calling
// Determine whether non-variant positions have sufficient coverage to be called wildtype or are "no-call" regions.
// Input: sample.bam, called_variants.GRanges
// Container: quay.io/biocontainers/bioconductor-varianttools:1.51.0--r45hdfd78af_0
// Requires: GenomicRanges, VariantTools
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter out indels from called variants using isIndel
//  * 2. [Input & Preparation] Define positions of interest
//  * 3. [Core Analysis] Call wildtype status using callWildtype with calling filters and power threshold

nextflow.enable.dsl = 2

process BIOC_VARIANTTOOLS_WILDTYPE_AND_NOCALL_CALLING {
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
    .bm_deps <- c("GenomicRanges", "VariantTools")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required Bioconductor libraries
    library(VariantTools)
    library(GenomicRanges)
    
    # Define input file paths
    bam_path <- "sample.bam"
    variants_path <- "called_variants.GRanges"
    
    # Verify input files exist
    if (!file.exists(bam_path)) {
      stop(paste("Required input BAM file is missing:", bam_path))
    }
    if (!file.exists(variants_path)) {
      stop(paste("Required input GRanges/VRanges file is missing:", variants_path))
    }
    
    # Read the called variants (expected to be a serialized GRanges/VRanges RDS object)
    called.variants <- readRDS(variants_path)
    
    # Assign the BAM file path to the variable 'bam' as expected by the documented code
    bam <- bam_path
    
    # === DOCUMENTED CODE WORKFLOW ===
    
    # 1. Filter out indels from called variants using isIndel
    called.variants <- called.variants[!isIndel(called.variants)]
    
    # 2. Define positions of interest
    pos <- c(called.variants, shift(called.variants, 3))
    
    # 3. Call wildtype status using callWildtype with calling filters and power threshold
    wildtype <- callWildtype(bam, called.variants, VariantCallingFilters(), 
                             pos = pos, power = 0.85)
    
    # Calculate the fraction of positions successfully called (non-NA)
    fraction_called <- mean(!is.na(wildtype))
    
    # === END DOCUMENTED CODE WORKFLOW ===
    
    # Save the primary output object
    saveRDS(wildtype, "wildtype_calls.rds")
    
    # Generate and save a summary CSV of the wildtype calling results
    summary_df <- data.frame(
      Metric = c("Total_Positions_Evaluated", "Wildtype_Count", "Variant_Count", "NoCall_Count", "Fraction_Called"),
      Value = c(
        length(wildtype),
        sum(wildtype == TRUE, na.rm = TRUE),
        sum(wildtype == FALSE, na.rm = TRUE),
        sum(is.na(wildtype)),
        fraction_called
      )
    )
    write.csv(summary_df, "wildtype_summary.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_VARIANTTOOLS_WILDTYPE_AND_NOCALL_CALLING":',
        paste0('    VariantTools: ', as.character(packageVersion('VariantTools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_wildtype_and_nocall_calling.csv versions.yml
    """
}

workflow BIOC_VARIANTTOOLS_WILDTYPE_AND_NOCALL_CALLING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample.bam, called_variants.GRanges ] ]

    main:
    BIOC_VARIANTTOOLS_WILDTYPE_AND_NOCALL_CALLING(ch_input)

    emit:
    tables   = BIOC_VARIANTTOOLS_WILDTYPE_AND_NOCALL_CALLING.out.tables
    plots    = BIOC_VARIANTTOOLS_WILDTYPE_AND_NOCALL_CALLING.out.plots
    objects  = BIOC_VARIANTTOOLS_WILDTYPE_AND_NOCALL_CALLING.out.objects
    versions = BIOC_VARIANTTOOLS_WILDTYPE_AND_NOCALL_CALLING.out.versions
}
