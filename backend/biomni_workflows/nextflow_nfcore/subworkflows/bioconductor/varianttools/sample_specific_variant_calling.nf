#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: VariantTools — sample_specific_variant_calling
// Call sample-specific (e.g., somatic) variants by comparing a case (tumor) BAM/tally to a control (normal) BAM/tally.
// Input: case.bam, control.bam, reference_genome
// Container: quay.io/biocontainers/bioconductor-varianttools:1.51.0--r45hdfd78af_0
// Requires: GenomicRanges, VariantTools, gmapR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define tally parameters using TallyVariantsParam
//  * 2. [Core Analysis] Call sample-specific variants using callSampleSpecificVariants with custom calling filters and power/p-value thresholds

nextflow.enable.dsl = 2

process BIOC_VARIANTTOOLS_SAMPLE_SPECIFIC_VARIANT_CALLING {
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
    .bm_deps <- c("GenomicRanges", "VariantTools", "gmapR")
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
    
    library(VariantTools)
    library(gmapR)
    library(GenomicRanges)
    
    # Locate the reference genome file
    ref_path <- "reference_genome"
    if (!file.exists(ref_path) && file.exists("reference_genome.fasta")) {
      ref_path <- "reference_genome.fasta"
    }
    
    if (!file.exists(ref_path)) {
      stop("Error: Reference genome file ('reference_genome' or 'reference_genome.fasta') not found in the working directory.")
    }
    
    if (!file.exists("case.bam")) {
      stop("Error: 'case.bam' not found in the working directory.")
    }
    
    if (!file.exists("control.bam")) {
      stop("Error: 'control.bam' not found in the working directory.")
    }
    
    # Build or load the GmapGenome object
    genome <- GmapGenome(ref_path, create = TRUE)
    
    # 1. Define tally parameters using TallyVariantsParam
    tally.param <- TallyVariantsParam(genome, 
                                      high_base_quality = 23L,
                                      indels = TRUE)
    tally.param@bamTallyParam@indels <- FALSE
    
    # 2. Call sample-specific variants using callSampleSpecificVariants
    calling.filters <- VariantCallingFilters(read.count = 3L)
    
    somatic <- callSampleSpecificVariants("case.bam", "control.bam", tally.param,
                                          calling.filters = calling.filters,
                                          power = 0.9, p.value = 0.001)
    
    # Save the results
    saveRDS(somatic, "somatic_variants.rds")
    write.csv(as.data.frame(somatic), "somatic_variants.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_VARIANTTOOLS_SAMPLE_SPECIFIC_VARIANT_CALLING":',
        paste0('    VariantTools: ', as.character(packageVersion('VariantTools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sample_specific_variant_calling.csv versions.yml
    """
}

workflow BIOC_VARIANTTOOLS_SAMPLE_SPECIFIC_VARIANT_CALLING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ case.bam, control.bam, reference_genome ] ]

    main:
    BIOC_VARIANTTOOLS_SAMPLE_SPECIFIC_VARIANT_CALLING(ch_input)

    emit:
    tables   = BIOC_VARIANTTOOLS_SAMPLE_SPECIFIC_VARIANT_CALLING.out.tables
    plots    = BIOC_VARIANTTOOLS_SAMPLE_SPECIFIC_VARIANT_CALLING.out.plots
    objects  = BIOC_VARIANTTOOLS_SAMPLE_SPECIFIC_VARIANT_CALLING.out.objects
    versions = BIOC_VARIANTTOOLS_SAMPLE_SPECIFIC_VARIANT_CALLING.out.versions
}
