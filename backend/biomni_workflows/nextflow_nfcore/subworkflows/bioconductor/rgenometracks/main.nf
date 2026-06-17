#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rgenometracks — visualize_genomic_tracks
// Combine and plot multiple genomic data tracks (such as TADs, arcs, and BigWig) for a specific genomic region.
// Input: tad_classification.bed, links2.links, bigwig2_X_2.5e6_3.5e6.bw, h5_dir
// Container: quay.io/biocontainers/bioconductor-rgenometracks:1.16.0--r45hdfd78af_0
// R packages: rGenomeTracks
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RGENOMETRACKS_VISUALIZE_GENOMIC_TRACKS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-rgenometracks:1.16.0--r45hdfd78af_0"

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
    .bm_deps <- c("rGenomeTracks")
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
    
    # Load the rGenomeTracks library
    library(rGenomeTracks)
    
    # --- Install pyGenomeTracks dependency ---
    tryCatch({
      install_pyGenomeTracks()
    }, error = function(e) {
      message("Note: pyGenomeTracks installation step encountered an issue or is already satisfied: ", e\$message)
    })
    
    # Define input file paths from the working directory
    tads_dir <- "tad_classification.bed"
    arcs_dir <- "links2.links"
    bw_dir <- "bigwig2_X_2.5e6_3.5e6.bw"
    h5_dir <- "h5_dir"
    
    # --- Create individual track objects ---
    # Create HiC track from HiC matrix
    h5 <- track_hic_matrix(
      file = h5_dir, depth = 250000, min_value = 5, max_value = 200,
      transform = "log1p", show_masked_bins = FALSE
    )
    
    # Create TADS track
    tads <- track_domains(
      file = tads_dir, border_color = "black",
      color = "none", height = 5,
      line_width = 5,
      show_data_range = FALSE,
      overlay_previous = "share-y"
    )
    
    # Create arcs track
    arcs <- track_links(
      file = arcs_dir, links_type = "triangles",
      line_style = "dashed",
      overlay_previous = "share-y",
      color = "darkred",
      line_width = 3,
      show_data_range = FALSE
    )
    
    # Create bigwig track
    bw <- track_bigwig(
      file = bw_dir, color = "red",
      max_value = 50,
      min_value = 0,
      height = 4,
      overlay_previous = "no",
      show_data_range = FALSE
    )
    
    # --- Combine track objects using the + operator ---
    tracks <- tads + arcs + bw
    
    # Save the combined track objects as RDS files
    saveRDS(tracks, "tracks_tads_arcs_bw.rds")
    saveRDS(h5 + tads + bw, "tracks_h5_tads_bw.rds")
    
    # --- Plot the combined tracks for a specific genomic region ---
    pdf("genomic_tracks_output.pdf", width = 10, height = 12)
    
    layout(matrix(c(1,1,2,3,4,4), nrow = 3, ncol = 2, byrow = TRUE))
    plot_gtracks(tracks, chr = "X", start = 25 * 10^5, end = 31 * 10^5)
    
    # Reset layout for the second plot to avoid layout carryover issues
    par(mfrow = c(1, 1))
    
    # Plot HiC, TADS and bigwig tracks
    plot_gtracks(h5 + tads + bw, chr = "X", start = 25 * 10^5, end = 31 * 10^5)
    
    dev.off()

    writeLines(c(
        '"BIOC_RGENOMETRACKS_VISUALIZE_GENOMIC_TRACKS":',
        paste0('        rgenometracks: ', as.character(packageVersion("rgenometracks")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_visualize_genomic_tracks.csv versions.yml
    """
}

workflow BIOC_RGENOMETRACKS_VISUALIZE_GENOMIC_TRACKS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tad_classification.bed, links2.links, bigwig2_X_2.5e6_3.5e6.bw, h5_dir ] ]

    main:
    BIOC_RGENOMETRACKS_VISUALIZE_GENOMIC_TRACKS(ch_input)

    emit:
    tables   = BIOC_RGENOMETRACKS_VISUALIZE_GENOMIC_TRACKS.out.tables
    plots    = BIOC_RGENOMETRACKS_VISUALIZE_GENOMIC_TRACKS.out.plots
    objects  = BIOC_RGENOMETRACKS_VISUALIZE_GENOMIC_TRACKS.out.objects
    versions = BIOC_RGENOMETRACKS_VISUALIZE_GENOMIC_TRACKS.out.versions
}
