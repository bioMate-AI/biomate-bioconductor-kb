#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: signeR — de_novo_signature_discovery
// Generate mutation count and opportunity matrices from genomic variants, estimate the optimal number of mutational signatures, and perform de novo signature disc
// Input: file.vcf, target.bed
// Container: quay.io/biocontainers/bioconductor-signer:2.12.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Hsapiens.UCSC.hg19, VariantAnnotation, rtracklayer, signeR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Generate mutation count matrix from VCF using genCountMatrixFromVcf
//  * 2. [Core Analysis] Generate opportunity matrix from reference genome and target regions using genOpportunityFromGenome
//  * 3. [Core Analysis] Run signeR to estimate signatures and exposures
//  * 4. [Visualization & Output] Plot BIC values to evaluate the optimal number of signatures using BICboxplot
//  * 5. [Visualization & Output] Plot MCMC paths, signatures, and exposures using Paths, SignPlot, SignHeat, ExposureBoxplot, ExposureBarplot, and ExposureHeat

nextflow.enable.dsl = 2

process BIOC_SIGNER_DE_NOVO_SIGNATURE_DISCOVERY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("VariantAnnotation", "BSgenome.Hsapiens.UCSC.hg19", "rtracklayer", "signeR")
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
        library(VariantAnnotation)
        library(BSgenome.Hsapiens.UCSC.hg19)
        library(rtracklayer)
        library(signeR)
        
        # 1. Generate mutation count matrix from VCF
        vcfobj <- readVcf("file.vcf", "hg19")
        mut <- genCountMatrixFromVcf(BSgenome.Hsapiens.UCSC.hg19, vcfobj)
        
        # 2. Generate opportunity matrix from reference genome and target regions
        target_regions <- import(con="target.bed", format="bed")
        opp <- genOpportunityFromGenome(BSgenome.Hsapiens.UCSC.hg19,
            target_regions, nsamples=nrow(mut))
        
        # 3. Run signeR to estimate signatures and exposures
        signatures <- signeR(M=mut, Opport=opp, main_eval=100, EM_eval=50, EMit_lim=20)
        
        # Save the generated signatures object and median exposures
        saveRDS(signatures, file="signatures_output.rds")
        
        tryCatch({
            median_exp <- Median_exp(signatures\$SignExposures)
            write.csv(median_exp, file="median_exposures.csv", row.names=TRUE)
        }, error = function(e) {
            message("Could not export median exposures: ", e\$message)
        })
        
        # 4. Plot BIC values, MCMC paths, signatures, and exposures to a PDF file
        pdf("signeR_plots.pdf", width=11, height=8.5)
        
        # Plot BIC values (may warn/error if nsig was fixed instead of a range, handled gracefully)
        tryCatch({
            BICboxplot(signatures)
        }, error = function(e) {
            message("BICboxplot skipped: ", e\$message)
        })
        
        # Plot MCMC paths
        Paths(signatures\$SignExposures)
        
        # Plot signatures (barplot and heatmap)
        SignPlot(signatures\$SignExposures)
        SignHeat(signatures\$SignExposures)
        
        # Plot exposures (boxplot, barplots, and heatmap)
        ExposureBoxplot(signatures\$SignExposures)
        ExposureBarplot(signatures\$SignExposures)
        ExposureBarplot(signatures\$SignExposures, relative=TRUE)
        ExposureHeat(signatures\$SignExposures)
        
        dev.off()

    writeLines(c(
        '"BIOC_SIGNER_DE_NOVO_SIGNATURE_DISCOVERY":',
        paste0('    signeR: ', as.character(packageVersion('signeR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_de_novo_signature_discovery.csv versions.yml
    """
}

workflow BIOC_SIGNER_DE_NOVO_SIGNATURE_DISCOVERY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ file.vcf, target.bed ] ]

    main:
    BIOC_SIGNER_DE_NOVO_SIGNATURE_DISCOVERY(ch_input)

    emit:
    tables   = BIOC_SIGNER_DE_NOVO_SIGNATURE_DISCOVERY.out.tables
    plots    = BIOC_SIGNER_DE_NOVO_SIGNATURE_DISCOVERY.out.plots
    objects  = BIOC_SIGNER_DE_NOVO_SIGNATURE_DISCOVERY.out.objects
    versions = BIOC_SIGNER_DE_NOVO_SIGNATURE_DISCOVERY.out.versions
}
