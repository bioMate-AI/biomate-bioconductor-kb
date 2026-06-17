#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: AlphaMissenseR — genomic_track_plot
// Create interactive, multi-scale genomic track plots of AlphaMissense pathogenicity scores using Gosling.
// Input: uniprot_id
// Container: quay.io/biocontainers/bioconductor-alphamissenser:1.6.1--r45hdfd78af_0
// R packages: AlphaMissenseR, dplyr
// Bioconductor: 3.20 | R: 4.4
// Requires: AlphaMissenseR, dplyr
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter AlphaMissense data for the target protein
//  * 2. [Core Analysis] Coerce the filtered data to a GPos object using to_GPos()
//  * 3. [Visualization & Output] Plot the genomic track using gosling_plot()

nextflow.enable.dsl = 2

process BIOC_ALPHAMISSENSER_GENOMIC_TRACK_PLOT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("AlphaMissenseR", "dplyr")
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
    library(AlphaMissenseR)
    library(dplyr)
    
    # Read user input from the working directory
    if (!file.exists("uniprot_id")) {
      stop("Error: 'uniprot_id' file not found in the working directory.")
    }
    
    uniprot_id_val <- trimws(readLines("uniprot_id", n = 1, warn = FALSE))
    if (length(uniprot_id_val) == 0 || uniprot_id_val == "") {
      stop("Error: 'uniprot_id' file is empty.")
    }
    
    # 1. Filter AlphaMissense data for the target protein
    # 2. Coerce the filtered data to a GPos object using to_GPos()
    gpos <- am_data("hg38") |> filter(uniprot_id == uniprot_id_val) |> to_GPos()
    
    # Save the GPos object and its tabular representation
    saveRDS(gpos, file = "gpos_output.rds")
    gpos_df <- as.data.frame(gpos)
    write.csv(gpos_df, file = "gpos_locations.csv", row.names = FALSE)
    
    # 3. Plot the genomic tracks using gosling_plot()
    title_text <- paste(uniprot_id_val, "track")
    
    # Bar plot track
    plot_bar <- gosling_plot(gpos, plot_type = "bar", title = title_text, subtitle = "bar plot example")
    saveRDS(plot_bar, file = "gosling_bar_plot.rds")
    
    # Lollipop plot track
    plot_lollipop <- gosling_plot(gpos, plot_type = "lollipop", title = title_text, subtitle = "lollipop plot example")
    saveRDS(plot_lollipop, file = "gosling_lollipop_plot.rds")
    
    # Clean up database connections
    db_disconnect_all()

    writeLines(c(
        '"BIOC_ALPHAMISSENSER_GENOMIC_TRACK_PLOT":',
        paste0('    AlphaMissenseR: ', as.character(packageVersion('AlphaMissenseR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomic_track_plot.csv versions.yml
    """
}

workflow BIOC_ALPHAMISSENSER_GENOMIC_TRACK_PLOT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ uniprot_id ] ]

    main:
    BIOC_ALPHAMISSENSER_GENOMIC_TRACK_PLOT(ch_input)

    emit:
    tables   = BIOC_ALPHAMISSENSER_GENOMIC_TRACK_PLOT.out.tables
    plots    = BIOC_ALPHAMISSENSER_GENOMIC_TRACK_PLOT.out.plots
    objects  = BIOC_ALPHAMISSENSER_GENOMIC_TRACK_PLOT.out.objects
    versions = BIOC_ALPHAMISSENSER_GENOMIC_TRACK_PLOT.out.versions
}
