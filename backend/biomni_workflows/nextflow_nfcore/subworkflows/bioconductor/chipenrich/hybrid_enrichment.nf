#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chipenrich — hybrid_enrichment
// Perform gene set enrichment testing using a hybrid approach that combines ChIP-Enrich and Poly-Enrich for optimal statistical power.
// Input: peaks_E2F4, vignette_genesets.txt
// Container: quay.io/biocontainers/bioconductor-chipenrich:2.34.0--r45hdfd78af_0
// R packages: chipenrich
// Bioconductor: 3.20 | R: 4.4
// Requires: chipenrich
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define the path to the gene sets file and read peaks
//  * 2. [Input & Preparation] Run Hybrid-Enrich analysis using hybridenrich()
//  * 3. [Input & Preparation] Extract and print the results
//  * 4. [Input & Preparation] Write named output files for the meaningful results

nextflow.enable.dsl = 2

process BIOC_CHIPENRICH_HYBRID_ENRICHMENT {
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
    
    # --- Define the path to the gene sets file and read peaks ---
    gs_path <- "vignette_genesets.txt"
    if (!file.exists(gs_path)) {
      stop("Required input file 'vignette_genesets.txt' not found in the working directory.")
    }
    
    # Resolve peaks_E2F4 input from the working directory
    peaks_E2F4 <- NULL
    if (file.exists("peaks_E2F4") && !dir.exists("peaks_E2F4")) {
      # Attempt to read as data.frame if it has a standard tabular structure
      peaks_E2F4 <- tryCatch({
        df_preview <- read.table("peaks_E2F4", header = FALSE, stringsAsFactors = FALSE, nrows = 10)
        if (ncol(df_preview) >= 3 && is.numeric(df_preview[[2]]) && is.numeric(df_preview[[3]])) {
          full_df <- read.table("peaks_E2F4", header = FALSE, stringsAsFactors = FALSE)
          colnames(full_df)[1:3] <- c("chrom", "start", "end")
          full_df
        } else {
          "peaks_E2F4"
        }
      }, error = function(e) {
        "peaks_E2F4"
      })
    } else if (file.exists("peaks_E2F4.bed")) {
      peaks_E2F4 <- "peaks_E2F4.bed"
    } else if (file.exists("peaks_E2F4.narrowPeak")) {
      peaks_E2F4 <- "peaks_E2F4.narrowPeak"
    } else if (file.exists("peaks_E2F4.txt")) {
      peaks_E2F4 <- read.table("peaks_E2F4.txt", header = TRUE, stringsAsFactors = FALSE)
    } else {
      stop("Required input 'peaks_E2F4' (file or data.frame) not found in the working directory.")
    }
    
    # --- Run Hybrid-Enrich analysis using hybridenrich() ---
    results = hybridenrich(peaks = peaks_E2F4, genome = 'hg19', genesets = gs_path, locusdef = "nearest_tss", qc_plots = F, out_name = NULL, n_cores = 1)
    
    # --- Extract and print the results ---
    results.hybrid = results\$results
    print(results.hybrid[1:5,1:5])
    
    # --- Write named output files for the meaningful results ---
    write.csv(results.hybrid, file = "hybrid_enrichment_results.csv", row.names = FALSE)
    saveRDS(results, file = "hybrid_enrichment_results.rds")

    writeLines(c(
        '"BIOC_CHIPENRICH_HYBRID_ENRICHMENT":',
        paste0('    chipenrich: ', as.character(packageVersion('chipenrich')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hybrid_enrichment.csv versions.yml
    """
}

workflow BIOC_CHIPENRICH_HYBRID_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peaks_E2F4, vignette_genesets.txt ] ]

    main:
    BIOC_CHIPENRICH_HYBRID_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_CHIPENRICH_HYBRID_ENRICHMENT.out.tables
    plots    = BIOC_CHIPENRICH_HYBRID_ENRICHMENT.out.plots
    objects  = BIOC_CHIPENRICH_HYBRID_ENRICHMENT.out.objects
    versions = BIOC_CHIPENRICH_HYBRID_ENRICHMENT.out.versions
}
