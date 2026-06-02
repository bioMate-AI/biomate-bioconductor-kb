#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: biscuiteer
// A test harness for bsseq loading of Biscuit output, summarization of WGBS data over defined regions 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/biscuiteer/inst/doc/biscuiteer.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("biscuiteer")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BISCUITEER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biscuiteer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biscuiteer:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-biscuiteer:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biscuiteer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biscuiteer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biscuiteer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(biscuiteer)
    library(GRanges)
    library(IRanges)
    library(WGBSage)
    library(jsonlite)

    # --- Merge Datasets [] ---
    # Key functions: readBiscuit, unionize
    shuf_bed <- system.file("extdata", "MCF7_Cunha_chr11p15_shuffled.bed.gz",
                            package = "biscuiteer")
    shuf_vcf <- system.file("extdata",
                            "MCF7_Cunha_shuffled_header_only.vcf.gz",
                            package = "biscuiteer")
    bisc2 <- readBiscuit(BEDfile = shuf_bed, VCFfile = shuf_vcf,
                         merged = FALSE)
    comb <- unionize(bisc, bisc2)


    # --- Read Epibed Format [] ---
    # Key functions: readEpibed
    epibed_nome <- system.file("extdata", "hct116.nome.epibed.gz",
                               package = "biscuiteer")
    epibed_nome_gr <- readEpibed(epibed = epibed_nome,
                                 genome = "hg19",
                                 chr = "chr1")


    # --- Region Methylation Extraction [] ---
    # Key functions: getLogitFracMeth
    reg <- GenomicRanges::GRanges(
        seqnames = rep("chr11", 5),
        strand = rep("*", 5),
        ranges = IRanges::IRanges(
            start = c(0, 2.8e6, 1.17e7, 1.38e7, 1.69e7),
            end = c(2.8e6, 1.17e7, 1.38e7, 1.69e7, 2.2e7)
        )
    )
    frac <- getLogitFracMeth(bisc, minSamp = 1, r = reg)


    # --- Epigenetic Age Estimation [] ---
    # Key functions: WGBSage
    ages <- WGBSage(comb, "horvath")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biscuiteer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biscuiteer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biscuiteer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BISCUITEER:", paste0("    biscuiteer: ", packageVersion("biscuiteer"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biscuiteer_results.csv
    touch ${prefix}_biscuiteer_output.rds
    echo "BIOC_BISCUITEER:" > versions.yml
    echo "    biscuiteer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BISCUITEER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BISCUITEER(ch_input)

    emit:
    results  = BIOC_BISCUITEER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BISCUITEER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BISCUITEER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BISCUITEER.out.versions  // channel: path(versions.yml)
}
