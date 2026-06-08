#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: VariantAnnotation — genotype_to_snpmatrix
// Convert VCF genotype calls or genotype likelihoods into a SnpMatrix object for downstream genetic association analysis.
// Input: chr22.vcf.gz, gl_chr1.vcf
// Container: quay.io/biocontainers/bioconductor-variantannotation:1.56.0--r45h01b2380_0
// Requires: VariantAnnotation
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read the VCF file. 2. Convert called genotypes (GT) to a SnpMatrix using genotypeToSnpMatrix. 3. Convert genotype likelihoods (GL)

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
        
    library(VariantAnnotation)
    
    # 1. Read the VCF file with GT calls from the working directory
    fl <- "chr22.vcf.gz"
    vcf <- readVcf(fl, "hg19")
    
    # 2. Convert called genotypes (GT) to a SnpMatrix
    res <- genotypeToSnpMatrix(vcf)
    
    # Save the GT results
    saveRDS(res, "gt_snpmatrix_result.rds")
    gt_map <- as.data.frame(res\$map)
    gt_map\$allele.1 <- as.character(res\$map\$allele.1)
    gt_map\$allele.2 <- vapply(as.list(res\$map\$allele.2), function(x) paste(as.character(x), collapse=","), character(1))
    write.csv(gt_map, "gt_map.csv", row.names=TRUE)
    
    # 3. Read the VCF file with GL likelihoods from the working directory
    fl.gl <- "gl_chr1.vcf"
    vcf.gl <- readVcf(fl.gl, "hg19")
    
    # 4. Convert genotype likelihoods (GL) to a SnpMatrix using uncertain=TRUE
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
