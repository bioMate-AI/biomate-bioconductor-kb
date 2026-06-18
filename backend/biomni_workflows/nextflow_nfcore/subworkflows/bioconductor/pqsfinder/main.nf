#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pqsfinder — g4_detection_and_export
// Detect potential G-quadruplexes in a DNA sequence, analyze their density, and export the results to GFF3 or FASTA formats.
// Input: sequence.fa
// Container: quay.io/biocontainers/bioconductor-pqsfinder:2.26.0--r45ha27e39d_1
// R packages: Biostrings, biomaRt, ggplot2, Gviz, pqsfinder, rtracklayer
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: density plot

nextflow.enable.dsl = 2

process BIOC_PQSFINDER_G4_DETECTION_AND_EXPORT {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-pqsfinder:2.26.0--r45ha27e39d_1"

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
    .bm_deps <- c("Biostrings", "biomaRt", "ggplot2", "Gviz", "pqsfinder", "rtracklayer")
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
    library(pqsfinder)
    library(Biostrings)
    library(rtracklayer)
    
    # ==========================================
    # --- Load sequence into a DNAString object ---
    # ==========================================
    # Read the user-provided FASTA file from the working directory
    fasta_file <- "sequence.fa"
    if (!file.exists(fasta_file)) {
      stop(paste("Error: Input file", fasta_file, "not found in the working directory."))
    }
    
    dna_set <- readDNAStringSet(fasta_file)
    if (length(dna_set) == 0) {
      stop("Error: The input FASTA file is empty.")
    }
    
    # Extract the first sequence as a DNAString object
    seq <- dna_set[[1]]
    
    # ==========================================
    # --- Run pqsfinder to detect potential G-quadruplexes ---
    # ==========================================
    # Basic quadruplex detection
    pqs <- pqsfinder(seq, min_score = 20)
    print("Basic PQS detection results:")
    print(pqs)
    
    # Extract metadata
    meta <- elementMetadata(pqs)
    print("PQS Metadata:")
    print(meta)
    
    # Save metadata to a CSV file
    write.csv(as.data.frame(meta), "pqs_metadata.csv", row.names = FALSE)
    
    # Detect overlapping PQS
    pqs_overlap <- pqsfinder(seq, overlapping = TRUE, min_score = 30)
    print("Overlapping PQS detection results:")
    print(pqs_overlap)
    
    # ==========================================
    # --- Extract metadata and calculate density ---
    # ==========================================
    # Run pqsfinder with deep = TRUE to enable density calculation
    pqs <- pqsfinder(seq, deep = TRUE, min_score = 20)
    pqs_density <- density(pqs)
    
    # Save density values to a CSV file
    density_df <- data.frame(Position = 1:length(pqs_density), Density = pqs_density)
    write.csv(density_df, "pqs_density.csv", row.names = FALSE)
    
    # Plot and save the density distribution
    pdf("pqs_density_plot.pdf", width = 10, height = 4)
    plot(pqs_density, type = "h", main = "PQS Density along Sequence", 
         xlab = "Position (bp)", ylab = "Density", col = "blue")
    dev.off()
    
    # ==========================================
    # --- Convert results to GRanges and export to GFF3 ---
    # ==========================================
    gr <- as(pqs, "GRanges")
    print("GRanges representation:")
    print(gr)
    
    # Export to GFF3 format
    export(gr, "test.gff", version = "3")
    
    # ==========================================
    # --- Convert results to DNAStringSet and export to FASTA ---
    # ==========================================
    dss <- as(pqs, "DNAStringSet")
    print("DNAStringSet representation:")
    print(dss)
    
    # Export to FASTA format
    writeXStringSet(dss, file = "test.fa", format = "fasta")
    
    print("Pipeline completed successfully. Outputs generated: pqs_metadata.csv, pqs_density.csv, pqs_density_plot.pdf, test.gff, test.fa")

    writeLines(c(
        '"BIOC_PQSFINDER_G4_DETECTION_AND_EXPORT":',
        paste0('        pqsfinder: ', as.character(packageVersion("pqsfinder")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_g4_detection_and_export.csv versions.yml
    """
}

workflow BIOC_PQSFINDER_G4_DETECTION_AND_EXPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sequence.fa ] ]

    main:
    BIOC_PQSFINDER_G4_DETECTION_AND_EXPORT(ch_input)

    emit:
    tables   = BIOC_PQSFINDER_G4_DETECTION_AND_EXPORT.out.tables
    plots    = BIOC_PQSFINDER_G4_DETECTION_AND_EXPORT.out.plots
    objects  = BIOC_PQSFINDER_G4_DETECTION_AND_EXPORT.out.objects
    versions = BIOC_PQSFINDER_G4_DETECTION_AND_EXPORT.out.versions
}
