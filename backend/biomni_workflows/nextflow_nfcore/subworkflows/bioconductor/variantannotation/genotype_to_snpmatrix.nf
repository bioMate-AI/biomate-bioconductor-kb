#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: VariantAnnotation — genotype_to_snpmatrix
// Convert VCF genotype calls or genotype likelihoods into a SnpMatrix object for downstream genetic association analysis.
// Input: chr22.vcf.gz, gl_chr1.vcf
// Container: quay.io/biocontainers/bioconductor-variantannotation:1.56.0--r45h01b2380_0
// R packages: VariantAnnotation
// Bioconductor: 3.20 | R: 4.4
// Requires: VariantAnnotation
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read the VCF file with GT calls from the working directory
//  * 2. [Input & Preparation] Convert called genotypes (GT) to a SnpMatrix
//  * 3. [Input & Preparation] Read the VCF file with GL likelihoods from the working
//  * 4. [Input & Preparation] Convert genotype likelihoods (GL) to a SnpMatrix using

nextflow.enable.dsl = 2

process BIOC_VARIANTANNOTATION_GENOTYPE_TO_SNPMATRIX {
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
    .bm_deps <- c("VariantAnnotation")
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
        
    library(VariantAnnotation)
    
    # --- Read the VCF file with GT calls from the working directory ---
    fl <- "chr22.vcf.gz"
    vcf <- readVcf(fl, "hg19")
    
    # --- Convert called genotypes (GT) to a SnpMatrix ---
    res <- genotypeToSnpMatrix(vcf)
    
    # Save the GT results
    saveRDS(res, "gt_snpmatrix_result.rds")
    gt_map <- as.data.frame(res\$map)
    gt_map\$allele.1 <- as.character(res\$map\$allele.1)
    gt_map\$allele.2 <- vapply(as.list(res\$map\$allele.2), function(x) paste(as.character(x), collapse=","), character(1))
    write.csv(gt_map, "gt_map.csv", row.names=TRUE)
    
    # --- Read the VCF file with GL likelihoods from the working ---
    fl.gl <- "gl_chr1.vcf"
    vcf.gl <- readVcf(fl.gl, "hg19")
    
    # --- Convert genotype likelihoods (GL) to a SnpMatrix using ---
    res <- genotypeToSnpMatrix(vcf.gl, uncertain=TRUE)
    
    # Save the GL results
    saveRDS(res, "gl_snpmatrix_result.rds")
    gl_map <- as.data.frame(res\$map)
    gl_map\$allele.1 <- as.character(res\$map\$allele.1)
    gl_map\$allele.2 <- vapply(as.list(res\$map\$allele.2), function(x) paste(as.character(x), collapse=","), character(1))
    write.csv(gl_map, "gl_map.csv", row.names=TRUE)

    writeLines(c(
        '"BIOC_VARIANTANNOTATION_GENOTYPE_TO_SNPMATRIX":',
        paste0('    VariantAnnotation: ', as.character(packageVersion('VariantAnnotation')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genotype_to_snpmatrix.csv versions.yml
    """
}

workflow BIOC_VARIANTANNOTATION_GENOTYPE_TO_SNPMATRIX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ chr22.vcf.gz, gl_chr1.vcf ] ]

    main:
    BIOC_VARIANTANNOTATION_GENOTYPE_TO_SNPMATRIX(ch_input)

    emit:
    tables   = BIOC_VARIANTANNOTATION_GENOTYPE_TO_SNPMATRIX.out.tables
    plots    = BIOC_VARIANTANNOTATION_GENOTYPE_TO_SNPMATRIX.out.plots
    objects  = BIOC_VARIANTANNOTATION_GENOTYPE_TO_SNPMATRIX.out.objects
    versions = BIOC_VARIANTANNOTATION_GENOTYPE_TO_SNPMATRIX.out.versions
}
