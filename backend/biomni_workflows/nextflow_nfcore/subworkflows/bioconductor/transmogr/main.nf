#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: transmogR
// transmogR provides the tools needed to crate a new reference genome or reference transcriptome, usin
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/transmogR/inst/doc/creating_a_new_reference.R
// Upstream  : VariantAnnotation, extraChIPs, rtracklayer
// Downstream: none
//
// Install: BiocManager::install("transmogR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TRANSMOGR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-transmogr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-transmogr:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-transmogr:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_transmogr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_transmogr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_transmogr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(transmogR)
    library(jsonlite)


    # --- Chr1 [] ---
    # Key functions: getSeq, chr1
    chr1 <- getSeq(BSgenome.Hsapiens.UCSC.hg38, "chr1")
    chr1 <- as(chr1, "DNAStringSet")
    names(chr1) <- "chr1"
    chr1

    # --- Var [] ---
    # Key functions: seqinfo, genome, ScanVcfParam, GRanges, rowRanges, readVcf, transmogR
    sq <- seqinfo(chr1)
    genome(sq) <- "GRCh38"
    vcf <- system.file("extdata/1000GP_subset.vcf.gz", package = "transmogR")
    vcf_param <- ScanVcfParam(fixed = "ALT", info = NA, which = GRanges(sq))
    var <- rowRanges(readVcf(vcf, param = vcf_param))
    seqinfo(var) <- sq
    var

    # --- Gtf [] ---
    # Key functions: import.gff, GRanges, seqinfo, splitAsList, upsetVarByCol, defineRegions, granges, overlapsByVar
    f <- system.file("extdata/gencode.v44.subset.gtf.gz", package = "transmogR")
    gtf <- import.gff(f, which = GRanges(sq))
    seqinfo(gtf) <- sq
    gtf

    ## ----gtf-split----------------------------------------------------------------
    gtf <- splitAsList(gtf, gtf$type)

    ## ----upset-var, fig.cap = "Included variants which overlap exonic sequences, summarised by unique gene ids"----
    upsetVarByCol(gtf$exon, var, mcol = "gene_id")

    ## ----overlaps-by-var----------------------------------------------------------
    regions <- defineRegions(gtf$gene, gtf$transcript, gtf$exon, proximal = 0)
    regions$exon <- granges(gtf$exon)
    overlapsByVar(regions, var)

    # --- Sj [] ---
    # Key functions: sjFromExons, chopMC, transcript_id, transcript_name, gene_id, gene_name
    ec <- c("transcript_id", "transcript_name", "gene_id", "gene_name")
    sj <- sjFromExons(gtf$exon, extra_cols = ec)
    sj

    ## ----chop-sj------------------------------------------------------------------
    chopMC(sj)

    ## ----sj-as-gi-----------------------------------------------------------------
    sj <- sjFromExons(gtf$exon, extra_cols = ec, as = "GInteractions")
    subset(sj, transcript_name == "DDX11L17-201")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_transmogr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_transmogr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_transmogr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TRANSMOGR:", paste0("    transmogr: ", packageVersion("transmogR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_transmogr_results.csv
    touch ${prefix}_transmogr_output.rds
    echo "BIOC_TRANSMOGR:" > versions.yml
    echo "    transmogr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TRANSMOGR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TRANSMOGR(ch_input)

    emit:
    results  = BIOC_TRANSMOGR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TRANSMOGR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TRANSMOGR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TRANSMOGR.out.versions  // channel: path(versions.yml)
}
