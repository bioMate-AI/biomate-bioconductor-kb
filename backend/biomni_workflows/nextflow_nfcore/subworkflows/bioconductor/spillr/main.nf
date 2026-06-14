#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: spillR — cytof_spillover_compensation
// Compensate for channel spillover in mass cytometry data using a nonparametric finite mixture model estimated from single-stained beads.
// Input: sce, sce_bead
// Container: quay.io/biocontainers/bioconductor-spillr:1.6.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: cowplot, dplyr, ggplot2, spillR
// Visualizations: diagnostic plot, scatter plot
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare bead and cell data using CATALYST and map markers to barcodes
//  * 2. [Core Analysis] Perform spillover compensation using spillR::compCytof
//  * 3. [Visualization & Output] Generate diagnostic plots using spillR::plotDiagnostics to evaluate the compensation

nextflow.enable.dsl = 2

process BIOC_SPILLR_CYTOF_SPILLOVER_COMPENSATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    .bm_deps <- c("spillR", "CATALYST", "dplyr", "ggplot2", "cowplot", "SummarizedExperiment")
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
        
        
        library(SummarizedExperiment)
        library(spillR)
        library(CATALYST)
        library(dplyr)
        library(ggplot2)
        library(cowplot)
        
        # --------- Load user inputs ---------
        sce <- readRDS("sce.rds")
        sce_bead <- readRDS("sce_bead.rds")
        
        # --------- Process bead data ---------
        bc_key <- rowData(sce_bead)[, c("channel_name", "is_bc")] |>
            as_tibble() |>
            dplyr::filter(is_bc == TRUE) |>
            dplyr::pull(channel_name) |>
            gsub(pattern = "[^0-9]", replacement = "") |>
            as.numeric()
    
        sce_bead <- assignPrelim(sce_bead, bc_key, verbose = FALSE)
        sce_bead <- applyCutoffs(estCutoffs(sce_bead))
        sce_bead <- computeSpillmat(sce_bead)
        
        # --------- Table for mapping markers and barcode ---------
        marker_to_barc <-
            rowData(sce_bead)[, c("channel_name", "is_bc")] |>
            as_tibble() |>
            dplyr::filter(is_bc == TRUE) |>
            mutate(barcode = bc_key) |>
            select(marker = channel_name, barcode)
        
        # Save mapping table
        write.csv(marker_to_barc, "marker_to_barc.csv", row.names = FALSE)
        
        # --------- Compensate function from spillR package ---------
        sce_spillr <-
            spillR::compCytof(sce, sce_bead, marker_to_barc, impute_value = NA, 
                              overwrite = FALSE)
        
        # Save compensated SingleCellExperiment object
        saveRDS(sce_spillr, "sce_spillr.rds")
        
        # --------- 2d histogram from CATALYST package -------
        as <- c("counts", "exprs", "compcounts", "compexprs")
        chs <- marker_to_barc\$marker[1:2]
        ps <- lapply(as, function(a) plotScatter(sce_spillr, chs, assay = a))
        p_scatter <- plot_grid(plotlist = ps, nrow = 2)
        
        # Save scatter plots
        ggsave("compensation_scatter_plots.pdf", plot = p_scatter, width = 10, height = 8)
        
        # --------- Diagnostic plots -------
        ps_diag <- spillR::plotDiagnostics(sce_spillr, chs[2])
        x_lim <- c(0, 7)
        p_diag <- plot_grid(ps_diag[[1]] + xlim(x_lim),
            ps_diag[[2]] + xlim(x_lim),
            ncol = 1, align = "v"
        )
        
        # Save diagnostic plots
        ggsave("diagnostic_plots.pdf", plot = p_diag, width = 8, height = 8)

    writeLines(c(
        '"BIOC_SPILLR_CYTOF_SPILLOVER_COMPENSATION":',
        paste0('    spillR: ', as.character(packageVersion('spillR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cytof_spillover_compensation.csv versions.yml
    """
}

workflow BIOC_SPILLR_CYTOF_SPILLOVER_COMPENSATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce, sce_bead ] ]

    main:
    BIOC_SPILLR_CYTOF_SPILLOVER_COMPENSATION(ch_input)

    emit:
    tables   = BIOC_SPILLR_CYTOF_SPILLOVER_COMPENSATION.out.tables
    plots    = BIOC_SPILLR_CYTOF_SPILLOVER_COMPENSATION.out.plots
    objects  = BIOC_SPILLR_CYTOF_SPILLOVER_COMPENSATION.out.objects
    versions = BIOC_SPILLR_CYTOF_SPILLOVER_COMPENSATION.out.versions
}
