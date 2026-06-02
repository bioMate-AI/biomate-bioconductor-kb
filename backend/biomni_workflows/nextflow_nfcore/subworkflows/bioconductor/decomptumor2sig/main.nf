#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: decompTumor2Sig
// Uses quadratic programming for signature refitting, i.e., to decompose the mutation catalog from an 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/decompTumor2Sig/inst/doc/decompTumor2Sig.R
// Upstream  : GenomicRanges, VariantAnnotation, knitr
// Downstream: none
//
// Install: BiocManager::install("decompTumor2Sig")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DECOMPTUMOR2SIG {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-decomptumor2sig"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-decomptumor2sig:2.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-decomptumor2sig:2.22.0--r44_0'}"

    input:
    tuple val(meta), path(deseq2results)

    output:
    tuple val(meta), path("${meta.id}_decomptumor2sig_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_decomptumor2sig_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_decomptumor2sig_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(decompTumor2Sig)
    library(jsonlite)

    # --- Load Mutational Signatures [] ---
    # Key functions: readAlexandrovSignatures, convertAlexandrov2Shiraishi, readShiraishiSignatures
    sig_alex <- readAlexandrovSignatures()
    sig_shiraishi <- convertAlexandrov2Shiraishi(sig_alex)
    sig_files <- system.file(
        "extdata",
        paste0("Nik-Zainal_PMID_22608084-pmsignature-sig", 1:4, ".tsv"),
        package = "decompTumor2Sig"
    )
    signatures <- readShiraishiSignatures(files = sig_files)

    # --- Load Tumor Genomes [] ---
    # Key functions: readGenomesFromVCF, readGenomesFromMPF, getGenomesFromMutFeatData
    ref_genome <- BSgenome.Hsapiens.UCSC.hg19::BSgenome.Hsapiens.UCSC.hg19
    tx_db <- TxDb.Hsapiens.UCSC.hg19.knownGene::TxDb.Hsapiens.UCSC.hg19.knownGene
    vcf_file <- system.file(
        "extdata",
        "Nik-Zainal_PMID_22608084-VCF-convertedfromMPF.vcf.gz",
        package = "decompTumor2Sig"
    )
    genomes <- readGenomesFromVCF(
        vcf_file, numBases = 5, type = "Shiraishi",
        trDir = TRUE, refGenome = ref_genome,
        transcriptAnno = tx_db, verbose = FALSE
    )

    # --- Signature Adjustment [] ---
    # Key functions: adjustSignaturesForRegionSet
    tx_db <- TxDb.Hsapiens.UCSC.hg19.knownGene::TxDb.Hsapiens.UCSC.hg19.knownGene
    ref_genome <- BSgenome.Hsapiens.UCSC.hg19::BSgenome.Hsapiens.UCSC.hg19
    regions_target <- GenomicRanges::promoters(
        tx_db, upstream = 2000, downstream = 200
    )
    signatures <- readAlexandrovSignatures()
    sign_adj <- adjustSignaturesForRegionSet(
        signatures, regions_target, regionsOriginal = NULL,
        refGenome = ref_genome
    )

    # --- Mutational Signature Decomposition [] ---
    # Key functions: decomposeTumorGenomes, getGenomesFromMutFeatData
    sig_files <- system.file(
        "extdata",
        paste0("Nik-Zainal_PMID_22608084-pmsignature-sig", 1:4, ".tsv"),
        package = "decompTumor2Sig"
    )
    signatures <- readShiraishiSignatures(files = sig_files)
    pmsigdata <- system.file(
        "extdata",
        "Nik-Zainal_PMID_22608084-pmsignature-G.Rdata",
        package = "decompTumor2Sig"
    )
    load(pmsigdata)
    genomes <- getGenomesFromMutFeatData(G, normalize = TRUE)
    decomp <- decomposeTumorGenomes(genomes, signatures, verbose = FALSE)

    # --- Visualisation [] ---
    # Key functions: plotMutationDistribution, plotDecomposedContribution
    sig_files <- system.file(
        "extdata",
        paste0("Nik-Zainal_PMID_22608084-pmsignature-sig", 1:4, ".tsv"),
        package = "decompTumor2Sig"
    )
    signatures <- readShiraishiSignatures(files = sig_files)
    plotMutationDistribution(signatures[[1]])


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_decomptumor2sig_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_decomptumor2sig_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_decomptumor2sig_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DECOMPTUMOR2SIG:", paste0("    decomptumor2sig: ", packageVersion("decompTumor2Sig"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_decomptumor2sig_results.csv
    touch ${prefix}_decomptumor2sig_output.rds
    echo "BIOC_DECOMPTUMOR2SIG:" > versions.yml
    echo "    decomptumor2sig: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DECOMPTUMOR2SIG_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(deseq2results) ]

    main:
    BIOC_DECOMPTUMOR2SIG(ch_input)

    emit:
    results  = BIOC_DECOMPTUMOR2SIG.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DECOMPTUMOR2SIG.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DECOMPTUMOR2SIG.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DECOMPTUMOR2SIG.out.versions  // channel: path(versions.yml)
}
