#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chipenrich — narrow_peak_enrichment
// Perform gene set enrichment testing for narrow genomic regions (e.g., transcription factors) using ChIP-Enrich, Poly-Enrich, or Hybrid-Enrich.
// Input: peaks_E2F4.bed, vignette_genesets.txt
// Container: quay.io/biocontainers/bioconductor-chipenrich:2.34.0--r45hdfd78af_0
// R packages: chipenrich
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHIPENRICH_NARROW_PEAK_ENRICHMENT {
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
    
    # Load required library
    library(chipenrich)
    
    # Define input file paths as specified by the user
    peaks_file = "peaks_E2F4.bed"
    gs_path = "vignette_genesets.txt"
    
    # Verify that the required input files exist in the working directory
    if (!file.exists(peaks_file)) {
      stop(paste("Required input file missing:", peaks_file))
    }
    if (!file.exists(gs_path)) {
      stop(paste("Required input file missing:", gs_path))
    }
    
    # Assign the peak file path to the variable name used in the documented code
    peaks_E2F4 = peaks_file
    
    # -----------------------------------------------------------------------------
    # Stage 1: Run chipenrich without mappability correction
    # -----------------------------------------------------------------------------
    message("Running chipenrich (without mappability)...")
    results = chipenrich(
      peaks = peaks_E2F4, 
      genome = 'hg19', 
      genesets = gs_path, 
      locusdef = "nearest_tss", 
      qc_plots = FALSE, 
      out_name = NULL, 
      n_cores = 1
    )
    results.ce = results\$results
    print("ChIP-Enrich (no mappability) top results:")
    print(results.ce[1:5, 1:5])
    
    # Save outputs
    write.csv(results.ce, "results_ce.csv", row.names = FALSE)
    saveRDS(results, "results_ce.rds")
    
    # -----------------------------------------------------------------------------
    # Stage 2: Run chipenrich with mappability correction
    # -----------------------------------------------------------------------------
    message("Running chipenrich (with mappability)...")
    results = chipenrich(
      peaks = peaks_E2F4, 
      genome = 'hg19', 
      genesets = gs_path, 
      locusdef = "nearest_tss", 
      mappability = 24, 
      qc_plots = FALSE, 
      out_name = NULL, 
      n_cores = 1
    )
    results.cem = results\$results
    print("ChIP-Enrich (with mappability) top results:")
    print(results.cem[1:5, 1:5])
    
    # Save outputs
    write.csv(results.cem, "results_cem.csv", row.names = FALSE)
    saveRDS(results, "results_cem.rds")
    
    # -----------------------------------------------------------------------------
    # Stage 3: Run standard polyenrich
    # -----------------------------------------------------------------------------
    message("Running polyenrich (standard)...")
    results = polyenrich(
      peaks = peaks_E2F4, 
      genome = 'hg19', 
      genesets = gs_path, 
      method = 'polyenrich', 
      locusdef = "nearest_tss", 
      qc_plots = FALSE, 
      out_name = NULL, 
      n_cores = 1
    )
    results.pe = results\$results
    print("Poly-Enrich (standard) top results:")
    print(results.pe[1:5, 1:5])
    
    # Save outputs
    write.csv(results.pe, "results_pe.csv", row.names = FALSE)
    saveRDS(results, "results_pe.rds")
    
    # -----------------------------------------------------------------------------
    # Stage 4: Run weighted polyenrich
    # -----------------------------------------------------------------------------
    message("Running polyenrich (weighted)...")
    results = polyenrich(
      peaks = peaks_E2F4, 
      genome = 'hg19', 
      genesets = gs_path, 
      method = "polyenrich_weighted", 
      locusdef = "enhancer_plus5kb", 
      qc_plots = FALSE, 
      out_name = NULL, 
      n_cores = 1
    )
    results.pe_weighted = results\$results
    print("Poly-Enrich (weighted) top results:")
    print(results.pe_weighted[1:5, 1:5])
    
    # Save outputs
    write.csv(results.pe_weighted, "results_pe_weighted.csv", row.names = FALSE)
    saveRDS(results, "results_pe_weighted.rds")
    
    # -----------------------------------------------------------------------------
    # Stage 5: Run hybridenrich
    # -----------------------------------------------------------------------------
    message("Running hybridenrich...")
    results = hybridenrich(
      peaks = peaks_E2F4, 
      genome = 'hg19', 
      genesets = gs_path, 
      locusdef = "nearest_tss", 
      qc_plots = F, 
      out_name = NULL, 
      n_cores = 1
    )
    results.hybrid = results\$results
    print("Hybrid-Enrich top results:")
    print(results.hybrid[1:5, 1:5])
    
    # Save outputs
    write.csv(results.hybrid, "results_hybrid.csv", row.names = FALSE)
    saveRDS(results, "results_hybrid.rds")
    
    # -----------------------------------------------------------------------------
    # Stage 6: Generate Diagnostic QC Plots
    # -----------------------------------------------------------------------------
    message("Generating diagnostic QC plots...")
    
    # 1. Peak distance to TSS distribution
    pdf("plot_dist_to_tss.pdf", width = 6, height = 6)
    plot_dist_to_tss(peaks = peaks_E2F4, genome = 'hg19')
    dev.off()
    
    # 2. Presence of peak versus locus length (ChIP-Enrich spline)
    pdf("plot_chipenrich_spline.pdf", width = 6, height = 6)
    plot_chipenrich_spline(peaks = peaks_E2F4, locusdef = 'nearest_tss', genome = 'hg19')
    dev.off()
    
    # 3. Number of peaks versus locus length (Poly-Enrich spline)
    pdf("plot_polyenrich_spline.pdf", width = 6, height = 6)
    plot_polyenrich_spline(peaks = peaks_E2F4, locusdef = 'nearest_tss', genome = 'hg19')
    dev.off()
    
    message("Pipeline completed successfully. All outputs saved to the working directory.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_CHIPENRICH_NARROW_PEAK_ENRICHMENT":
        chipenrich: \$(Rscript -e 'cat(as.character(packageVersion("chipenrich")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_narrow_peak_enrichment.csv versions.yml
    """
}

workflow BIOC_CHIPENRICH_NARROW_PEAK_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peaks_E2F4.bed, vignette_genesets.txt ] ]

    main:
    BIOC_CHIPENRICH_NARROW_PEAK_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_CHIPENRICH_NARROW_PEAK_ENRICHMENT.out.tables
    plots    = BIOC_CHIPENRICH_NARROW_PEAK_ENRICHMENT.out.plots
    objects  = BIOC_CHIPENRICH_NARROW_PEAK_ENRICHMENT.out.objects
    versions = BIOC_CHIPENRICH_NARROW_PEAK_ENRICHMENT.out.versions
}
