#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chipenrich — broad_peak_enrichment
// Perform gene set enrichment testing for broad genomic regions (e.g., histone modifications) using Broad-Enrich.
// Input: peaks_H3K4me3_GM12878.bed, vignette_genesets.txt
// Container: quay.io/biocontainers/bioconductor-chipenrich:2.34.0--r45hdfd78af_0
// R packages: chipenrich, egseadata
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHIPENRICH_BROAD_PEAK_ENRICHMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-chipenrich:2.34.0--r45hdfd78af_0"

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
    .bm_deps <- c("chipenrich", "egseadata")
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
    
    # Load required library
    library(chipenrich)
    
    # Define input file paths from the working directory
    peaks_H3K4me3_GM12878 <- "peaks_H3K4me3_GM12878.bed"
    gs_path <- "vignette_genesets.txt"
    
    # Verify input files exist
    if (!file.exists(peaks_H3K4me3_GM12878)) {
      stop(paste("Error: Input file not found:", peaks_H3K4me3_GM12878))
    }
    if (!file.exists(gs_path)) {
      stop(paste("Error: Input file not found:", gs_path))
    }
    
    # Run broadenrich() to perform enrichment testing using cumulative peak coverage
    results = broadenrich(peaks = peaks_H3K4me3_GM12878, genome = 'hg19', genesets = gs_path, locusdef = "nearest_tss", qc_plots = FALSE, out_name = NULL, n_cores=1)
    
    # Extract and inspect the enrichment results
    results.be = results\$results
    print(results.be[1:5,1:5])
    
    # Save meaningful results to disk
    write.csv(results.be, "broadenrich_results.csv", row.names = FALSE)
    if (!is.null(results\$peaks)) {
      write.csv(results\$peaks, "assigned_peaks.csv", row.names = FALSE)
    }
    if (!is.null(results\$peaks_per_gene)) {
      write.csv(results\$peaks_per_gene, "peaks_per_gene.csv", row.names = FALSE)
    }
    saveRDS(results, "broadenrich_results_object.rds")
    
    # Generate a diagnostic plot of gene coverage versus locus length using plot_gene_coverage()
    pdf("gene_coverage_plot.pdf", width = 6, height = 6)
    plot_gene_coverage(peaks = peaks_H3K4me3_GM12878, locusdef = 'nearest_tss',  genome = 'hg19')
    dev.off()

    writeLines(c(
        '"BIOC_CHIPENRICH_BROAD_PEAK_ENRICHMENT":',
        paste0('        chipenrich: ', as.character(packageVersion("chipenrich")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_broad_peak_enrichment.csv versions.yml
    """
}

workflow BIOC_CHIPENRICH_BROAD_PEAK_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peaks_H3K4me3_GM12878.bed, vignette_genesets.txt ] ]

    main:
    BIOC_CHIPENRICH_BROAD_PEAK_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_CHIPENRICH_BROAD_PEAK_ENRICHMENT.out.tables
    plots    = BIOC_CHIPENRICH_BROAD_PEAK_ENRICHMENT.out.plots
    objects  = BIOC_CHIPENRICH_BROAD_PEAK_ENRICHMENT.out.objects
    versions = BIOC_CHIPENRICH_BROAD_PEAK_ENRICHMENT.out.versions
}
