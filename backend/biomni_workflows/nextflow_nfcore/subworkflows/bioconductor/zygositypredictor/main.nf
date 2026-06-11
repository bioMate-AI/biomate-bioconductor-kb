#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ZygosityPredictor — variant_copy_calculation
// Calculate the number of copies affected by individual germline or somatic variants.
// Input: GR_GERM_SMALL_VARS, GR_SOM_SMALL_VARS, GR_SCNA
// Container: quay.io/biocontainers/bioconductor-zygositypredictor:1.10.0--r45hdfd78af_0
// R packages: dplyr, GenomicRanges, stringr, ZygosityPredictor
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, ZygosityPredictor, dplyr, stringr
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Extract germline variant allele frequency and chromosome
//  * 2. [Core Analysis] Extract total copy number at the germline variant position
//  * 3. [Core Analysis] Calculate affected copies for germline variants
//  * 4. [Core Analysis] Extract somatic variant allele frequency, chromosome, and
//  * 5. [Core Analysis] Calculate affected copies for a set of variants

nextflow.enable.dsl = 2

process BIOC_ZYGOSITYPREDICTOR_VARIANT_COPY_CALCULATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("dplyr", "GenomicRanges", "stringr", "ZygosityPredictor")
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
    library(ZygosityPredictor)
    library(dplyr)
    library(stringr)
    library(GenomicRanges)
    
    # Read user input files from the working directory
    GR_GERM_SMALL_VARS <- readRDS("GR_GERM_SMALL_VARS.rds")
    GR_SOM_SMALL_VARS <- readRDS("GR_SOM_SMALL_VARS.rds")
    GR_SCNA <- readRDS("GR_SCNA.rds")
    
    # Define sample metadata parameters
    PURITY <- 0.98
    SEX <- "female"
    
    # --- Extract germline variant allele frequency and chromosome ---
    AF = elementMetadata(GR_GERM_SMALL_VARS[1])[["af"]]
    CHR = seqnames(GR_GERM_SMALL_VARS[1]) %>%
      as.character()
    
    # --- Extract total copy number at the germline variant position ---
    TCN = elementMetadata(
      subsetByOverlaps(GR_SCNA, GR_GERM_SMALL_VARS[1])
      )[["tcn"]]
    
    # --- Calculate affected copies for germline variants ---
    germ_copies <- aff_germ_copies(af=AF,
                    tcn=TCN,
                    purity=PURITY,
                    chr=CHR,
                    sex=SEX)
    
    # --- Extract somatic variant allele frequency, chromosome, and ---
    AF = elementMetadata(GR_SOM_SMALL_VARS[1])[["af"]]
    CHR = seqnames(GR_SOM_SMALL_VARS[1]) %>%
      as.character()
    TCN = elementMetadata(
      subsetByOverlaps(GR_SCNA, GR_SOM_SMALL_VARS[1])
      )[["tcn"]]
    
    # Calculate affected copies for somatic variants
    som_copies <- aff_som_copies(af=AF,
                   chr=CHR,
                   tcn=TCN,
                   purity=PURITY,
                   sex=SEX)
    
    # --- Calculate affected copies for a set of variants ---
    pred_per_var <- predict_per_variant(purity=PURITY, 
                        sex=SEX,
                        somCna=GR_SCNA,
                        somSmallVars=GR_SOM_SMALL_VARS)
    
    # Write outputs to files
    writeLines(as.character(germ_copies), "germline_affected_copies.txt")
    writeLines(as.character(som_copies), "somatic_affected_copies.txt")
    saveRDS(pred_per_var, "predict_per_variant_results.rds")
    
    if (!is.null(pred_per_var\$evaluation_per_variant)) {
      write.csv(pred_per_var\$evaluation_per_variant, "evaluation_per_variant.csv", row.names = FALSE)
    }

    writeLines(c(
        '"BIOC_ZYGOSITYPREDICTOR_VARIANT_COPY_CALCULATION":',
        paste0('    ZygosityPredictor: ', as.character(packageVersion('ZygosityPredictor')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_variant_copy_calculation.csv versions.yml
    """
}

workflow BIOC_ZYGOSITYPREDICTOR_VARIANT_COPY_CALCULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ GR_GERM_SMALL_VARS, GR_SOM_SMALL_VARS, GR_SCNA ] ]

    main:
    BIOC_ZYGOSITYPREDICTOR_VARIANT_COPY_CALCULATION(ch_input)

    emit:
    tables   = BIOC_ZYGOSITYPREDICTOR_VARIANT_COPY_CALCULATION.out.tables
    plots    = BIOC_ZYGOSITYPREDICTOR_VARIANT_COPY_CALCULATION.out.plots
    objects  = BIOC_ZYGOSITYPREDICTOR_VARIANT_COPY_CALCULATION.out.objects
    versions = BIOC_ZYGOSITYPREDICTOR_VARIANT_COPY_CALCULATION.out.versions
}
