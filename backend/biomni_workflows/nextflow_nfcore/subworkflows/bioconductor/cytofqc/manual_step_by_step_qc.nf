#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cytofQC — manual_step_by_step_qc
// Manually label CyTOF events step-by-step for fine-grained control over each event type (beads, debris, doublets, dead cells).
// Input: raw_cytof.fcs
// Container: quay.io/biocontainers/bioconductor-cytofqc:1.6.0--r44hdfd78af_0
// R packages: CATALYST, RColorBrewer, cytofQC, ggplot2, gridExtra, uwot
// Bioconductor: 3.20 | R: 4.4
// Requires: RColorBrewer, SingleCellExperiment, cytofQC, ggplot2, gridExtra, uwot
// Visualizations: UMAP plot
// QC: doublet detection QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read FCS data and define QC channels using readCytof
//  * 2. [Core Analysis] Identify and label beads using initialBead and svmLabel
//  * 3. [Core Analysis] Identify and label debris using initialDebris and svmLabel
//  * 4. [Core Analysis] Identify and label doublets using initialDoublet and svmLabel
//  * 5. [Core Analysis] Identify and label dead cells using initialDead and svmLabel

nextflow.enable.dsl = 2

process BIOC_CYTOFQC_MANUAL_STEP_BY_STEP_QC {
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
    .bm_deps <- c("CATALYST", "RColorBrewer", "cytofQC", "ggplot2", "gridExtra", "uwot")
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
    library(cytofQC)
    library(CATALYST)
    library(ggplot2)
    library(gridExtra)
    library(uwot)
    library(RColorBrewer)
    
    # Define input file path
    input_file <- "raw_cytof.fcs"
    
    # Check if the input file exists
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    # 1. Read FCS data and define QC channels using readCytof
    message("Reading CyTOF data...")
    x <- readCytof(input_file, 
                   beads = c("Bead"),
                   dna = c("DNA1", "DNA2"),
                   event_length = "Event_length",
                   viability = "Live_Dead",
                   gaussian = c("Center", "Offset", "Width", "Residual"))
    
    # 2. Identify and label beads using initialBead and svmLabel
    message("Identifying and labeling beads...")
    x <- initialBead(x)
    x <- svmLabel(x, type = "bead", n = 500)
    
    # 3. Identify and label debris using initialDebris and svmLabel
    message("Identifying and labeling debris...")
    x <- initialDebris(x)
    x <- svmLabel(x, type = "debris", n = 500)
    
    # 4. Identify and label doublets using initialDoublet and svmLabel
    message("Identifying and labeling doublets...")
    x <- initialDoublet(x)
    x <- svmLabel(x, type = "doublet", n = 500)
    
    # 5. Identify and label dead cells using initialDead and svmLabel
    # Wrapped in tryCatch as viability modeling can fail if there are too few dead events
    message("Identifying and labeling dead cells...")
    x <- initialDead(x)
    x <- tryCatch({
      svmLabel(x, type = "dead", n = 500)
    }, error = function(e) {
      warning("Skipping SVM labeling for dead cells due to insufficient events: ", e\$message)
      x
    })
    
    # --- Save Outputs ---
    
    # 1. Save the final SingleCellExperiment object
    message("Saving labeled SingleCellExperiment object...")
    saveRDS(x, file = "qc_labeled_sce.rds")
    
    # 2. Save summary table of labels
    message("Saving label summary table...")
    label_counts <- as.data.frame(table(label(x)))
    colnames(label_counts) <- c("Label", "Count")
    write.csv(label_counts, "qc_label_summary.csv", row.names = FALSE)
    
    # 3. Save detailed event-level QC scores and probabilities
    message("Saving detailed event QC metrics...")
    df_probs <- as.data.frame(probs(x))
    df_scores <- as.data.frame(scores(x))
    df_out <- data.frame(
      Event_ID = seq_len(ncol(x)),
      Label = label(x),
      df_scores,
      df_probs
    )
    write.csv(df_out, "qc_event_details.csv", row.names = FALSE)
    
    # 4. Generate and save QC score histograms
    message("Generating QC histograms...")
    pdf("qc_histograms.pdf", width = 8, height = 10)
    bead_plot <- cytofHist(scores(x, type = 'bead'), label(x), title = "Bead score")
    debris_plot <- cytofHist(scores(x, type = 'debris'), label(x), title = "Debris score")
    doublet_plot <- cytofHist(scores(x, type = 'doublet'), label(x), title = "Doublet score")
    grid.arrange(bead_plot, debris_plot, doublet_plot, ncol = 1)
    dev.off()
    
    # 5. Generate and save UMAP visualization
    message("Generating UMAP visualization...")
    tech_data <- as.matrix(tech(x))
    # Remove columns with zero variance to avoid scaling issues
    tech_data_filtered <- tech_data[, apply(tech_data, 2, var) > 0, drop = FALSE]
    
    pdf("qc_umap.pdf", width = 8, height = 6)
    lab.umap <- umap(scale(tech_data_filtered), ret_model = TRUE)
    lab.umapD <- data.frame(
      x = lab.umap\$embedding[, 1], 
      y = lab.umap\$embedding[, 2], 
      labs = label(x)
    )
    
    p <- ggplot(lab.umapD, aes(x = x, y = y)) +
      geom_point(aes(color = labs), size = 0.5, alpha = 0.5) +
      scale_color_brewer(name = "QC Label", palette = "Dark2") +
      guides(colour = guide_legend(override.aes = list(size = 2))) +
      labs(x = "UMAP 1", y = "UMAP 2", title = "UMAP of CyTOF QC Labels") +
      theme_bw()
    print(p)
    dev.off()
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_CYTOFQC_MANUAL_STEP_BY_STEP_QC":',
        paste0('    cytofQC: ', as.character(packageVersion('cytofQC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_manual_step_by_step_qc.csv versions.yml
    """
}

workflow BIOC_CYTOFQC_MANUAL_STEP_BY_STEP_QC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_cytof.fcs ] ]

    main:
    BIOC_CYTOFQC_MANUAL_STEP_BY_STEP_QC(ch_input)

    emit:
    tables   = BIOC_CYTOFQC_MANUAL_STEP_BY_STEP_QC.out.tables
    plots    = BIOC_CYTOFQC_MANUAL_STEP_BY_STEP_QC.out.plots
    objects  = BIOC_CYTOFQC_MANUAL_STEP_BY_STEP_QC.out.objects
    versions = BIOC_CYTOFQC_MANUAL_STEP_BY_STEP_QC.out.versions
}
