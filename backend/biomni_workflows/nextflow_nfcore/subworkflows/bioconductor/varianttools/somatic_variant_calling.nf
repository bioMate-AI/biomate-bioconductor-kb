#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: varianttools — somatic_variant_calling
// Call sample-specific (e.g., somatic tumor vs. normal) variants from case and control BAM files.
// Input: case.bam, control.bam
// Container: quay.io/biocontainers/bioconductor-varianttools:1.51.0--r45hdfd78af_0
// R packages: VariantAnnotation, VariantTools, gmapR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VARIANTTOOLS_SOMATIC_VARIANT_CALLING {
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
    .bm_deps <- c("VariantAnnotation", "VariantTools", "gmapR")
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
    
    # Load required Bioconductor libraries
    library(VariantTools)
    library(gmapR)
    library(VariantAnnotation)
    
    # Define user input files
    case_bam <- "case.bam"
    control_bam <- "control.bam"
    
    # Verify input files exist
    if (!file.exists(case_bam)) {
      stop(paste("Required input file missing:", case_bam))
    }
    if (!file.exists(control_bam)) {
      stop(paste("Required input file missing:", control_bam))
    }
    
    # --- Define tally parameters using TallyVariantsParam ---
    # We use the TP53Genome from gmapR as the reference genome.
    # In a production pipeline, this should be replaced with the GmapGenome 
    # corresponding to the reference used for aligning case.bam and control.bam.
    genome <- gmapR::TP53Genome()
    
    tally.param <- TallyVariantsParam(genome = genome,
                                      high_base_quality = 23L,
                                      indels = TRUE,
                                      read_length = 75L)
    
    # --- Call sample-specific variants using ---
    # Modify tally parameters as documented
    tally.param@bamTallyParam@indels <- FALSE
    
    # First call (with default filters)
    somatic_initial <- callSampleSpecificVariants(case_bam, control_bam,
                                                  tally.param)
    
    # Second call (with custom calling filters and power/p-value thresholds)
    calling.filters <- VariantCallingFilters(read.count = 3L)
    somatic <- callSampleSpecificVariants(case_bam, control_bam, tally.param,
                                          calling.filters = calling.filters,
                                          power = 0.9, p.value = 0.001)
    
    # Write named output files for the meaningful results
    # Save the somatic variants as an RDS object
    saveRDS(somatic, "somatic_variants.rds")
    
    # Export the somatic variants to a CSV table
    somatic_df <- as.data.frame(somatic)
    write.csv(somatic_df, "somatic_variants.csv", row.names = FALSE)
    
    # Export the somatic variants to a VCF file
    tryCatch({
      # Set sample name to avoid missing sample name errors during VCF export
      sampleNames(somatic) <- "case"
      # Clear metadata columns for simplicity and compatibility
      mcols(somatic) <- NULL
      vcf <- asVCF(somatic)
      writeVcf(vcf, "somatic_variants.vcf")
    }, error = function(e) {
      warning("Could not export to VCF: ", e\$message)
    })
    
    cat("Somatic variant calling pipeline completed successfully.\n")

    writeLines(c(
        '"BIOC_VARIANTTOOLS_SOMATIC_VARIANT_CALLING":',
        paste0('        varianttools: ', as.character(packageVersion("varianttools")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_somatic_variant_calling.csv versions.yml
    """
}

workflow BIOC_VARIANTTOOLS_SOMATIC_VARIANT_CALLING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ case.bam, control.bam ] ]

    main:
    BIOC_VARIANTTOOLS_SOMATIC_VARIANT_CALLING(ch_input)

    emit:
    tables   = BIOC_VARIANTTOOLS_SOMATIC_VARIANT_CALLING.out.tables
    plots    = BIOC_VARIANTTOOLS_SOMATIC_VARIANT_CALLING.out.plots
    objects  = BIOC_VARIANTTOOLS_SOMATIC_VARIANT_CALLING.out.objects
    versions = BIOC_VARIANTTOOLS_SOMATIC_VARIANT_CALLING.out.versions
}
