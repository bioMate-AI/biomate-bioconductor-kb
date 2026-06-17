#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: demuxmix — pooling_non_labeled_with_labeled_cells
// Demultiplex a mixture of labeled cells and non-labeled cells (e.g., rare cells) using a single HTO channel.
// Input: csf
// Container: quay.io/biocontainers/bioconductor-demuxmix:1.12.0--r45hdfd78af_0
// R packages: cowplot, demuxmix, ggplot2
// Bioconductor: 3.20 | R: 4.4
// Requires: cowplot, demuxmix, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter out low-quality droplets based on detected gene counts
//  * 2. [Core Analysis] Fit a regression mixture model for the single HTO using demuxmix
//  * 3. [Core Analysis] Classify droplets into labeled (positive) and non-labeled (negative) using dmmClassify
//  * 4. [Visualization & Output] Assess model fit and overlap using summary, dmmOverlap, plotDmmHistogram, and plotDmmScatter

nextflow.enable.dsl = 2

process BIOC_DEMUXMIX_POOLING_NON_LABELED_WITH_LABELED_CELLS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-single_cell:3.20-slim"

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
    .bm_deps <- c("cowplot", "demuxmix", "ggplot2")
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
    library(demuxmix)
    library(ggplot2)
    library(cowplot)
    
    # Read the user input file 'csf' from the working directory
    # Supporting both CSV and RDS formats
    if (file.exists("csf.csv")) {
      csf <- read.csv("csf.csv", row.names = 1, check.names = FALSE)
    } else if (file.exists("csf.rds")) {
      csf <- readRDS("csf.rds")
    } else {
      stop("Error: Input file 'csf.csv' or 'csf.rds' not found in the working directory.")
    }
    
    # 1. Filter out low-quality droplets based on detected gene counts
    csf <- csf[csf\$NumGenes >= 200, ]
    
    # Prepare HTO matrix
    hto <- t(matrix(csf\$HTO, dimnames = list(rownames(csf), "HTO")))
    
    # 2. Fit a regression mixture model for the single HTO using demuxmix
    dmm <- demuxmix(hto, rna = csf\$NumGenes)
    dmm
    
    # 3. Assess model fit and overlap using summary and dmmOverlap
    dmm_summary <- summary(dmm)
    overlap_val <- dmmOverlap(dmm)
    
    # 4. Generate QC plots
    histo <- plotDmmHistogram(dmm)
    scatter <- plotDmmScatter(dmm) + coord_cartesian(xlim = c(2, 4))
    
    # 5. Classify droplets into labeled (positive) and non-labeled (negative) using dmmClassify
    class <- dmmClassify(dmm)
    
    # Write named output files for the meaningful results
    # Save the fitted demuxmix model object
    saveRDS(dmm, "dmm_model.rds")
    
    # Save the summary table
    write.csv(dmm_summary, "dmm_summary.csv", row.names = FALSE)
    
    # Save the overlap value
    overlap_df <- data.frame(HTO = names(overlap_val), Overlap = as.numeric(overlap_val))
    write.csv(overlap_df, "dmm_overlap.csv", row.names = FALSE)
    
    # Save the classification results
    write.csv(class, "dmm_classifications.csv", row.names = TRUE)
    
    # Save the diagnostic plots as a PDF
    pdf("dmm_qc_plots.pdf", width = 8, height = 10)
    grid_plot <- plot_grid(histo, scatter, labels = c("A", "B"), nrow = 2)
    print(grid_plot)
    dev.off()

    writeLines(c(
        '"BIOC_DEMUXMIX_POOLING_NON_LABELED_WITH_LABELED_CELLS":',
        paste0('    demuxmix: ', as.character(packageVersion('demuxmix')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pooling_non_labeled_with_labeled_cells.csv versions.yml
    """
}

workflow BIOC_DEMUXMIX_POOLING_NON_LABELED_WITH_LABELED_CELLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ csf ] ]

    main:
    BIOC_DEMUXMIX_POOLING_NON_LABELED_WITH_LABELED_CELLS(ch_input)

    emit:
    tables   = BIOC_DEMUXMIX_POOLING_NON_LABELED_WITH_LABELED_CELLS.out.tables
    plots    = BIOC_DEMUXMIX_POOLING_NON_LABELED_WITH_LABELED_CELLS.out.plots
    objects  = BIOC_DEMUXMIX_POOLING_NON_LABELED_WITH_LABELED_CELLS.out.objects
    versions = BIOC_DEMUXMIX_POOLING_NON_LABELED_WITH_LABELED_CELLS.out.versions
}
