#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: varianttools — single_sample_calling
// Call single-sample variants from a BAM file, apply QA and calling filters, post-filter, and export the results to a VCF file.
// Input: sample.bam, genome_reference
// Container: quay.io/biocontainers/bioconductor-varianttools:1.51.0--r45hdfd78af_0
// R packages: GenomicRanges, Rsamtools, VariantAnnotation, gmapR, VariantTools
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VARIANTTOOLS_SINGLE_SAMPLE_CALLING {
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
    .bm_deps <- c("GenomicRanges", "Rsamtools", "VariantAnnotation", "gmapR", "VariantTools")
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
    library(gmapR)
    library(VariantAnnotation)
    library(GenomicRanges)
    library(Rsamtools)
    
    # Define input files
    bam_file <- "sample.bam"
    genome_ref <- "genome_reference"
    
    # Check if input files exist
    if (!file.exists(bam_file)) {
      stop("Error: 'sample.bam' not found in the working directory.")
    }
    if (!file.exists(genome_ref) && !dir.exists(genome_ref)) {
      stop("Error: 'genome_reference' not found in the working directory.")
    }
    
    # Load or construct the GmapGenome object
    genome <- tryCatch({
      if (dir.exists(genome_ref)) {
        gmapR::GmapGenome(path = genome_ref)
      } else {
        # Try reading as RDS first
        tryCatch({
          readRDS(genome_ref)
        }, error = function(e) {
          # Otherwise treat as FASTA and create GmapGenome
          gmapR::GmapGenome(reference = genome_ref, create = TRUE)
        })
      }
    }, error = function(err) {
      stop("Failed to load or construct GmapGenome: ", err\$message)
    })
    
    # Extract genomic ranges from BAM header to restrict tallying
    bam_header <- Rsamtools::scanBamHeader(bam_file)
    targets <- bam_header[[1]]\$targets
    which_ranges <- GenomicRanges::GRanges(names(targets), IRanges::IRanges(1, targets))
    
    # 1. Define tally parameters using TallyVariantsParam
    tally.param <- TallyVariantsParam(genome, 
                                      high_base_quality = 23L,
                                      which = which_ranges,
                                      indels = TRUE, read_length = 75L)
    
    # 2. Tally variants from BAM using tallyVariants
    tallies_H1993 <- tallyVariants(bam_file, tally.param)
    
    # 3. Apply QA filters using qaVariants
    qa.variants <- qaVariants(tallies_H1993)
    
    # 4. Call variants using callVariants
    called.variants <- callVariants(qa.variants)
    
    # 5. Post-filter variants using postFilterVariants
    pf.variants <- postFilterVariants(called.variants)
    
    # Save intermediate and final R objects
    saveRDS(tallies_H1993, "tallies_H1993.rds")
    saveRDS(qa.variants, "qa_variants.rds")
    saveRDS(called.variants, "called_variants.rds")
    saveRDS(pf.variants, "pf_variants.rds")
    
    # Export tables to CSV
    write.csv(as.data.frame(called.variants), "called_variants.csv", row.names = FALSE)
    write.csv(as.data.frame(pf.variants), "pf_variants.csv", row.names = FALSE)
    
    # 6. Export called variants to VCF using asVCF and writeVcf
    sampleNames(called.variants) <- "H1993"
    mcols(called.variants) <- NULL
    vcf <- asVCF(called.variants)
    writeVcf(vcf, "H1993.vcf", index = TRUE)

    writeLines(c(
        '"BIOC_VARIANTTOOLS_SINGLE_SAMPLE_CALLING":',
        paste0('        varianttools: ', as.character(packageVersion("varianttools")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_sample_calling.csv versions.yml
    """
}

workflow BIOC_VARIANTTOOLS_SINGLE_SAMPLE_CALLING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample.bam, genome_reference ] ]

    main:
    BIOC_VARIANTTOOLS_SINGLE_SAMPLE_CALLING(ch_input)

    emit:
    tables   = BIOC_VARIANTTOOLS_SINGLE_SAMPLE_CALLING.out.tables
    plots    = BIOC_VARIANTTOOLS_SINGLE_SAMPLE_CALLING.out.plots
    objects  = BIOC_VARIANTTOOLS_SINGLE_SAMPLE_CALLING.out.objects
    versions = BIOC_VARIANTTOOLS_SINGLE_SAMPLE_CALLING.out.versions
}
