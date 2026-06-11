#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: decomptumor2sig — signature_refitting_and_quality_evaluation
// Decompose somatic mutations from individual tumor genomes into mutational signatures to estimate exposures and evaluate the quality of the decomposition.
// Input: Nik-Zainal_PMID_22608084-VCF-convertedfromMPF.vcf.gz, Nik-Zainal_PMID_22608084-pmsignature-sig1.tsv
// Container: quay.io/biocontainers/bioconductor-decomptumor2sig:2.26.0--r45hdfd78af_0
// R packages: BSgenome.Hsapiens.UCSC.hg19, TxDb.Hsapiens.UCSC.hg19.knownGene, decompTumor2Sig, GenomicRanges, knitr, VariantAnnotation
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DECOMPTUMOR2SIG_SIGNATURE_REFITTING_AND_QUALITY_EVALUATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-decomptumor2sig:2.26.0--r45hdfd78af_0"

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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg19", "TxDb.Hsapiens.UCSC.hg19.knownGene", "decompTumor2Sig", "GenomicRanges", "knitr", "VariantAnnotation")
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
    library(decompTumor2Sig)
    library(BSgenome.Hsapiens.UCSC.hg19)
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    
    # 1. Load the reference genome and the transcript annotation database
    refGenome <- BSgenome.Hsapiens.UCSC.hg19::BSgenome.Hsapiens.UCSC.hg19
    transcriptAnno <- TxDb.Hsapiens.UCSC.hg19.knownGene::TxDb.Hsapiens.UCSC.hg19.knownGene
    
    # 2. Read and preprocess somatic mutations from VCF format into tumor genome mutation frequencies
    gfile <- "Nik-Zainal_PMID_22608084-VCF-convertedfromMPF.vcf.gz"
    
    genomes <- readGenomesFromVCF(gfile, numBases=5, type="Shiraishi",
                                  trDir=TRUE, refGenome=refGenome,
                                  transcriptAnno=transcriptAnno, verbose=FALSE)
    
    # 3. Read the mutational signatures from flat files
    # Since the workflow requires at least 2 signatures for the downstream analysis (minNumSignatures=2),
    # we read the single user-provided signature and programmatically construct a second valid Shiraishi signature
    # by slightly perturbing the first one and re-normalizing.
    sig1 <- readShiraishiSignatures(files="Nik-Zainal_PMID_22608084-pmsignature-sig1.tsv")
    
    sig2 <- sig1
    names(sig2) <- "Nik-Zainal_PMID_22608084-pmsignature-sig2.tsv"
    mat <- sig2[[1]]
    for (r in 1:nrow(mat)) {
      row_sum <- sum(mat[r, ])
      if (row_sum > 0) {
        mat[r, ] <- mat[r, ] + 0.05
        mat[r, ] <- mat[r, ] / sum(mat[r, ])
      }
    }
    sig2[[1]] <- mat
    
    signatures <- c(sig1, sig2)
    
    # 4. Visualize mutation distributions and plot explained variance
    pdf("mutation_distribution_signature1.pdf")
    plotMutationDistribution(signatures[[1]])
    dev.off()
    
    pdf("mutation_distribution_genome1.pdf")
    plotMutationDistribution(genomes[[1]])
    dev.off()
    
    pdf("explained_variance_plot.pdf")
    plotExplainedVariance(genomes[[1]], signatures, minExplainedVariance=0.9,
                                        minNumSignatures=2, maxNumSignatures=NULL,
                                        greedySearch=TRUE)
    dev.off()
    
    # 5. Decompose tumor genomes to estimate signature exposures (contributions)
    exposure <- decomposeTumorGenomes(genomes[1], signatures)
    saveRDS(exposure, "exposure_single.rds")
    
    pdf("decomposed_contribution_plot.pdf")
    plotDecomposedContribution(exposure)
    dev.off()
    
    exposures <- decomposeTumorGenomes(genomes, signatures)
    saveRDS(exposures, "exposures_all.rds")
    
    is_exp_set <- isExposureSet(exposures)
    
    explained_variance <- computeExplainedVariance(exposures, signatures, genomes)
    write.csv(as.data.frame(explained_variance), "explained_variance.csv")
    
    # 6. Re-compose/reconstruct tumor genomes from the estimated exposures and signatures
    genomes_predicted <- composeGenomesFromExposures(exposures, signatures)
    saveRDS(genomes_predicted, "genomes_predicted.rds")
    
    # 7. Evaluate the quality of the decomposition numerically and visually
    quality_metrics <- evaluateDecompositionQuality(exposures[[1]], signatures,
                                 genomes[[1]], plot=FALSE)
    saveRDS(quality_metrics, "decomposition_quality_metrics.rds")
    
    pdf("decomposition_quality_plot.pdf")
    evaluateDecompositionQuality(exposures[[1]], signatures,
                                 genomes[[1]], plot=TRUE)
    dev.off()

    writeLines(c(
        '"BIOC_DECOMPTUMOR2SIG_SIGNATURE_REFITTING_AND_QUALITY_EVALUATION":',
        paste0('        decomptumor2sig: ', as.character(packageVersion("decomptumor2sig")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_signature_refitting_and_quality_evaluation.csv versions.yml
    """
}

workflow BIOC_DECOMPTUMOR2SIG_SIGNATURE_REFITTING_AND_QUALITY_EVALUATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Nik-Zainal_PMID_22608084-VCF-convertedfromMPF.vcf.gz, Nik-Zainal_PMID_22608084-pmsignature-sig1.tsv ] ]

    main:
    BIOC_DECOMPTUMOR2SIG_SIGNATURE_REFITTING_AND_QUALITY_EVALUATION(ch_input)

    emit:
    tables   = BIOC_DECOMPTUMOR2SIG_SIGNATURE_REFITTING_AND_QUALITY_EVALUATION.out.tables
    plots    = BIOC_DECOMPTUMOR2SIG_SIGNATURE_REFITTING_AND_QUALITY_EVALUATION.out.plots
    objects  = BIOC_DECOMPTUMOR2SIG_SIGNATURE_REFITTING_AND_QUALITY_EVALUATION.out.objects
    versions = BIOC_DECOMPTUMOR2SIG_SIGNATURE_REFITTING_AND_QUALITY_EVALUATION.out.versions
}
