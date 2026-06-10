#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SNPRelate — relatedness_and_ibd_analysis
// Estimate identity-by-descent (IBD) coefficients and infer relationships using Method of Moments (MoM), Maximum Likelihood Estimation (MLE), or KING robust metho
// Input: genofile, YRI.id, snpset.id, snp.id, family.id
// Container: quay.io/biocontainers/bioconductor-snprelate:1.44.0--r45ha27e39d_0
// R packages: SNPRelate, gdsfmt
// Bioconductor: 3.20 | R: 4.4
// Requires: SNPRelate, gdsfmt
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Estimate IBD using PLINK Method of Moments with snpgdsIBDMoM
//  * 2. [Core Analysis] Estimate IBD using Maximum Likelihood Estimation with snpgdsIBDMLE
//  * 3. [Core Analysis] Infer relationships in the presence of population stratification using the KING method with snpgdsIBDKING
//  * 4. [Core Analysis] Extract pairwise IBD coefficients using snpgdsIBDSelection

nextflow.enable.dsl = 2

process BIOC_SNPRELATE_RELATEDNESS_AND_IBD_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("SNPRelate", "gdsfmt")
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
    library(gdsfmt)
    library(SNPRelate)
    
    # ==========================================
    # 1. READ USER INPUTS FROM WORKING DIRECTORY
    # ==========================================
    
    # Read the GDS file handle or path
    if (file.exists("genofile.gds")) {
      genofile <- snpgdsOpen("genofile.gds")
    } else if (file.exists("genofile.rds")) {
      g_input <- readRDS("genofile.rds")
      if (is.character(g_input)) {
        genofile <- snpgdsOpen(g_input)
      } else {
        genofile <- g_input
      }
    } else {
      stop("Error: 'genofile.gds' or 'genofile.rds' not found in the working directory.")
    }
    
    # Read the other required vector inputs
    if (file.exists("YRI.id.rds")) {
      YRI.id <- readRDS("YRI.id.rds")
    } else {
      stop("Error: 'YRI.id.rds' not found in the working directory.")
    }
    
    if (file.exists("snpset.id.rds")) {
      snpset.id <- readRDS("snpset.id.rds")
    } else {
      stop("Error: 'snpset.id.rds' not found in the working directory.")
    }
    
    if (file.exists("snp.id.rds")) {
      snp.id <- readRDS("snp.id.rds")
    } else {
      stop("Error: 'snp.id.rds' not found in the working directory.")
    }
    
    if (file.exists("family.id.rds")) {
      family.id <- readRDS("family.id.rds")
    } else {
      stop("Error: 'family.id.rds' not found in the working directory.")
    }
    
    
    # ==========================================
    # 2. EXECUTING THE WORKFLOW STAGES
    # ==========================================
    
    # --- Stage 1: Estimate IBD using PLINK Method of Moments (MoM) ---
    ibd <- snpgdsIBDMoM(genofile, sample.id=YRI.id, snp.id=snpset.id, maf=0.05, missing.rate=0.05, num.thread=2)
    ibd.coeff <- snpgdsIBDSelection(ibd)
    
    # Save MoM Outputs
    write.csv(ibd.coeff, "ibd_mom_coefficients.csv", row.names=FALSE)
    saveRDS(ibd, "ibd_mom_raw.rds")
    saveRDS(ibd.coeff, "ibd_mom_coefficients.rds")
    
    # Plot MoM Results
    pdf("ibd_mom_plot.pdf", width=6, height=6)
    plot(ibd.coeff\$k0, ibd.coeff\$k1, xlim=c(0,1), ylim=c(0,1),
         xlab="k0", ylab="k1", main="YRI samples (MoM)")
    lines(c(0,1), c(1,0), col="red", lty=2)
    dev.off()
    
    
    # --- Stage 2: Estimate IBD using Maximum Likelihood Estimation (MLE) ---
    ibd <- snpgdsIBDMLE(genofile, sample.id=YRI.id, snp.id=snp.id, maf=0.05, missing.rate=0.05, num.thread=2)
    ibd.coeff <- snpgdsIBDSelection(ibd)
    
    # Save MLE Outputs
    write.csv(ibd.coeff, "ibd_mle_coefficients.csv", row.names=FALSE)
    saveRDS(ibd, "ibd_mle_raw.rds")
    saveRDS(ibd.coeff, "ibd_mle_coefficients.rds")
    
    # Plot MLE Results
    pdf("ibd_mle_plot.pdf", width=6, height=6)
    plot(ibd.coeff\$k0, ibd.coeff\$k1, xlim=c(0,1), ylim=c(0,1),
         xlab="k0", ylab="k1", main="YRI samples (MLE)")
    lines(c(0,1), c(1,0), col="red", lty=2)
    dev.off()
    
    
    # --- Stage 3 & 4: Infer relationships using the KING robust method ---
    ibd.robust <- snpgdsIBDKING(genofile, sample.id=YRI.id, family.id=family.id, num.thread=2)
    dat <- snpgdsIBDSelection(ibd.robust)
    
    # Save KING Outputs
    write.csv(dat, "ibd_king_coefficients.csv", row.names=FALSE)
    saveRDS(ibd.robust, "ibd_king_raw.rds")
    saveRDS(dat, "ibd_king_coefficients.rds")
    
    # Plot KING Results
    pdf("ibd_king_plot.pdf", width=6, height=6)
    plot(dat\$IBS0, dat\$kinship, xlab="Proportion of Zero IBS",
         ylab="Estimated Kinship Coefficient (KING-robust)",
         main="YRI samples (KING-robust)")
    dev.off()
    
    
    # ==========================================
    # 3. CLEANUP AND CLOSE GDS FILE
    # ==========================================
    snpgdsClose(genofile)

    writeLines(c(
        '"BIOC_SNPRELATE_RELATEDNESS_AND_IBD_ANALYSIS":',
        paste0('    SNPRelate: ', as.character(packageVersion('SNPRelate')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_relatedness_and_ibd_analysis.csv versions.yml
    """
}

workflow BIOC_SNPRELATE_RELATEDNESS_AND_IBD_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genofile, YRI.id, snpset.id, snp.id, family.id ] ]

    main:
    BIOC_SNPRELATE_RELATEDNESS_AND_IBD_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SNPRELATE_RELATEDNESS_AND_IBD_ANALYSIS.out.tables
    plots    = BIOC_SNPRELATE_RELATEDNESS_AND_IBD_ANALYSIS.out.plots
    objects  = BIOC_SNPRELATE_RELATEDNESS_AND_IBD_ANALYSIS.out.objects
    versions = BIOC_SNPRELATE_RELATEDNESS_AND_IBD_ANALYSIS.out.versions
}
