#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: r4rna — comparative_structure_visualization
// Compare predicted and known RNA secondary structures using single, double, and overlapping arc diagrams, including filtering and coloring by p-values.
// Input: predicted_structure.txt, known_structure.dbn
// Container: quay.io/biocontainers/bioconductor-r4rna:1.38.0--r45hdfd78af_0
// R packages: Biostrings, R4RNA
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_R4RNA_COMPARATIVE_STRUCTURE_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-r4rna:1.38.0--r45hdfd78af_0"

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
    .bm_deps <- c("Biostrings", "R4RNA")
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
    
    # Load the required library
    library(R4RNA)
    
    # Define input file paths as specified by the user
    predicted_file <- "predicted_structure.txt"
    known_file <- "known_structure.dbn"
    
    # Verify that the input files exist before proceeding
    if (!file.exists(predicted_file)) {
      stop(paste("Required input file missing:", predicted_file))
    }
    if (!file.exists(known_file)) {
      stop(paste("Required input file missing:", known_file))
    }
    
    # --- Read predicted structure (helix format) and known ---
    message("Reading predicted structure in helix format...")
    transat <- readHelix(predicted_file)
    
    message("Reading known structure in dot bracket format...")
    known <- readVienna(known_file)
    
    # --- Expand helices to basepairs of length 1 for maximum ---
    message("Expanding helices to basepairs of length 1...")
    transat <- expandHelix(transat)
    known <- expandHelix(known)
    
    # Save the expanded structures to CSV for downstream analysis
    write.csv(as.data.frame(transat), "predicted_expanded.csv", row.names = FALSE)
    write.csv(as.data.frame(known), "known_expanded.csv", row.names = FALSE)
    
    # Open a PDF device to save all comparative plots
    pdf("comparative_plots.pdf", width = 10, height = 8)
    
    # --- Plot single structure (Known Structure) ---
    message("Plotting single known structure...")
    plotHelix(known, line = TRUE, arrow = TRUE)
    mtext("Known Structure", side = 3, line = -2, adj = 0)
    
    # --- Plot double structure (Unfiltered Predicted vs Known) ---
    message("Plotting double structure (unfiltered)...")
    plotDoubleHelix(transat, known, line = TRUE, arrow = TRUE)
    mtext("TRANSAT\nPredicted\nStructure", side = 3, line = -5, adj = 0)
    mtext("Known Structure", side = 1, line = -2, adj = 0)
    
    # --- Filter predicted structure by value (e.g., p-value <= ---
    message("Filtering out helices above p-value 1e-3...")
    transat <- transat[which(transat\$value <= 1e-3), ]
    
    # --- Color predicted structure by value and plot double helix ---
    message("Assigning colour to basepairs according to p-value...")
    transat\$col <- col <- colourByValue(transat, log = TRUE)
    
    message("Plotting double structure with p-value coloring...")
    plotDoubleHelix(transat, known, line = TRUE, arrow = TRUE)
    legend("topright", legend = attr(col, "legend"), fill = attr(col, "fill"),
        inset = 0.05, bty = "n", border = NA, cex = 0.75, title = "TRANSAT P-values")
    
    # --- Plot overlapping structures ---
    message("Plotting overlapping structures...")
    plotOverlapHelix(transat, known, line = TRUE, arrow = TRUE, scale = FALSE)
    
    # Close the PDF device
    dev.off()
    
    # Save the final filtered and colored predicted structure
    write.csv(as.data.frame(transat), "predicted_filtered_colored.csv", row.names = FALSE)
    saveRDS(transat, "predicted_filtered_colored.rds")
    
    message("Pipeline completed successfully. Outputs saved to 'comparative_plots.pdf', 'predicted_expanded.csv', 'known_expanded.csv', 'predicted_filtered_colored.csv', and 'predicted_filtered_colored.rds'.")

    writeLines(c(
        '"BIOC_R4RNA_COMPARATIVE_STRUCTURE_VISUALIZATION":',
        paste0('        r4rna: ', as.character(packageVersion("r4rna")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_comparative_structure_visualization.csv versions.yml
    """
}

workflow BIOC_R4RNA_COMPARATIVE_STRUCTURE_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ predicted_structure.txt, known_structure.dbn ] ]

    main:
    BIOC_R4RNA_COMPARATIVE_STRUCTURE_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_R4RNA_COMPARATIVE_STRUCTURE_VISUALIZATION.out.tables
    plots    = BIOC_R4RNA_COMPARATIVE_STRUCTURE_VISUALIZATION.out.plots
    objects  = BIOC_R4RNA_COMPARATIVE_STRUCTURE_VISUALIZATION.out.objects
    versions = BIOC_R4RNA_COMPARATIVE_STRUCTURE_VISUALIZATION.out.versions
}
