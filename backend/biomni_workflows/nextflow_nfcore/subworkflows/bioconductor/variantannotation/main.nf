#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: VariantAnnotation
// Annotate variants, compute amino acid coding changes, predict coding outcomes.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/VariantAnnotation/inst/doc/VariantAnnotation.R
// Upstream  : AnnotationHub, GenomicRanges, ggplot2, microbenchmark, rjsoncons
// Downstream: alabaster.vcf, CNVrd2, deepSNV, demuxSNP, HelloRanges
//
// Install: BiocManager::install("VariantAnnotation")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VARIANTANNOTATION {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-variantannotation"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-variantannotation:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-variantannotation:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_variantannotation_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_variantannotation_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_variantannotation_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRanges)
    library(ScanVcfParam)
    library(TabixFile)
    library(jsonlite)

    # --- Import VCF Data [] ---
    # Key functions: readVcf
    library(VariantAnnotation)
    fl <- system.file("extdata", "chr22.vcf.gz", package="VariantAnnotation")
    vcf <- readVcf(fl, "hg19")
    # --- Extract VCF Sample Names [] ---
    # Key functions: samples, geno
    samples(header(vcf))
    geno(header(vcf))
    # --- Extract Fixed VCF Fields [] ---
    # Key functions: ref, qual
    ref(vcf)[1:5]
    qual(vcf)[1:5]
    # --- Access genotype data from VCF [] ---
    # Key functions: geno
    geno(vcf)
    sapply(geno(vcf), class)
    # --- Query dbSNP Annotations [] ---
    # Key functions: snpsBySeqname, mcols
    library(SNPlocs.Hsapiens.dbSNP144.GRCh37)
    vcf_rsids <- names(rowRanges(vcf))
    chr22snps <- snpsBySeqname(SNPlocs.Hsapiens.dbSNP144.GRCh37, "22")
    # --- Access INFO field from VCF [] ---
    # Key functions: info
    info(header(vcf))[c("VT", "LDAF", "RSQ"),]
    # --- examine ggplot2 [] ---
    # Key functions: ggplot, geom_density, scale_x_continuous, scale_y_continuous, theme
    library(ggplot2)
    ggplot(metrics, aes(x=RSQ, fill=in_dbSNP)) +
    geom_density(alpha=0.5) +
    # --- Define Genomic Regions for Subsetting [] ---
    # Key functions: GRanges
    rng <- GRanges(seqnames="22", ranges=IRanges(
    start=c(50301422, 50989541),
    end=c(50312106, 51001328),
    # --- Import VCF Subset via Tabix [] ---
    # Key functions: TabixFile, readVcf
    tab <- TabixFile(fl)
    vcf_rng <- readVcf(tab, "hg19", param=rng)
    head(rowRanges(vcf_rng), 3)
    # --- Inspect VCF Header [] ---
    # Key functions: scanVcfHeader
    hdr <- scanVcfHeader(fl)
    head(info(hdr), 3)
    head(geno(hdr), 3)
    # --- Define VCF Import Parameters [] ---
    # Key functions: ScanVcfParam, readVcf
    svp <- ScanVcfParam(info="LDAF", geno="GT")
    vcf1 <- readVcf(fl, "hg19", svp)
    names(geno(vcf1))
    # --- subset ScanVcfParam new [] ---
    # Key functions: ScanVcfParam
    svp_all <- ScanVcfParam(info="LDAF", geno="GT", which=rng)
    # --- Harmonize Chromosome Names [] ---
    # Key functions: seqlevels, rowRanges, locateVariants
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    seqlevels(vcf) <- "chr22"
    rd <- rowRanges(vcf)
    # --- Locate variants in genomic features [] ---
    # Key functions: locateVariants
    allvar <- locateVariants(rd, txdb, AllVariants())
    # --- Group Variants by Gene [] ---
    # Key functions: split
    splt <- split(mcols(loc)$GENEID, mcols(loc)$QUERYID)
    table(sapply(splt, function(x) length(unique(x)) > 1))
    splt <- split(mcols(loc)$QUERYID, mcols(loc)$GENEID)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_variantannotation_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_variantannotation_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_variantannotation_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_VARIANTANNOTATION:", paste0("    variantannotation: ", packageVersion("VariantAnnotation"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_variantannotation_results.csv
    touch ${prefix}_variantannotation_output.rds
    echo "BIOC_VARIANTANNOTATION:" > versions.yml
    echo "    variantannotation: 0.0.0" >> versions.yml
    """
}


workflow BIOC_VARIANTANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_VARIANTANNOTATION(ch_input)

    emit:
    results  = BIOC_VARIANTANNOTATION.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_VARIANTANNOTATION.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_VARIANTANNOTATION.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_VARIANTANNOTATION.out.versions  // channel: path(versions.yml)
}
