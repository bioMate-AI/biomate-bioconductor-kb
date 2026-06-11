#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chipenrich — narrow_peak_enrichment_polyenrich
// Perform gene set enrichment testing for narrow genomic regions using a count-based model, suitable for high peak counts or enhancer-target gene definitions.
// Input: peaks_E2F4, vignette_genesets.txt
// Container: quay.io/biocontainers/bioconductor-chipenrich:2.34.0--r45hdfd78af_0
// R packages: chipenrich
// Bioconductor: 3.20 | R: 4.4
// Requires: chipenrich
// Visualizations: enrichment plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read User Inputs from Working Directory
//  * 2. [Input & Preparation] Run Poly-Enrich (Standard Count-Based Method)
//  * 3. [Input & Preparation] Run Poly-Enrich (Weighted Method & Enhancer Locus)
//  * 4. [Input & Preparation] Generate and Save QC Plots

nextflow.enable.dsl = 2

process BIOC_CHIPENRICH_NARROW_PEAK_ENRICHMENT_POLYENRICH {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    library(chipenrich)
    
    # ---------------------------------------------------------
    # --- Read User Inputs from Working Directory ---
    # ---------------------------------------------------------
    
    # Locate the peaks_E2F4 file (can be a path to .bed, .narrowPeak, or a text file)
    peaks_input = "peaks_E2F4"
    if (!file.exists(peaks_input)) {
      possible_extensions = c(".bed", ".narrowPeak", ".txt")
      found = FALSE
      for (ext in possible_extensions) {
        test_path = paste0("peaks_E2F4", ext)
        if (file.exists(test_path)) {
          peaks_input = test_path
          found = TRUE
          break
        }
      }
      if (!found) {
        stop("Error: Input file 'peaks_E2F4' (or with .bed/.narrowPeak/.txt extension) not found in the working directory.")
      }
    }
    
    # Assign to the variable name used in the documented code
    peaks_E2F4 = peaks_input
    
    # Define the path to the custom gene sets file
    gs_path = "vignette_genesets.txt"
    if (!file.exists(gs_path)) {
      stop("Error: Input file 'vignette_genesets.txt' not found in the working directory.")
    }
    
    # ---------------------------------------------------------
    # --- Run Poly-Enrich (Standard Count-Based Method) ---
    # ---------------------------------------------------------
    message("Running Poly-Enrich with standard count-based method...")
    
    results_std = polyenrich(
      peaks = peaks_E2F4, 
      genome = 'hg19', 
      genesets = gs_path, 
      method = 'polyenrich', 
      locusdef = "nearest_tss", 
      qc_plots = FALSE, 
      out_name = NULL, 
      n_cores = 1
    )
    results.pe = results_std\$results
    print(results.pe[1:5,1:5])
    
    # Save standard results
    write.csv(results.pe, file = "polyenrich_standard_results.csv", row.names = FALSE)
    saveRDS(results_std, file = "polyenrich_standard_full.rds")
    
    # ---------------------------------------------------------
    # --- Run Poly-Enrich (Weighted Method & Enhancer Locus) ---
    # ---------------------------------------------------------
    message("Running Poly-Enrich with weighted method and enhancer locus definition...")
    
    results_wt = polyenrich(
      peaks = peaks_E2F4, 
      genome = 'hg19', 
      genesets = gs_path, 
      method = "polyenrich_weighted", 
      locusdef = "enhancer_plus5kb", 
      qc_plots = FALSE, 
      out_name = NULL, 
      n_cores = 1
    )
    results.pe = results_wt\$results
    print(results.pe[1:5,1:5])
    
    # Save weighted results
    write.csv(results.pe, file = "polyenrich_weighted_results.csv", row.names = FALSE)
    saveRDS(results_wt, file = "polyenrich_weighted_full.rds")
    
    # ---------------------------------------------------------
    # --- Generate and Save QC Plots ---
    # ---------------------------------------------------------
    tryCatch({
      message("Generating QC plots...")
      pdf("polyenrich_qc_plots.pdf", width = 8, height = 6)
      
      # Peak distance to TSS distribution
      plot_dist_to_tss(peaks = peaks_E2F4, genome = 'hg19')
      
      # Number of peaks versus locus length spline
      plot_polyenrich_spline(peaks = peaks_E2F4, locusdef = 'nearest_tss', genome = 'hg19')
      
      dev.off()
      message("QC plots saved to 'polyenrich_qc_plots.pdf'")
    }, error = function(e) {
      warning("Could not generate QC plots: ", e\$message)
    })
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_CHIPENRICH_NARROW_PEAK_ENRICHMENT_POLYENRICH":',
        paste0('    chipenrich: ', as.character(packageVersion('chipenrich')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_narrow_peak_enrichment_polyenrich.csv versions.yml
    """
}

workflow BIOC_CHIPENRICH_NARROW_PEAK_ENRICHMENT_POLYENRICH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peaks_E2F4, vignette_genesets.txt ] ]

    main:
    BIOC_CHIPENRICH_NARROW_PEAK_ENRICHMENT_POLYENRICH(ch_input)

    emit:
    tables   = BIOC_CHIPENRICH_NARROW_PEAK_ENRICHMENT_POLYENRICH.out.tables
    plots    = BIOC_CHIPENRICH_NARROW_PEAK_ENRICHMENT_POLYENRICH.out.plots
    objects  = BIOC_CHIPENRICH_NARROW_PEAK_ENRICHMENT_POLYENRICH.out.objects
    versions = BIOC_CHIPENRICH_NARROW_PEAK_ENRICHMENT_POLYENRICH.out.versions
}
