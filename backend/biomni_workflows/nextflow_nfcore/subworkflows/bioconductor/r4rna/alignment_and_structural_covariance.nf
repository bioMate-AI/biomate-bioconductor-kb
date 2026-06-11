#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: r4rna — alignment_and_structural_covariance
// Visualize RNA secondary structure on top of a multiple sequence alignment, annotating alignment and arcs by covariation, conservation, canonical base-pairing, o
// Input: alignment.fasta, known_structure.dbn
// Container: quay.io/biocontainers/bioconductor-r4rna:1.38.0--r45hdfd78af_0
// R packages: Biostrings, R4RNA
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_R4RNA_ALIGNMENT_AND_STRUCTURAL_COVARIANCE {
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
    
    library(R4RNA)
    library(Biostrings)
    
    # Read inputs from the working directory
    fasta <- as.character(readBStringSet("alignment.fasta"))
    known <- readVienna("known_structure.dbn")
    
    # Expand helices to basepairs of length 1
    known <- expandHelix(known)
    transat <- known # Reusing known structure as transat for demonstration of predicted structure plotting
    
    # Open PDF device to save the plots
    pdf("alignment_structural_covariance_plots.pdf", width = 11, height = 8.5)
    
    # Plot covariance in alignment
    plotCovariance(fasta, known, cex = 0.5)
    
    # Plot covariance with predicted structure, handling conflicting basepairs
    plotCovariance(fasta, transat, cex = 0.5, conflict.col = "grey")
    
    # Color and plot by covariation
    col <- colourByCovariation(known, fasta, get = TRUE)
    plotCovariance(fasta, col, grid = TRUE, legend = FALSE)
    legend("topright", legend = attr(col, "legend"), fill = attr(col, "fill"),
        inset = 0.1, bty = "n", border = NA, cex = 0.37, title = "Covariation")
    saveRDS(col, "col_covariation.rds")
    
    # Color and plot by conservation
    custom_colours <- c("green", "blue", "cyan", "red", "black", "grey")
    plotCovariance(fasta, col <- colourByConservation(known, fasta, get = TRUE),
        palette = custom_colours, cex = 0.5)
    legend("topright", legend = attr(col, "legend"), fill = attr(col, "fill"),
        inset = 0.15, bty = "n", border = NA, cex = 0.75, title = "Conservation")
    saveRDS(col, "col_conservation.rds")
    
    # Color and plot by percentage canonical basepairs
    col <- colourByCanonical(known, fasta, custom_colours, get = TRUE)
    plotCovariance(fasta, col, base.colour = TRUE, cex = 0.5)
    legend("topright", legend = attr(col, "legend"), fill = attr(col, "fill"),
        inset = 0.15, bty = "n", border = NA, cex = 0.75, title = "% Canonical")
    saveRDS(col, "col_canonical.rds")
    
    # Color and plot pseudoknots
    col <- colourByUnknottedGroups(known, c("red", "blue"), get = TRUE)
    species_val <- min(23, length(fasta))
    plotCovariance(fasta, col, base.colour = TRUE, legend = FALSE, species = species_val, grid = TRUE, text = TRUE, text.cex = 0.2, cex = 0.5)
    saveRDS(col, "col_unknotted.rds")
    
    # Close PDF device
    dev.off()

    writeLines(c(
        '"BIOC_R4RNA_ALIGNMENT_AND_STRUCTURAL_COVARIANCE":',
        paste0('        r4rna: ', as.character(packageVersion("r4rna")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_alignment_and_structural_covariance.csv versions.yml
    """
}

workflow BIOC_R4RNA_ALIGNMENT_AND_STRUCTURAL_COVARIANCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ alignment.fasta, known_structure.dbn ] ]

    main:
    BIOC_R4RNA_ALIGNMENT_AND_STRUCTURAL_COVARIANCE(ch_input)

    emit:
    tables   = BIOC_R4RNA_ALIGNMENT_AND_STRUCTURAL_COVARIANCE.out.tables
    plots    = BIOC_R4RNA_ALIGNMENT_AND_STRUCTURAL_COVARIANCE.out.plots
    objects  = BIOC_R4RNA_ALIGNMENT_AND_STRUCTURAL_COVARIANCE.out.objects
    versions = BIOC_R4RNA_ALIGNMENT_AND_STRUCTURAL_COVARIANCE.out.versions
}
