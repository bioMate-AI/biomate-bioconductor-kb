#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: deepSNV — shearwater_ml_variant_calling
// Call mutations across multiple samples using the maximum-likelihood Shearwater ML algorithm without prior information.
// Input: test.bam, control.bam
// Container: quay.io/biocontainers/bioconductor-deepsnv:1.56.0--r45ha27e39d_0
// Requires: GenomicRanges, Rsamtools, VariantAnnotation, deepSNV
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define genomic regions of interest
//  * 2. [Input & Preparation] Load count data from BAM files using loadAllData
//  * 3. [Core Analysis] Compute p-values for each possible mutation using betabinLRT
//  * 4. [Core Analysis] Adjust p-values for multiple testing
//  * 5. [Visualization & Output] Export significant variants to VCF format using qvals2Vcf

nextflow.enable.dsl = 2

process BIOC_DEEPSNV_SHEARWATER_ML_VARIANT_CALLING {
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
    .bm_deps <- c("GenomicRanges", "Rsamtools", "VariantAnnotation", "deepSNV")
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
    
    # Load required libraries
    library(deepSNV)
    library(GenomicRanges)
    library(VariantAnnotation)
    library(Rsamtools)
    
    # Reading exactly the user-specified files from the working directory
    files <- c("test.bam", "control.bam")
    
    if (!all(file.exists(files))) {
      stop("Error: Both 'test.bam' and 'control.bam' must be present in the working directory.")
    }
    
    # 1. Define genomic regions of interest dynamically from the BAM header
    # This ensures the script works on generic user-provided BAM files
    targets <- scanBamHeader(files[1])[[1]]\$targets
    regions <- GRanges(seqnames = names(targets), IRanges(start = 1, end = unname(targets)))
    
    # 2. Load count data from BAM files using loadAllData
    counts <- loadAllData(files, regions, q=30)
    
    # 3. Compute p-values for each possible mutation using betabinLRT
    pvals <- betabinLRT(counts, rho=1e-4, maxtruncate = 1)\$pvals
    
    # 4. Adjust p-values for multiple testing
    qvals <- p.adjust(pvals, method="BH")
    dim(qvals) = dim(pvals)
    
    # 5. Export significant variants to VCF format using qvals2Vcf
    vcfML = qvals2Vcf(qvals, counts, regions, samples = files, mvcf = TRUE)
    
    # Write outputs
    # Save the VCF object to a file
    writeVcf(vcfML, "shearwater_ml_variants.vcf")
    
    # Save the raw results as an RDS object for downstream analysis
    saveRDS(list(counts = counts, pvals = pvals, qvals = qvals, vcf = vcfML), "shearwater_ml_results.rds")
    
    # Export a summary table of the variants
    if (length(vcfML) > 0) {
      vcf_df <- as.data.frame(rowRanges(vcfML))
      write.csv(vcf_df, "significant_variants_summary.csv", row.names = FALSE)
    } else {
      write.csv(data.frame(Status = "No significant variants called"), "significant_variants_summary.csv", row.names = FALSE)
    }

    writeLines(c(
        '"BIOC_DEEPSNV_SHEARWATER_ML_VARIANT_CALLING":',
        paste0('    deepSNV: ', as.character(packageVersion('deepSNV')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_shearwater_ml_variant_calling.csv versions.yml
    """
}

workflow BIOC_DEEPSNV_SHEARWATER_ML_VARIANT_CALLING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ test.bam, control.bam ] ]

    main:
    BIOC_DEEPSNV_SHEARWATER_ML_VARIANT_CALLING(ch_input)

    emit:
    tables   = BIOC_DEEPSNV_SHEARWATER_ML_VARIANT_CALLING.out.tables
    plots    = BIOC_DEEPSNV_SHEARWATER_ML_VARIANT_CALLING.out.plots
    objects  = BIOC_DEEPSNV_SHEARWATER_ML_VARIANT_CALLING.out.objects
    versions = BIOC_DEEPSNV_SHEARWATER_ML_VARIANT_CALLING.out.versions
}
