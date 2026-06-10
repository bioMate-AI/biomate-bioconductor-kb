#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tidycoverage — single_locus_coverage
// Extract and plot coverage of multiple tracks over a single genomic locus.
// Input: Scc1.bw, RNA.fwd.bw, RNA.rev.bw, PolII.bw, MNase.bw
// Container: quay.io/biocontainers/bioconductor-tidycoverage:1.6.0--r45hdfd78af_0
// R packages: GenomicRanges, AnnotationHub, ggplot2, plyranges, purrr, rtracklayer, tidyCoverage
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TIDYCOVERAGE_SINGLE_LOCUS_COVERAGE {
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
    .bm_deps <- c("GenomicRanges", "AnnotationHub", "ggplot2", "plyranges", "purrr", "rtracklayer", "tidyCoverage")
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
    library(tidyCoverage)
    library(GenomicRanges)
    library(rtracklayer)
    library(ggplot2)
    
    # 1. Load genomic tracks as a BigWigFileList from the working directory
    tracks <- list(
        Scc1 = "Scc1.bw", 
        RNA_fwd = "RNA.fwd.bw",
        RNA_rev = "RNA.rev.bw",
        PolII = "PolII.bw", 
        MNase = "MNase.bw"
    ) |> BigWigFileList()
    
    # 2. Define the genomic locus of interest as a GRanges object
    locus <- GRanges("II:450001-475000")
    
    # 3. Instantiate a CoverageExperiment object
    CE_chrII <- CoverageExperiment(
        tracks = tracks, 
        features = locus,
        width = width(locus)
    )
    
    # Save the raw CoverageExperiment object
    saveRDS(CE_chrII, file = "CE_chrII.rds")
    
    # 4. Coarsen the coverage resolution using coarsen()
    # 5. Expand the object into a tidy tibble using expand()
    expanded_df <- CE_chrII |> 
        coarsen(window = 10) |> 
        expand()
    
    # Save the expanded tidy tibble to a CSV file
    write.csv(expanded_df, file = "expanded_coverage.csv", row.names = FALSE)
    
    # 6. Plot the coverage tracks using ggplot2 and geom_coverage()
    p <- expanded_df |> 
        ggplot() + 
        geom_coverage(aes(fill = track)) + 
        facet_grid(track~., scales = 'free')
    
    # Save the generated plot to a PDF file
    ggsave("coverage_plot.pdf", plot = p, width = 10, height = 8)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_TIDYCOVERAGE_SINGLE_LOCUS_COVERAGE":
        tidycoverage: \$(Rscript -e 'cat(as.character(packageVersion("tidycoverage")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_locus_coverage.csv versions.yml
    """
}

workflow BIOC_TIDYCOVERAGE_SINGLE_LOCUS_COVERAGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Scc1.bw, RNA.fwd.bw, RNA.rev.bw, PolII.bw, MNase.bw ] ]

    main:
    BIOC_TIDYCOVERAGE_SINGLE_LOCUS_COVERAGE(ch_input)

    emit:
    tables   = BIOC_TIDYCOVERAGE_SINGLE_LOCUS_COVERAGE.out.tables
    plots    = BIOC_TIDYCOVERAGE_SINGLE_LOCUS_COVERAGE.out.plots
    objects  = BIOC_TIDYCOVERAGE_SINGLE_LOCUS_COVERAGE.out.objects
    versions = BIOC_TIDYCOVERAGE_SINGLE_LOCUS_COVERAGE.out.versions
}
