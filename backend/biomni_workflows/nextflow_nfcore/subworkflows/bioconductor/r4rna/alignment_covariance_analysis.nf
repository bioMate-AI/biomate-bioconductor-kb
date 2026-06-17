#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: R4RNA — alignment_covariance_analysis
// Visualize RNA secondary structures on top of multiple sequence alignments, highlighting covariation, conservation, and canonical base-pairing.
// Input: fasta.txt, vienna.txt
// Container: quay.io/biocontainers/bioconductor-r4rna:1.38.0--r45hdfd78af_0
// R packages: Biostrings, R4RNA
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, R4RNA
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read the known structure and expand
//  * 2. [Visualization & Output] Read the multiple sequence alignment
//  * 3. [Visualization & Output] Plot covariance in alignment
//  * 4. [Visualization & Output] Color and plot by covariation
//  * 5. [Visualization & Output] Color and plot by conservation
//  * 6. [Visualization & Output] Color and plot by canonical
//  * 7. [Visualization & Output] Color and plot pseudoknots/unknotted groups

nextflow.enable.dsl = 2

process BIOC_R4RNA_ALIGNMENT_COVARIANCE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    
    library(R4RNA)
    library(Biostrings)
    
    # --- Read the known structure and expand ---
    known_file <- "vienna.txt"
    known <- readVienna(known_file)
    known <- expandHelix(known)
    saveRDS(known, "known_structure.rds")
    
    # --- Read the multiple sequence alignment ---
    fasta_file <- "fasta.txt"
    fasta <- as.character(readBStringSet(fasta_file))
    
    # Open PDF device to save plots
    pdf("alignment_covariance_plots.pdf", width = 11, height = 8.5)
    
    # --- Plot covariance in alignment ---
    message("Plot covariance in alignment")
    plotCovariance(fasta, known, cex = 0.5)
    
    # --- Color and plot by covariation ---
    col <- colourByCovariation(known, fasta, get = TRUE)
    saveRDS(col, "col_covariation.rds")
    plotCovariance(fasta, col, grid = TRUE, legend = FALSE)
    legend("topright", legend = attr(col, "legend"), fill = attr(col, "fill"),
        inset = 0.1, bty = "n", border = NA, cex = 0.37, title = "Covariation")
    
    # --- Color and plot by conservation ---
    custom_colours <- c("green", "blue", "cyan", "red", "black", "grey")
    plotCovariance(fasta, col <- colourByConservation(known, fasta, get = TRUE),
        palette = custom_colours, cex = 0.5)
    saveRDS(col, "col_conservation.rds")
    legend("topright", legend = attr(col, "legend"), fill = attr(col, "fill"),
        inset = 0.15, bty = "n", border = NA, cex = 0.75, title = "Conservation")
    
    # --- Color and plot by canonical ---
    col <- colourByCanonical(known, fasta, custom_colours, get = TRUE)
    saveRDS(col, "col_canonical.rds")
    plotCovariance(fasta, col, base.colour = TRUE, cex = 0.5)
    legend("topright", legend = attr(col, "legend"), fill = attr(col, "fill"),
        inset = 0.15, bty = "n", border = NA, cex = 0.75, title = "% Canonical")
    
    # --- Color and plot pseudoknots/unknotted groups ---
    tryCatch({
        col <- colourByUnknottedGroups(known, c("red", "blue"), get = TRUE)
        saveRDS(col, "col_unknotted.rds")
        plotCovariance(fasta, col, base.colour = TRUE, legend = FALSE, species = 23, grid = TRUE, text = TRUE, text.cex = 0.2, cex = 0.5)
    }, error = function(e) {
        message("Species 23 not available or error occurred, attempting with species = 1")
        col <- colourByUnknottedGroups(known, c("red", "blue"), get = TRUE)
        saveRDS(col, "col_unknotted.rds")
        plotCovariance(fasta, col, base.colour = TRUE, legend = FALSE, species = 1, grid = TRUE, text = TRUE, text.cex = 0.2, cex = 0.5)
    })
    
    dev.off()

    writeLines(c(
        '"BIOC_R4RNA_ALIGNMENT_COVARIANCE_ANALYSIS":',
        paste0('    R4RNA: ', as.character(packageVersion('R4RNA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_alignment_covariance_analysis.csv versions.yml
    """
}

workflow BIOC_R4RNA_ALIGNMENT_COVARIANCE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fasta.txt, vienna.txt ] ]

    main:
    BIOC_R4RNA_ALIGNMENT_COVARIANCE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_R4RNA_ALIGNMENT_COVARIANCE_ANALYSIS.out.tables
    plots    = BIOC_R4RNA_ALIGNMENT_COVARIANCE_ANALYSIS.out.plots
    objects  = BIOC_R4RNA_ALIGNMENT_COVARIANCE_ANALYSIS.out.objects
    versions = BIOC_R4RNA_ALIGNMENT_COVARIANCE_ANALYSIS.out.versions
}
