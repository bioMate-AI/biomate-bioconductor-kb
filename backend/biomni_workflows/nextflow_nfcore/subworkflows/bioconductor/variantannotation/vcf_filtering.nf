#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: VariantAnnotation — vcf_filtering
// Filter a large VCF file using prefilters (fast string matching) and filters (parsed VCF evaluation) to write a smaller VCF file.
// Input: chr7-sub.vcf.gz, chr7-sub.vcf.gz.tbi
// Container: quay.io/biocontainers/bioconductor-variantannotation:1.56.0--r45h01b2380_0
// R packages: VariantAnnotation
// Bioconductor: 3.20 | R: 4.4
// Requires: VariantAnnotation
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Define prefilter functions using fast string matching
//  * 2. [Visualization & Output] Define filter functions evaluating parsed VCF objects
//  * 3. [Visualization & Output] Combine prefilters and filters using FilterRules
//  * 4. [Visualization & Output] Set up a TabixFile with a specified yieldSize for
//  * 5. [Visualization & Output] Execute filtering and write the output to a destination

nextflow.enable.dsl = 2

process BIOC_VARIANTANNOTATION_VCF_FILTERING {
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
    .bm_deps <- c("VariantAnnotation", "SummarizedExperiment")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
        # Load required library
        library(VariantAnnotation)
        library(SummarizedExperiment)
        
        # --- Define prefilter functions using fast string matching ---
        isGermlinePrefilter <- function(x) {
          grepl("Germline", x, fixed=TRUE)
        }
        
        notInDbsnpPrefilter <- function(x) {
          !(grepl("dbsnp", x, fixed=TRUE))
        }
        
        # --- Define filter functions evaluating parsed VCF objects ---
        # AD (FORMAT Number=R) is parsed by VariantAnnotation as a samples-by-
        # variants matrix of per-allele depth vectors (each cell = c(ref, alt, ...)),
        # NOT a 3-D numeric array. Keep variants where the tumour (sample 1) OR the
        # normal (sample 2) shows an alternate-allele fraction > 0.1.
        allelicDepth <- function(x) {
          ad <- geno(x)\$AD                       # dim: [variants x samples], list cells
          altFrac <- function(cell) {
            v <- as.numeric(unlist(cell))
            if (length(v) < 2 || all(is.na(v)) || sum(v, na.rm=TRUE) == 0) return(NA_real_)
            sum(v[-1], na.rm=TRUE) / sum(v, na.rm=TRUE)   # alt depth / total depth
          }
          tumorPct <- vapply(ad[, 1], altFrac, numeric(1))
          normPct  <- if (ncol(ad) >= 2) vapply(ad[, 2], altFrac, numeric(1))
                      else rep(NA_real_, nrow(ad))
          test <- (!is.na(tumorPct) & tumorPct > 0.1) | (!is.na(normPct) & normPct > 0.1)
          as.vector(test)
        }
        
        # --- Combine prefilters and filters using FilterRules ---
        prefilters <- FilterRules(list(germline=isGermlinePrefilter, dbsnp=notInDbsnpPrefilter))
        filters <- FilterRules(list(isSNV=isSNV, AD=allelicDepth))
        
        # Define input files from the working directory
        file.gz <- "chr7-sub.vcf.gz"
        file.gz.tbi <- "chr7-sub.vcf.gz.tbi"
        
        # Define output destination file
        destination.file <- "filtered_chr7-sub.vcf"
        
        # --- Set up a TabixFile with a specified yieldSize for ---
        tabix.file <- TabixFile(file.gz, yieldSize=10000)
        
        # --- Execute filtering and write the output to a destination ---
        filterVcf(tabix.file, "hg19", destination.file, prefilters=prefilters, filters=filters, verbose=TRUE)
        
        # Read the filtered VCF back to verify and save as a meaningful RDS output
        filtered_vcf <- readVcf(destination.file, "hg19")
        saveRDS(filtered_vcf, "filtered_vcf_object.rds")
        
        # Write a summary table of the filtered variants
        filtered_ranges <- rowRanges(filtered_vcf)
        summary_df <- data.frame(
          CHROM = as.character(seqnames(filtered_ranges)),
          POS = start(filtered_ranges),
          REF = as.character(ref(filtered_vcf)),
          ALT = vapply(as.list(alt(filtered_vcf)), function(x) paste(as.character(x), collapse=","), character(1)),
          stringsAsFactors = FALSE
        )
        write.csv(summary_df, "filtered_variants_summary.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_VARIANTANNOTATION_VCF_FILTERING":',
        paste0('    VariantAnnotation: ', as.character(packageVersion('VariantAnnotation')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_vcf_filtering.csv versions.yml
    """
}

workflow BIOC_VARIANTANNOTATION_VCF_FILTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ chr7-sub.vcf.gz, chr7-sub.vcf.gz.tbi ] ]

    main:
    BIOC_VARIANTANNOTATION_VCF_FILTERING(ch_input)

    emit:
    tables   = BIOC_VARIANTANNOTATION_VCF_FILTERING.out.tables
    plots    = BIOC_VARIANTANNOTATION_VCF_FILTERING.out.plots
    objects  = BIOC_VARIANTANNOTATION_VCF_FILTERING.out.objects
    versions = BIOC_VARIANTANNOTATION_VCF_FILTERING.out.versions
}
