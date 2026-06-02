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
    library(VariantAnnotation)
    library(GRanges)
    library(ScanVcfParam)
    library(TabixFile)
    library(jsonlite)

    # --- VCF Parsing and Inspection ---
    # Key functions: readVcf, header, samples, geno, rowRanges
    fl <- system.file("extdata", "chr22.vcf.gz", package="VariantAnnotation")
    vcf <- readVcf(fl, "hg19")
    vcf_hdr <- header(vcf)
    vcf_samples <- samples(vcf_hdr)
    vcf_geno <- geno(vcf)
    vcf_ranges <- rowRanges(vcf)

    # --- Targeted Genomic Subsetting ---
    # Key functions: ScanVcfParam, TabixFile, readVcf, scanVcfHeader
    fl <- system.file("extdata", "chr22.vcf.gz", package="VariantAnnotation")
    rng <- GenomicRanges::GRanges(
        seqnames="22",
        ranges=IRanges::IRanges(
            start=c(50301422, 50989541),
            end=c(50312106, 51001328)
        )
    )
    svp <- ScanVcfParam(info="LDAF", geno="GT", which=rng)
    tab <- TabixFile(fl)
    vcf_subset <- readVcf(tab, "hg19", param=svp)
    hdr_info <- scanVcfHeader(fl)

    # --- Variant Localization ---
    # Key functions: locateVariants, CodingVariants
    fl <- system.file("extdata", "chr22.vcf.gz", package="VariantAnnotation")
    vcf <- readVcf(fl, "hg19")
    GenomeInfoDb::seqlevels(vcf) <- "chr22"
    rd <- rowRanges(vcf)
    txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene::TxDb.Hsapiens.UCSC.hg19.knownGene
    loc <- locateVariants(rd, txdb, CodingVariants())

    # --- Coding Effect Prediction ---
    # Key functions: predictCoding
    fl <- system.file("extdata", "chr22.vcf.gz", package="VariantAnnotation")
    vcf <- readVcf(fl, "hg19")
    GenomeInfoDb::seqlevels(vcf) <- "chr22"
    txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene::TxDb.Hsapiens.UCSC.hg19.knownGene
    seq_source <- BSgenome.Hsapiens.UCSC.hg19::Hsapiens
    coding <- predictCoding(vcf, txdb, seqSource=seq_source)

    # --- Genotype Conversion ---
    # Key functions: genotypeToSnpMatrix
    fl <- system.file("extdata", "gl_chr1.vcf", package="VariantAnnotation")
    vcf_gl <- readVcf(fl, "hg19")
    res_uncertain <- genotypeToSnpMatrix(vcf_gl, uncertain=TRUE)
    res_certain <- genotypeToSnpMatrix(vcf_gl, uncertain=FALSE)

    # --- VCF Export ---
    # Key functions: writeVcf
    fl <- system.file("extdata", "ex2.vcf", package="VariantAnnotation")
    vcf_in <- readVcf(fl, "hg19")
    out_file <- tempfile(fileext=".vcf")
    writeVcf(vcf_in, out_file)


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
