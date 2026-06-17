#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chipenrich — narrow_peak_enrichment_chipenrich
// Perform gene set enrichment testing for narrow genomic regions (e.g., transcription factor binding) using a binary peak presence/absence model, optionally corre
// Input: peaks_E2F4, vignette_genesets.txt
// Container: quay.io/biocontainers/bioconductor-chipenrich:2.34.0--r45hdfd78af_0
// R packages: chipenrich
// Bioconductor: 3.20 | R: 4.4
// Requires: chipenrich
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define the path to the gene sets file. 2. Run ChIP-Enrich analysis without mappability correction using chipenrich(). 3. Run ChIP-

nextflow.enable.dsl = 2

process BIOC_CHIPENRICH_NARROW_PEAK_ENRICHMENT_CHIPENRICH {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("chipenrich")
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
    
    # Define input files from the working directory
    peaks_E2F4 <- "peaks_E2F4"
    if (!file.exists(peaks_E2F4)) {
      # Check for common extensions if the exact file name doesn't exist
      for (ext in c(".bed", ".narrowPeak", ".txt", ".tsv")) {
        test_path <- paste0("peaks_E2F4", ext)
        if (file.exists(test_path)) {
          peaks_E2F4 <- test_path
          break
        }
      }
    }
    
    # Verify that the peaks file exists
    if (!file.exists(peaks_E2F4)) {
      stop("Error: peaks_E2F4 file not found in the working directory.")
    }
    
    # Verify that the gene sets file exists
    gs_path <- "vignette_genesets.txt"
    if (!file.exists(gs_path)) {
      stop("Error: vignette_genesets.txt file not found in the working directory.")
    }
    
    # -----------------------------------------------------------------------------
    # Without mappability
    # -----------------------------------------------------------------------------
    results = chipenrich(peaks = peaks_E2F4, genome = 'hg19', genesets = gs_path, locusdef = "nearest_tss", qc_plots = FALSE, out_name = NULL, n_cores = 1)
    results.ce = results\$results
    print("First 5 rows and columns of results without mappability:")
    print(results.ce[1:5,1:5])
    
    # Save results without mappability
    write.csv(results.ce, "chipenrich_results_no_mappa.csv", row.names = FALSE)
    saveRDS(results, "chipenrich_full_output_no_mappa.rds")
    
    # -----------------------------------------------------------------------------
    # With mappability
    # -----------------------------------------------------------------------------
    results = chipenrich(peaks = peaks_E2F4, genome = 'hg19', genesets = gs_path, locusdef = "nearest_tss", mappability=24, qc_plots = FALSE, out_name = NULL, n_cores=1)
    results.cem = results\$results
    print("First 5 rows and columns of results with mappability:")
    print(results.cem[1:5,1:5])
    
    # Save results with mappability
    write.csv(results.cem, "chipenrich_results_with_mappa.csv", row.names = FALSE)
    saveRDS(results, "chipenrich_full_output_with_mappa.rds")

    writeLines(c(
        '"BIOC_CHIPENRICH_NARROW_PEAK_ENRICHMENT_CHIPENRICH":',
        paste0('    chipenrich: ', as.character(packageVersion('chipenrich')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_narrow_peak_enrichment_chipenrich.csv versions.yml
    """
}

workflow BIOC_CHIPENRICH_NARROW_PEAK_ENRICHMENT_CHIPENRICH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peaks_E2F4, vignette_genesets.txt ] ]

    main:
    BIOC_CHIPENRICH_NARROW_PEAK_ENRICHMENT_CHIPENRICH(ch_input)

    emit:
    tables   = BIOC_CHIPENRICH_NARROW_PEAK_ENRICHMENT_CHIPENRICH.out.tables
    plots    = BIOC_CHIPENRICH_NARROW_PEAK_ENRICHMENT_CHIPENRICH.out.plots
    objects  = BIOC_CHIPENRICH_NARROW_PEAK_ENRICHMENT_CHIPENRICH.out.objects
    versions = BIOC_CHIPENRICH_NARROW_PEAK_ENRICHMENT_CHIPENRICH.out.versions
}
