#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: norce — go_enrichment_ncrna_regions
// Perform GO enrichment analysis for genomic regions of interest.
// Input: ncRegion.txt
// Container: quay.io/biocontainers/bioconductor-norce:1.22.0--r45hdfd78af_0
// R packages: NoRCE, rtracklayer
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: dot plot, enrichment plot

nextflow.enable.dsl = 2

process BIOC_NORCE_GO_ENRICHMENT_NCRNA_REGIONS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-norce:1.22.0--r45hdfd78af_0"

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
    .bm_deps <- c("NoRCE", "rtracklayer")
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
    library(NoRCE)
    library(rtracklayer)
    
    # Define input file path (must exist in the working directory)
    input_file <- "ncRegion.txt"
    
    if (!file.exists(input_file)) {
      stop(paste("Required input file", input_file, "does not exist in the working directory."))
    }
    
    # Set parameters as documented
    setParameters("searchRegion", "all")
    
    # Import BED file using rtracklayer::import
    message("Importing BED file...")
    regionNC <- rtracklayer::import(input_file, format = "BED")
    
    # Run region-based GO enrichment using geneRegionGOEnricher
    message("Running geneRegionGOEnricher...")
    regionGO <- geneRegionGOEnricher(region = regionNC, org_assembly = 'hg19', near = TRUE)
    
    # Save the raw result object
    message("Saving results...")
    saveRDS(regionGO, file = "regionGO_results.rds")
    
    # Write enrichment results to a tabular format
    tryCatch({
      writeEnrichment(mrnaObject = regionGO, fileName = "enrichment_results.txt", sept = "\t", type = "pvalue")
      message("Enrichment results written to enrichment_results.txt")
    }, error = function(e) {
      warning("Could not write enrichment table: ", e\$message)
    })
    
    # Try to generate a dot plot
    tryCatch({
      pdf("enrichment_dotplot.pdf", width = 8, height = 8)
      drawDotPlot(mrnaObject = regionGO, type = "pvalue", n = 10)
      dev.off()
      message("Dot plot saved to enrichment_dotplot.pdf")
    }, error = function(e) {
      if (dev.cur() > 1) dev.off()
      warning("Could not generate dot plot: ", e\$message)
    })
    
    # Try to generate a GO DAG
    tryCatch({
      getGoDag(mrnaObject = regionGO, type = 'pvalue', n = 5, filename = 'dag.png', imageFormat = "png")
      message("GO DAG saved to dag.png")
    }, error = function(e) {
      warning("Could not generate GO DAG: ", e\$message)
    })
    
    message("Pipeline completed.")

    writeLines(c(
        '"BIOC_NORCE_GO_ENRICHMENT_NCRNA_REGIONS":',
        paste0('        norce: ', as.character(packageVersion("norce")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_go_enrichment_ncrna_regions.csv versions.yml
    """
}

workflow BIOC_NORCE_GO_ENRICHMENT_NCRNA_REGIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ncRegion.txt ] ]

    main:
    BIOC_NORCE_GO_ENRICHMENT_NCRNA_REGIONS(ch_input)

    emit:
    tables   = BIOC_NORCE_GO_ENRICHMENT_NCRNA_REGIONS.out.tables
    plots    = BIOC_NORCE_GO_ENRICHMENT_NCRNA_REGIONS.out.plots
    objects  = BIOC_NORCE_GO_ENRICHMENT_NCRNA_REGIONS.out.objects
    versions = BIOC_NORCE_GO_ENRICHMENT_NCRNA_REGIONS.out.versions
}
