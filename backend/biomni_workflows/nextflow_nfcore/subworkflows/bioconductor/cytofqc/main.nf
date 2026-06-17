#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cytofqc — all_in_one_qc_labeling
// Automatically label CyTOF events using the all-in-one labelQC function.
// Input: raw_cytof.fcs
// Container: quay.io/biocontainers/bioconductor-cytofqc:1.6.0--r44hdfd78af_0
// R packages: CATALYST, SingleCellExperiment, cytofQC, ggplot2, gridExtra, RColorBrewer, uwot
// Bioconductor: 3.20 | R: 4.4
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CYTOFQC_ALL_IN_ONE_QC_LABELING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-cytofqc:1.6.0--r44hdfd78af_0"

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
    .bm_deps <- c("CATALYST", "SingleCellExperiment", "cytofQC", "ggplot2", "gridExtra", "RColorBrewer", "uwot")
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
    library(cytofQC)
    library(CATALYST)
    library(SingleCellExperiment)
    library(ggplot2)
    library(gridExtra)
    
    # Define input file path (must be in the working directory)
    f <- "raw_cytof.fcs"
    
    if (!file.exists(f)) {
      stop(paste("Required input file '", f, "' not found in the working directory."))
    }
    
    # --- Read FCS data and define QC channels using readCytof ---
    x <- readCytof(f, 
                   beads = c("Bead"),
                   dna = c("DNA1", "DNA2"),
                   event_length = "Event_length",
                   viability = "Live_Dead",
                   gaussian = c("Center", "Offset", "Width", "Residual"))
    
    # --- Run the all-in-one labeling using labelQC ---
    x <- labelQC(x)
    
    # --- Retrieve labels, scores, and probabilities using label, ---
    lbls <- label(x)
    scrs <- scores(x)
    init <- initial(x)
    prbs <- probs(x)
    
    # Print summary tables to console
    print("Label distribution:")
    print(table(lbls))
    
    print("Head of scores:")
    print(head(scrs))
    
    print("Head of initial classifications:")
    print(head(init))
    
    print("Head of probabilities:")
    print(head(prbs))
    
    # Save tabular results to CSV
    results_summary <- data.frame(
      Event_Index = seq_len(ncol(x)),
      Label = lbls
    )
    results_summary <- cbind(results_summary, as.data.frame(scrs), as.data.frame(prbs))
    write.csv(results_summary, "cytof_qc_results.csv", row.names = FALSE)
    
    # Save the SingleCellExperiment object
    saveRDS(x, "cytof_qc_sce.rds")
    
    # --- Visualize the scores using cytofHist ---
    bead <- cytofHist(scores(x, type = 'bead'), label(x), title = "Bead score")
    debris <- cytofHist(scores(x, type = 'debris'), label(x), title = "Debris score")
    doublet <- cytofHist(scores(x, type = 'doublet'), label(x), title = "Doublet score")
    
    # Save the visualization to a PDF file
    pdf("cytof_qc_histograms.pdf", width = 8, height = 11)
    grid.arrange(bead, debris, doublet, ncol = 1)
    dev.off()
    
    # Also generate and save the density-scaled histograms
    bead_dens <- cytofHist(scores(x, type = 'bead'), label(x), type = "density", title = "Bead score (Density)")
    debris_dens <- cytofHist(scores(x, type = 'debris'), label(x), type = "density", title = "Debris score (Density)")
    doublet_dens <- cytofHist(scores(x, type = 'doublet'), label(x), type = "density", title = "Doublet score (Density)")
    
    pdf("cytof_qc_density_histograms.pdf", width = 8, height = 11)
    grid.arrange(bead_dens, debris_dens, doublet_dens, ncol = 1)
    dev.off()
    
    print("Pipeline completed successfully. Outputs saved: 'cytof_qc_results.csv', 'cytof_qc_sce.rds', 'cytof_qc_histograms.pdf', 'cytof_qc_density_histograms.pdf'.")

    writeLines(c(
        '"BIOC_CYTOFQC_ALL_IN_ONE_QC_LABELING":',
        paste0('        cytofqc: ', as.character(packageVersion("cytofqc")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_all_in_one_qc_labeling.csv versions.yml
    """
}

workflow BIOC_CYTOFQC_ALL_IN_ONE_QC_LABELING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_cytof.fcs ] ]

    main:
    BIOC_CYTOFQC_ALL_IN_ONE_QC_LABELING(ch_input)

    emit:
    tables   = BIOC_CYTOFQC_ALL_IN_ONE_QC_LABELING.out.tables
    plots    = BIOC_CYTOFQC_ALL_IN_ONE_QC_LABELING.out.plots
    objects  = BIOC_CYTOFQC_ALL_IN_ONE_QC_LABELING.out.objects
    versions = BIOC_CYTOFQC_ALL_IN_ONE_QC_LABELING.out.versions
}
