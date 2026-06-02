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

    # --- Pmsignature [] ---
    # Key functions: pmsignature, getSignaturesFromEstParam
    ---------------------------------------------------------------------
    # load example signatures for breast cancer genomes from Nik-Zainal et al
    # (PMID: 22608084) in the format produced by pmsignature (PMID: 26630308)
    pmsigdata <- system.file("extdata",
              "Nik-Zainal_PMID_22608084-pmsignature-Param.Rdata",
    # --- Isalexandrovset [] ---
    # Key functions: isAlexandrovSet, isSignatureSet, isShiraishiSet, sameSignatureFormat
    ---------------------------------------------------------------------
    isAlexandrovSet(sign_a)
    isSignatureSet(sign_a)
    isShiraishiSet(sign_s)
    isSignatureSet(sign_s)
    # --- Al [] ---
    # Key functions: al, readGenomesFromVCF
    ---------------------------------------------------------------------
    # load the reference genome and the transcript annotation database
    refGenome <- BSgenome.Hsapiens.UCSC.hg19::BSgenome.Hsapiens.UCSC.hg19
    transcriptAnno <-
               TxDb.Hsapiens.UCSC.hg19.knownGene::TxDb.Hsapiens.UCSC.hg19.knownGene
    # --- Al [] ---
    # Key functions: al, readGenomesFromMPF
    ---------------------------------------------------------------------
    # load the reference genome and the transcript annotation database
    refGenome <- BSgenome.Hsapiens.UCSC.hg19::BSgenome.Hsapiens.UCSC.hg19
    transcriptAnno <-
               TxDb.Hsapiens.UCSC.hg19.knownGene::TxDb.Hsapiens.UCSC.hg19.knownGene
    # --- Al [] ---
    # Key functions: al, pmsignature, getGenomesFromMutFeatData
    ---------------------------------------------------------------------
    # get breast cancer genomes from Nik-Zainal et al (PMID: 22608084)
    # in the format produced by pmsignature (PMID: 26630308)
    pmsigdata <- system.file("extdata",
                             "Nik-Zainal_PMID_22608084-pmsignature-G.Rdata",
    # --- Readalexandrovsignatures [] ---
    # Key functions: readAlexandrovSignatures, plotMutationDistribution
    ---------------------------------------------------------------------
    signatures <- readAlexandrovSignatures()
    plotMutationDistribution(signatures[[1]])
    # --- Al [] ---
    # Key functions: al, readGenomesFromVCF
    ---------------------------------------------------------------------
    # load the reference genome and the transcript annotation database
    refGenome <- BSgenome.Hsapiens.UCSC.hg19::BSgenome.Hsapiens.UCSC.hg19
    transcriptAnno <-
               TxDb.Hsapiens.UCSC.hg19.knownGene::TxDb.Hsapiens.UCSC.hg19.knownGene
    # --- Decomposetumorgenomes [] ---
    # Key functions: decomposeTumorGenomes
    ---------------------------------------------------------------------
    exposure <- decomposeTumorGenomes(genomes[1], signatures)
    # --- Isexposureset [] ---
    # Key functions: isExposureSet
    ---------------------------------------------------------------------
    isExposureSet(exposures)
    # --- Decomposetumorgenomes [] ---
    # Key functions: decomposeTumorGenomes
    ---------------------------------------------------------------------
    exposures <- decomposeTumorGenomes(genomes[1], signatures,
                                       minExplainedVariance=0.9,
                                       minNumSignatures=2, maxNumSignatures=NULL,
                                       greedySearch=FALSE, verbose=TRUE)
    # --- Decomposetumorgenomes [] ---
    # Key functions: decomposeTumorGenomes, computeExplainedVariance
    ---------------------------------------------------------------------
    exposures <- decomposeTumorGenomes(genomes, signatures)
    computeExplainedVariance(exposures, signatures, genomes)
    # --- Composegenomesfromexposures [] ---
    # Key functions: composeGenomesFromExposures
    ---------------------------------------------------------------------
    genomes_predicted <- composeGenomesFromExposures(exposures, signatures)
    genomes_predicted[1:2]
    # --- Evaluatedecompositionquality [] ---
    # Key functions: evaluateDecompositionQuality
    ---------------------------------------------------------------------
    evaluateDecompositionQuality(exposures[[1]], signatures,
                                 genomes[[1]], plot=FALSE)
    # --- Al [] ---
    # Key functions: al, readShiraishiSignatures
    ---------------------------------------------------------------------
    # get 4 Shiraishi signatures from 21 breast cancers from
    # Nik-Zainal et al (PMID: 22608084)
    sigfiles <- system.file("extdata",
                     paste0("Nik-Zainal_PMID_22608084-pmsignature-sig",1:4,".tsv"),
    # --- Determinesignaturedistances [] ---
    # Key functions: determineSignatureDistances
    ---------------------------------------------------------------------
    determineSignatureDistances(fromSignature=sign_s4[[1]], toSignatures=sign_s15,
                                method="frobenius")

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
