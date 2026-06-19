#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tidycoverage — aggregated_coverage_multiple_features
// Extract, aggregate, and plot coverage of multiple tracks over multiple sets of genomic features.
// Input: TSSs.bed, conv_transcription_loci.bed, Scc1.bw, RNA.fwd.bw, RNA.rev.bw, PolII.bw, MNase.bw
// Container: quay.io/biocontainers/bioconductor-tidycoverage:1.6.0--r45hdfd78af_0
// R packages: ggplot2, plyranges, purrr, rtracklayer, tidyCoverage
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: coverage plot

nextflow.enable.dsl = 2

process BIOC_TIDYCOVERAGE_AGGREGATED_COVERAGE_MULTIPLE_FEATURES {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-tidycoverage:1.6.0--r45hdfd78af_0"

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
    .bm_deps <- c("ggplot2", "plyranges", "purrr", "rtracklayer", "tidyCoverage")
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
    library(tidyCoverage)
    library(purrr)
    library(plyranges)
    library(rtracklayer)
    library(ggplot2)
    
    # --- Import genomic features and filter by strand ---
    features <- list(
        TSSs = "TSSs.bed",
        `Convergent transcription` = "conv_transcription_loci.bed"
    ) |> map(import) |> map(filter, strand == '+') 
    
    # --- Import genomic tracks as Rle objects ---
    tracks <- list(
        Scc1 = "Scc1.bw", 
        RNA_fwd = "RNA.fwd.bw",
        RNA_rev = "RNA.rev.bw",
        PolII = "PolII.bw", 
        MNase = "MNase.bw"
    ) |> map(import, as = 'Rle')
    
    # --- Create a CoverageExperiment object with scaling and ---
    CE <- CoverageExperiment(tracks, features, width = 5000, scale = TRUE, center = TRUE)
    
    # --- Aggregate the coverage across features using aggregate() ---
    AC <- aggregate(CE)
    
    # --- Coerce the AggregatedCoverage object to a tibble using ---
    ac_tibble <- as_tibble(AC)
    
    # --- Plot the aggregated coverage profiles using ggplot2 and ---
    p <- ac_tibble |> 
        ggplot(aes(col = track, linetype = track %in% c('RNA_fwd', 'RNA_rev'))) + 
        geom_aggrcoverage() + 
        facet_grid(features ~ .) + 
        labs(x = 'Distance from genomic feature', y = 'Mean coverage (± 95% conf. interval)') + 
        theme_bw() + 
        theme(legend.position = 'top')
    
    # Save outputs to the working directory
    saveRDS(CE, "CoverageExperiment.rds")
    saveRDS(AC, "AggregatedCoverage.rds")
    write.csv(ac_tibble, "aggregated_coverage.csv", row.names = FALSE)
    ggsave("aggregated_coverage_plot.pdf", plot = p, width = 10, height = 8)

    writeLines(c(
        '"BIOC_TIDYCOVERAGE_AGGREGATED_COVERAGE_MULTIPLE_FEATURES":',
        paste0('        tidycoverage: ', as.character(packageVersion("tidycoverage")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_aggregated_coverage_multiple_features.csv versions.yml
    """
}

workflow BIOC_TIDYCOVERAGE_AGGREGATED_COVERAGE_MULTIPLE_FEATURES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ TSSs.bed, conv_transcription_loci.bed, Scc1.bw, RNA.fwd.bw, RNA.rev.bw, PolII.bw, MNase.bw ] ]

    main:
    BIOC_TIDYCOVERAGE_AGGREGATED_COVERAGE_MULTIPLE_FEATURES(ch_input)

    emit:
    tables   = BIOC_TIDYCOVERAGE_AGGREGATED_COVERAGE_MULTIPLE_FEATURES.out.tables
    plots    = BIOC_TIDYCOVERAGE_AGGREGATED_COVERAGE_MULTIPLE_FEATURES.out.plots
    objects  = BIOC_TIDYCOVERAGE_AGGREGATED_COVERAGE_MULTIPLE_FEATURES.out.objects
    versions = BIOC_TIDYCOVERAGE_AGGREGATED_COVERAGE_MULTIPLE_FEATURES.out.versions
}
