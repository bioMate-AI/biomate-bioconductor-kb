#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: deepsnv — shearwater_ml
// Call subclonal mutations across multiple BAM files using the Shearwater ML maximum-likelihood algorithm and output a VCF file.
// Input: files
// Container: quay.io/biocontainers/bioconductor-deepsnv:1.56.0--r45ha27e39d_0
// R packages: GenomicRanges, Rsamtools, VariantAnnotation, deepSNV
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DEEPSNV_SHEARWATER_ML {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-deepsnv:1.56.0--r45ha27e39d_0"

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
    .bm_deps <- c("GenomicRanges", "Rsamtools", "VariantAnnotation", "deepSNV")
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
    library(Rsamtools)
    library(VariantAnnotation)
    
    # 1. Define genomic regions of interest dynamically from input BAM files
    # Find all BAM files in the working directory
    files <- list.files(pattern = "\\\\.bam\$", full.names = TRUE)
    if (length(files) == 0) {
      stop("Error: No BAM files found in the working directory.")
    }
    
    # Read BAM header to get a valid chromosome and region
    header <- scanBamHeader(files[1])
    targets <- header[[1]]\$targets
    if (length(targets) == 0) {
      stop("Error: No targets found in the BAM header.")
    }
    
    # Use the first chromosome and define a region (e.g., first 1000 bp)
    chr <- names(targets)[1]
    start_pos <- 1
    end_pos <- min(1000, targets[1])
    regions <- GRanges(chr, IRanges(start = start_pos, end = end_pos))
    
    # 2. Load count data from BAM files
    counts <- loadAllData(files, regions, q=30)
    
    # 3. Compute p-values using the beta-binomial Likelihood Ratio Test
    pvals <- betabinLRT(counts, rho=1e-4, maxtruncate = 1)\$pvals
    
    # 4. Adjust p-values for multiple testing
    qvals <- p.adjust(pvals, method="BH")
    dim(qvals) = dim(pvals)
    
    # 5. Convert results to VCF format
    vcfML = qvals2Vcf(qvals, counts, regions, samples = files, mvcf = TRUE)
    
    # Save outputs
    writeVcf(vcfML, "shearwater_ml_results.vcf")
    saveRDS(pvals, "pvals.rds")
    saveRDS(qvals, "qvals.rds")

    writeLines(c(
        '"BIOC_DEEPSNV_SHEARWATER_ML":',
        paste0('        deepsnv: ', as.character(packageVersion("deepsnv")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_shearwater_ml.csv versions.yml
    """
}

workflow BIOC_DEEPSNV_SHEARWATER_ML_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ files ] ]

    main:
    BIOC_DEEPSNV_SHEARWATER_ML(ch_input)

    emit:
    tables   = BIOC_DEEPSNV_SHEARWATER_ML.out.tables
    plots    = BIOC_DEEPSNV_SHEARWATER_ML.out.plots
    objects  = BIOC_DEEPSNV_SHEARWATER_ML.out.objects
    versions = BIOC_DEEPSNV_SHEARWATER_ML.out.versions
}
