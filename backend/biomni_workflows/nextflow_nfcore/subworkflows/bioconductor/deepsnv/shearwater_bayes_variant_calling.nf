#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: deepSNV — shearwater_bayes_variant_calling
// Call mutations across multiple samples using the original Shearwater Bayes classifier with prior information.
// Input: test.bam, control.bam
// Container: quay.io/biocontainers/bioconductor-deepsnv:1.56.0--r45ha27e39d_0
// R packages: GenomicRanges, VariantAnnotation, deepSNV
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, VariantAnnotation, deepSNV
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define genomic regions of interest
//  * 2. [Input & Preparation] Load count data from BAM files using loadAllData
//  * 3. [Core Analysis] Compute Bayes factors using bbb
//  * 4. [Visualization & Output] Export variants to VCF format using bf2Vcf

nextflow.enable.dsl = 2

process BIOC_DEEPSNV_SHEARWATER_BAYES_VARIANT_CALLING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20-slim"

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
    .bm_deps <- c("GenomicRanges", "VariantAnnotation", "deepSNV")
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
    library(deepSNV)
    library(GenomicRanges)
    library(VariantAnnotation)
    
    # 1. Define genomic regions of interest
    regions <- GRanges("B.FR.83.HXB2_LAI_IIIB_BRU_K034", IRanges(start = 3120, end = 3140))
    
    # Define local input files (must exist in the working directory)
    files <- c("test.bam", "control.bam")
    
    # Verify that input files exist before proceeding
    for (f in files) {
      if (!file.exists(f)) {
        stop(paste("Required input file missing in working directory:", f))
      }
    }
    
    # 2. Load count data from BAM files using loadAllData
    counts <- loadAllData(files, regions, q=10)
    
    # 3. Compute Bayes factors using bbb
    bf <- bbb(counts, model = "OR", rho=1e-4)
    
    # 4. Export variants to VCF format using bf2Vcf
    vcf <- bf2Vcf(bf, counts, regions, cutoff = 0.5, samples = files, prior = 0.5, mvcf = TRUE)
    
    # Save outputs to the working directory
    saveRDS(counts, file = "shearwater_counts.rds")
    saveRDS(bf, file = "shearwater_bayes_factors.rds")
    writeVcf(vcf, filename = "shearwater_bayes_variants.vcf")

    writeLines(c(
        '"BIOC_DEEPSNV_SHEARWATER_BAYES_VARIANT_CALLING":',
        paste0('    deepSNV: ', as.character(packageVersion('deepSNV')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_shearwater_bayes_variant_calling.csv versions.yml
    """
}

workflow BIOC_DEEPSNV_SHEARWATER_BAYES_VARIANT_CALLING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ test.bam, control.bam ] ]

    main:
    BIOC_DEEPSNV_SHEARWATER_BAYES_VARIANT_CALLING(ch_input)

    emit:
    tables   = BIOC_DEEPSNV_SHEARWATER_BAYES_VARIANT_CALLING.out.tables
    plots    = BIOC_DEEPSNV_SHEARWATER_BAYES_VARIANT_CALLING.out.plots
    objects  = BIOC_DEEPSNV_SHEARWATER_BAYES_VARIANT_CALLING.out.objects
    versions = BIOC_DEEPSNV_SHEARWATER_BAYES_VARIANT_CALLING.out.versions
}
