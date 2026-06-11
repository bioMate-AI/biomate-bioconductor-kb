#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Harman — methylation_m_values
// Correct batch effects in DNA methylation data using M-values, reconstruct corrected beta values, and identify/filter out inappropriately corrected clustered pro
// Input: mSetSw, betas_sml
// Container: quay.io/biocontainers/bioconductor-harman:1.38.0--r45ha27e39d_0
// R packages: Biobase, Harman, minfi
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, Harman, minfi
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read User Input Files
//  * 2. [Core Analysis] Shift extreme beta values to avoid infinite M-values
//  * 3. [Core Analysis] Run harman on M-values
//  * 4. [Core Analysis] Reconstruct corrected M-values and convert back to beta
//  * 5. [Core Analysis] Compare pre- and post-correction beta values using
//  * 6. [Core Analysis] Save Outputs

nextflow.enable.dsl = 2

process BIOC_HARMAN_METHYLATION_M_VALUES {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("Biobase", "Harman", "minfi")
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
        library(Harman)
        library(minfi)
        library(Biobase)
        
        # -----------------------------------------------------------------------------
        # --- Read User Input Files ---
        # -----------------------------------------------------------------------------
        mSetSw_path <- if (file.exists("mSetSw")) "mSetSw" else "mSetSw.rds"
        betas_sml_path <- if (file.exists("betas_sml")) "betas_sml" else "betas_sml.rds"
        
        if (!file.exists(mSetSw_path) || !file.exists(betas_sml_path)) {
          stop("Required input files 'mSetSw' and 'betas_sml' (or with .rds extension) not found in the working directory.")
        }
        
        mSetSw <- readRDS(mSetSw_path)
        betas_sml <- readRDS(betas_sml_path)
        
        # Extract beta values from the SWAN object for the shiftBetas step
        betas <- minfi::getBeta(mSetSw)
        
        # -----------------------------------------------------------------------------
        # --- Shift extreme beta values to avoid infinite M-values ---
        # -----------------------------------------------------------------------------
        newBetas <- shiftBetas(betas, shiftBy=1e-4)
        newM <- minfi::logit2(newBetas)
        
        # -----------------------------------------------------------------------------
        # --- Run harman on M-values ---
        # -----------------------------------------------------------------------------
        methHarman <- harman(newM, expt=pData(mSetSw)\$status, batch=pData(mSetSw)\$Slide, limit=0.65)
        
        # Save summary output to a text file
        sink("methHarman_summary.txt")
        summary(methHarman)
        sink()
        
        # Save plot to a PDF file
        pdf("methHarman_plot.pdf", width=7, height=7)
        plot(methHarman, 2, 5)
        dev.off()
        
        # -----------------------------------------------------------------------------
        # --- Reconstruct corrected M-values and convert back to beta ---
        # -----------------------------------------------------------------------------
        ms_hm <- reconstructData(methHarman)
        betas_hm <- minfi::ilogit2(ms_hm)
        
        # -----------------------------------------------------------------------------
        # Stage 4 & 5: Discover clustered methylation and extract cluster membership
        # -----------------------------------------------------------------------------
        # Align betas_hm_sml with betas_sml to ensure matching dimensions and probes
        common_probes <- intersect(rownames(betas_sml), rownames(betas_hm))
        if (length(common_probes) > 0) {
          betas_hm_sml <- betas_hm[common_probes, , drop=FALSE]
          betas_sml <- betas_sml[common_probes, , drop=FALSE]
        } else {
          # Fallback to index-based alignment if no matching rownames exist
          min_rows <- min(nrow(betas_sml), nrow(betas_hm))
          betas_hm_sml <- betas_hm[1:min_rows, , drop=FALSE]
          betas_sml <- betas_sml[1:min_rows, , drop=FALSE]
        }
        
        myK <- discoverClusteredMethylation(betas_sml, min_cluster_size = 3, cores=2, printInfo = TRUE)
        mykClust = kClusterMethylation(betas_sml, row_ks=myK, cores=2)
        
        # -----------------------------------------------------------------------------
        # --- Compare pre- and post-correction beta values using ---
        # -----------------------------------------------------------------------------
        res <- clusterStats(pre_betas=betas_sml, post_betas=betas_hm_sml, kClusters = mykClust)
        
        # -----------------------------------------------------------------------------
        # --- Save Outputs ---
        # -----------------------------------------------------------------------------
        write.csv(res, "cluster_stats.csv", row.names=TRUE)
        saveRDS(res, "cluster_stats.rds")
        saveRDS(betas_hm, "betas_corrected.rds")
        saveRDS(methHarman, "methHarman.rds")
        saveRDS(newBetas, "betas_shifted.rds")

    writeLines(c(
        '"BIOC_HARMAN_METHYLATION_M_VALUES":',
        paste0('    Harman: ', as.character(packageVersion('Harman')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methylation_m_values.csv versions.yml
    """
}

workflow BIOC_HARMAN_METHYLATION_M_VALUES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mSetSw, betas_sml ] ]

    main:
    BIOC_HARMAN_METHYLATION_M_VALUES(ch_input)

    emit:
    tables   = BIOC_HARMAN_METHYLATION_M_VALUES.out.tables
    plots    = BIOC_HARMAN_METHYLATION_M_VALUES.out.plots
    objects  = BIOC_HARMAN_METHYLATION_M_VALUES.out.objects
    versions = BIOC_HARMAN_METHYLATION_M_VALUES.out.versions
}
