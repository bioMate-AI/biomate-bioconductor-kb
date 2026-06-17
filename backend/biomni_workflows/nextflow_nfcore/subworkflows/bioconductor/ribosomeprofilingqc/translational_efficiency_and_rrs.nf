#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ribosomeprofilingqc — translational_efficiency_and_rrs
// Calculate and analyze translational efficiency (TE) and ribosome release score (RRS) by combining RPF and RNA-Seq data.
// Input: RPFs, RNAs, gtf
// Container: quay.io/biocontainers/bioconductor-ribosomeprofilingqc:1.22.0--r45hdfd78af_0
// R packages: edgeR, limma, ribosomeProfilingQC, txdbmaker
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RIBOSOMEPROFILINGQC_TRANSLATIONAL_EFFICIENCY_AND_RRS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-ribosomeprofilingqc:1.22.0--r45hdfd78af_0"

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
    .bm_deps <- c("edgeR", "limma", "ribosomeProfilingQC", "txdbmaker")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(ribosomeProfilingQC)
    library(txdbmaker)
    library(limma)
    library(edgeR)
    
    # ==========================================
    # 1. USER INPUTS & VALIDATION
    # ==========================================
    # The pipeline expects RPFs, RNAs, and gtf to be present in the working directory.
    # We dynamically detect them to ensure a complete, runnable pipeline.
    
    rpf_files <- list.files(pattern = "^RPF.*\\\\.bam\$")
    rna_files <- list.files(pattern = "^(RNA|mRNA).*\\\\.bam\$")
    gtf_files <- list.files(pattern = "\\\\.gtf(\\\\.gz)?\$")
    
    if (length(rpf_files) < 2) {
      stop("Error: At least 2 RPF BAM files are required in the working directory to run this pipeline (due to sample=2 plotting constraints).")
    }
    if (length(rna_files) < 2) {
      stop("Error: At least 2 RNA BAM files are required in the working directory to run this pipeline (due to sample=2 plotting constraints).")
    }
    if (length(gtf_files) == 0) {
      stop("Error: No GTF file found in the working directory.")
    }
    
    # Assign inputs
    RPFs <- rpf_files
    RNAs <- rna_files
    gtf <- gtf_files[1]
    
    # Prepare TxDb object from the user-provided GTF file
    message("Preparing TxDb from GTF...")
    txdb <- txdbmaker::makeTxDbFromGFF(gtf)
    
    # Define experimental groups (gp) dynamically based on the number of samples
    n_samples <- length(RPFs)
    if (n_samples %% 2 == 0) {
      gp <- factor(rep(c("KD", "CTL"), each = n_samples / 2))
    } else {
      gp <- factor(c(rep("KD", floor(n_samples / 2)), "CTL"))
    }
    
    # ==========================================
    # 2. TRANSLATIONAL EFFICIENCY & RRS WORKFLOW
    # ==========================================
    
    # --- Count reads for both RPFs and RNA-Seq using countReads ---
    message("Counting reads...")
    cnts <- countReads(RPFs, RNAs, gtf, level="tx")
    saveRDS(cnts, "counts_tx.rds")
    
    # --- Calculate FPKM using getFPKM ---
    message("Calculating FPKM...")
    fpkm <- getFPKM(cnts)
    saveRDS(fpkm, "fpkm.rds")
    
    # --- Calculate standard Translational Efficiency (TE) using ---
    message("Calculating standard Translational Efficiency...")
    TE <- translationalEfficiency(fpkm)
    saveRDS(TE, "TE_standard.rds")
    
    # --- Perform differential TE analysis using limma ---
    message("Performing differential TE analysis...")
    TE.log2 <- log2(TE\$TE + 1)
    design <- model.matrix(~0+gp)
    colnames(design) <- sub("gp", "", colnames(design))
    fit <- lmFit(TE.log2, design)
    fit2 <- eBayes(fit)
    diff_table <- topTable(fit2, number=3)
    write.csv(diff_table, "differential_TE_top3.csv")
    
    # Plot standard TE
    pdf("plot_TE_standard.pdf")
    plotTE(TE, sample=2, xaxis="mRNA", log2=TRUE)
    dev.off()
    
    # --- Calculate maximum N-mer TE (TE90) using coverageDepth and ---
    message("Calculating TE90 (maximum 90-mer TE)...")
    cvgs <- coverageDepth(RPFs, RNAs, txdb)
    saveRDS(cvgs, "coverage_depth_cds.rds")
    
    TE90 <- translationalEfficiency(cvgs, window = 90, normByLibSize=TRUE)
    saveRDS(TE90, "TE90_cds.rds")
    
    pdf("plot_TE90.pdf")
    plotTE(TE90, sample=2, xaxis="mRNA", log2=TRUE)
    dev.off()
    
    message("Calculating TE90 for 3' UTR...")
    cvgs.utr3 <- coverageDepth(RPFs, RNAs, txdb, region="utr3")
    saveRDS(cvgs.utr3, "coverage_depth_utr3.rds")
    
    TE90.utr3 <- translationalEfficiency(cvgs.utr3, window = 90)
    saveRDS(TE90.utr3, "TE90_utr3.rds")
    
    # --- Normalize TE using normBy or normalizeTEbyLoess ---
    message("Normalizing TE using edgeR and Loess methods...")
    cnts_normByEdgeR <- normBy(cnts, method = 'edgeR')
    TE_edgeR <- translationalEfficiency(cnts_normByEdgeR)
    
    pdf("plot_TE_edgeR.pdf")
    plotTE(TE_edgeR)
    dev.off()
    
    TE.log2_norm <- normalizeTEbyLoess(TE)
    
    pdf("plot_TE_loess.pdf")
    plotTE(TE.log2_norm, log2 = FALSE)
    dev.off()
    
    # --- Calculate Ribosome Release Score (RRS) using ---
    message("Calculating Ribosome Release Score (RRS)...")
    RRS <- ribosomeReleaseScore(TE90, TE90.utr3, log2 = TRUE)
    write.csv(RRS, "ribosome_release_score.csv")
    
    # --- Plot metagene coverage using metaPlot ---
    message("Generating metagene coverage plots...")
    cvgs.utr5 <- coverageDepth(RPFs, RNAs, txdb, region="utr5")
    saveRDS(cvgs.utr5, "coverage_depth_utr5.rds")
    
    pdf("plot_metagene_coverage.pdf")
    metaPlot(cvgs.utr5, cvgs, cvgs.utr3, sample=2, xaxis = "mRNA")
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_RIBOSOMEPROFILINGQC_TRANSLATIONAL_EFFICIENCY_AND_RRS":',
        paste0('        ribosomeprofilingqc: ', as.character(packageVersion("ribosomeprofilingqc")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_translational_efficiency_and_rrs.csv versions.yml
    """
}

workflow BIOC_RIBOSOMEPROFILINGQC_TRANSLATIONAL_EFFICIENCY_AND_RRS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ RPFs, RNAs, gtf ] ]

    main:
    BIOC_RIBOSOMEPROFILINGQC_TRANSLATIONAL_EFFICIENCY_AND_RRS(ch_input)

    emit:
    tables   = BIOC_RIBOSOMEPROFILINGQC_TRANSLATIONAL_EFFICIENCY_AND_RRS.out.tables
    plots    = BIOC_RIBOSOMEPROFILINGQC_TRANSLATIONAL_EFFICIENCY_AND_RRS.out.plots
    objects  = BIOC_RIBOSOMEPROFILINGQC_TRANSLATIONAL_EFFICIENCY_AND_RRS.out.objects
    versions = BIOC_RIBOSOMEPROFILINGQC_TRANSLATIONAL_EFFICIENCY_AND_RRS.out.versions
}
