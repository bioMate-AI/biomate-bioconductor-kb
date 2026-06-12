#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: motifstack — single_motif_logo
// Import a single position count/frequency/affinity matrix and plot it as a customized sequence or affinity logo with markers and custom styles.
// Input: motif_matrix.txt
// Container: quay.io/biocontainers/bioconductor-motifstack:1.54.0--r45hdfd78af_0
// R packages: ade4, JASPAR2020, MotifDb, motifStack, RColorBrewer, TFBSTools
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MOTIFSTACK_SINGLE_MOTIF_LOGO {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-motifstack:1.54.0--r45hdfd78af_0"

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
    .bm_deps <- c("ade4", "JASPAR2020", "MotifDb", "motifStack", "RColorBrewer", "TFBSTools")
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
    library(motifStack)
    library(grid)
    
    # --- Import matrix from the user-provided file ---
    # The user input file "motif_matrix.txt" is expected to be in the working directory.
    pcm <- read.table("motif_matrix.txt")
    
    # Robustly handle potential extra metadata columns (similar to the package's bin_SOLEXA.pcm format)
    if (ncol(pcm) > 4 && !all(rownames(pcm) %in% c("A", "C", "G", "T"))) {
      pcm <- pcm[, 3:ncol(pcm)]
    }
    rownames(pcm) <- c("A", "C", "G", "T")
    
    # Save the processed PCM matrix to a CSV file
    write.csv(pcm, "processed_pcm.csv", row.names = TRUE)
    
    # --- Convert/create S4 object ---
    motif <- new("pcm", mat=as.matrix(pcm), name="bin_SOLEXA")
    
    # Open PDF device to save all generated plots
    pdf("motif_logos.pdf", width=8, height=6)
    
    # Plot DNA sequence logo
    plot(motif)
    
    # Plot the logo with same height (probability scale)
    plot(motif, ic.scale=FALSE, ylab="probability")
    
    # Try a different font and a different color group
    motif@color <- colorset(colorScheme='basepairing')
    plot(motif, font="serif")
    
    # --- Define markers ---
    markerRect <- new("marker", type="rect", start=6, stop=7, gp=gpar(lty=2, fill=NA, col="orange"))
    markerLine <- new("marker", type="line", start=2, stop=7, gp=gpar(lwd=2, col="red"))
    markerText <- new("marker", type="text", start=c(1, 5), label=c("*", "core"), gp=gpar(cex=2, col="red"))
    
    # Re-create the motif object with the defined markers
    motif <- new("pcm", mat=as.matrix(pcm), name="bin_SOLEXA", markers=c(markerRect, markerLine, markerText))
    
    # Plot DNA sequence logo with markers
    plot(motif)
    
    # Change the x-axis labels
    plot(motif, xaxis=paste0("pos", seq.int(7)+10))
    
    # --- Plot an RNA sequence logo ---
    rna <- pcm
    rownames(rna)[4] <- "U"
    motif_rna <- new("pcm", mat=as.matrix(rna), name="RNA_motif")
    plot(motif_rna)
    
    # Close the PDF device
    dev.off()
    
    # Save the S4 motif objects as RDS files for downstream analysis
    saveRDS(motif, "dna_motif_with_markers.rds")
    saveRDS(motif_rna, "rna_motif.rds")

    writeLines(c(
        '"BIOC_MOTIFSTACK_SINGLE_MOTIF_LOGO":',
        paste0('        motifstack: ', as.character(packageVersion("motifstack")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_motif_logo.csv versions.yml
    """
}

workflow BIOC_MOTIFSTACK_SINGLE_MOTIF_LOGO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ motif_matrix.txt ] ]

    main:
    BIOC_MOTIFSTACK_SINGLE_MOTIF_LOGO(ch_input)

    emit:
    tables   = BIOC_MOTIFSTACK_SINGLE_MOTIF_LOGO.out.tables
    plots    = BIOC_MOTIFSTACK_SINGLE_MOTIF_LOGO.out.plots
    objects  = BIOC_MOTIFSTACK_SINGLE_MOTIF_LOGO.out.objects
    versions = BIOC_MOTIFSTACK_SINGLE_MOTIF_LOGO.out.versions
}
